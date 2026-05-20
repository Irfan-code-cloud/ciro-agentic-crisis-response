import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

String? _basicAuthHeader;

void main() {
  runApp(const CiroApp());
}

class CiroApp extends StatelessWidget {
  const CiroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CIRO | ISLAMABAD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090E14),
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData(brightness: Brightness.dark).textTheme),
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          secondary: Colors.redAccent,
          surface: Color(0xFF151C26),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF05080C),
          elevation: 0,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

class CiroDashboardMobile extends StatefulWidget {
  const CiroDashboardMobile({super.key});

  @override
  State<CiroDashboardMobile> createState() => _CiroDashboardMobileState();
}

class _CiroDashboardMobileState extends State<CiroDashboardMobile> {
  bool _isLoading = false;
  String _status = 'Ready';
  Map<String, dynamic>? _analysisData;
  List<LatLng> _blockedRoutePoints = [];
  List<LatLng> _detourRoutePoints = [];
  bool _isUrdu = false;
  bool _isBroadcasting = false;
  bool _kpisDispatched = false;
  bool _isMapFullScreen = false;
  double _detourDistanceKm = 0.0;
  int _detourDurationMins = 0;

  // Feature A: WhatsApp Citizen Bot Live Reports
  List<dynamic> _liveReports = [];
  Timer? _pollingTimer;
  final String liveReportsUrl = 'https://ciro-agentic-crisis-response-295512477034.us-central1.run.app/api/live-reports';
  final String broadcastUrl = 'https://ciro-agentic-crisis-response-295512477034.us-central1.run.app/api/broadcast';

  // Note: If testing on a physical Android device, replace 10.0.2.2 with your PC's local IP address (e.g., 192.168.1.x).
  final String backendUrl = 'https://ciro-agentic-crisis-response-295512477034.us-central1.run.app/api/analyze';
  LatLng? _geocode(String location) {
    final lowerLoc = location.toLowerCase();
    if (lowerLoc.contains('f-8')) return const LatLng(33.7104, 73.0369);
    if (lowerLoc.contains('g-10')) return const LatLng(33.6700, 73.0200);
    if (lowerLoc.contains('e-11')) return const LatLng(33.6980, 72.9750);
    if (lowerLoc.contains('kashmir') || lowerLoc.contains('srinagar')) return const LatLng(33.6850, 72.9950);
    return null;
  }

  Future<Map<String, dynamic>> _getStreetRoute(LatLng start, LatLng end) async {
    try {
      final url = 'http://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?geometries=geojson';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(milliseconds: 1500));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final coordinates = data['routes'][0]['geometry']['coordinates'] as List;
          final List<LatLng> coordinatesList = coordinates.map((coord) => LatLng(coord[1] as double, coord[0] as double)).toList();
          final distance = double.tryParse(data['routes'][0]['distance']?.toString() ?? '0.0') ?? 0.0;
          final duration = double.tryParse(data['routes'][0]['duration']?.toString() ?? '0.0') ?? 0.0;
          return {
            'points': coordinatesList,
            'distance': distance,
            'duration': duration,
          };
        }
      }
    } catch (e) {
      debugPrint('OSRM Routing Error: $e');
    }
    // Fallback to straight line if API fails
    return {
      'points': [start, end],
      'distance': 0.0,
      'duration': 0.0,
    };
  }

  Future<void> _fetchTacticalData([String? customSignal]) async {
    setState(() {
      _isLoading = true;
      _analysisData = null; // Fix UI ghosting
      _status = 'Loading';
    });

    try {
      String url = customSignal != null 
          ? '$backendUrl?signal=${Uri.encodeComponent(customSignal)}' 
          : backendUrl;
      url += (url.contains('?') ? '&' : '?') + 'lang=${_isUrdu ? 'ur' : 'en'}';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': _basicAuthHeader!,
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final analysis = data['analysis'];
        
        setState(() {
          _analysisData = analysis;
          _blockedRoutePoints = []; // Clear old routes while computing
          _detourRoutePoints = [];
          _detourDistanceKm = 0.0;
          _detourDurationMins = 0;
          _status = 'Success';
          _isLoading = false;
        });

        if (analysis['routing'] != null) {
          final routing = analysis['routing'];
          final blockedStart = LatLng(routing['blocked_start']['lat'], routing['blocked_start']['lng']);
          final blockedEnd = LatLng(routing['blocked_end']['lat'], routing['blocked_end']['lng']);
          final detourStart = LatLng(routing['detour_start']['lat'], routing['detour_start']['lng']);
          final detourEnd = LatLng(routing['detour_end']['lat'], routing['detour_end']['lng']);
          
          final blockedData = await _getStreetRoute(blockedStart, blockedEnd);
          final detourData = await _getStreetRoute(detourStart, detourEnd);
          
          setState(() {
            _blockedRoutePoints = blockedData['points'];
            _detourRoutePoints = detourData['points'];
            _detourDistanceKm = (detourData['distance'] as double) / 1000;
            _detourDurationMins = (detourData['duration'] as double) ~/ 60;
          });
        }
      } else {
        setState(() {
          _status = 'Error: HTTP ${response.statusCode}';
          _isLoading = false;
        });
      }
    } on TimeoutException catch (_) {
      setState(() {
        _status = 'Error: Request timed out (30s)';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: ${e.toString()}';
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI Data Sync Error. Retrying...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchLiveReports();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLiveReports() async {
    try {
      final response = await http.get(
        Uri.parse(liveReportsUrl),
        headers: {
          'Authorization': _basicAuthHeader!,
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        try {
          final parsedData = json.decode(response.body) as List<dynamic>;
          if (parsedData.length != _liveReports.length) {
            if (_liveReports.isNotEmpty && parsedData.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: const [
                      Icon(Icons.notification_important, color: Colors.redAccent),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'New Citizen Report Received!',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: const Color(0xFF1A1A24),
                  behavior: SnackBarBehavior.floating,
                  margin: EdgeInsets.only(
                    bottom: MediaQuery.of(context).size.height - 150,
                    left: 16,
                    right: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.redAccent, width: 1.5),
                  ),
                  elevation: 10,
                ),
              );
            }
            setState(() {
              _liveReports = parsedData;
            });
          }
        } catch (e) {
          print('JSON Parse Error: $e');
        }
      }
    } catch (e) {
      // Fail silently on general network issues to not disrupt the UX
    }
  }

  Future<void> _executeCommunications() async {
    if (_analysisData == null) return;
    setState(() {
      _isBroadcasting = true;
    });

    try {
      final payload = {
        'location': _analysisData!['epicenter'] != null 
            ? '${_analysisData!['epicenter']['lat']}, ${_analysisData!['epicenter']['lng']}' 
            : 'Islamabad',
        'crisis_type': _analysisData!['crisis_type_short']?.toString() ?? 'Emergency',
        'recommended_actions': _analysisData!['recommended_actions'] ?? [],
      };

      final response = await http.post(
        Uri.parse(broadcastUrl),
        headers: {
          'Authorization': _basicAuthHeader!,
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _kpisDispatched = true;
        });
        _showCommunicationsModal(data);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to generate communications.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() {
        _isBroadcasting = false;
      });
    }
  }

  void _showCommunicationsModal(Map<String, dynamic> comms) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            top: 24.0,
            left: 24.0,
            right: 24.0,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.cell_tower, color: Colors.blueAccent, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'MULTI-CHANNEL BROADCAST',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white24),
                const SizedBox(height: 16),
                
                // Twitter Post
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.lightBlueAccent.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.flutter_dash, color: Colors.lightBlueAccent, size: 20),
                          SizedBox(width: 8),
                          Text('Official X/Twitter Draft', style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.w400, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(comms['twitter_post']?.toString() ?? '', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w300)),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final twitterText = comms['twitter_post']?.toString() ?? '';
                            final Uri tweetUrl = Uri.parse('https://twitter.com/intent/tweet?text=${Uri.encodeComponent(twitterText)}');
                            try {
                              if (await canLaunchUrl(tweetUrl)) {
                                await launchUrl(tweetUrl, mode: LaunchMode.externalApplication);
                              } else {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Could not open Twitter/X intent URL.')),
                                );
                              }
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error launching X/Twitter: $e')),
                              );
                            }
                          },
                          icon: const Icon(Icons.share, size: 16),
                          label: const Text('Share on X'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white10,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // SMS Alert
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.sms, color: Colors.greenAccent, size: 20),
                          SizedBox(width: 8),
                          Text('Public SMS Alert', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w400, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(comms['sms_alert']?.toString() ?? '', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w300)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Internal Email
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.email, color: Colors.orangeAccent, size: 20),
                          SizedBox(width: 8),
                          Text('Command Dispatch Email', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w400, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(comms['internal_email']?.toString() ?? '', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w300)),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final emailText = comms['internal_email']?.toString() ?? '';
                            final String subject = Uri.encodeComponent('URGENT: Urban Crisis Response');
                            final String body = Uri.encodeComponent(emailText);
                            final Uri emailLaunchUri = Uri.parse('mailto:?subject=$subject&body=$body');
                            
                            try {
                              await launchUrl(emailLaunchUri);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Error launching email client.', style: TextStyle(color: Colors.white)),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.mail, size: 16),
                          label: const Text('Draft Email'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white10,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'DONE',
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSignalInjector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.podcasts, size: 48, color: Colors.amber),
              const SizedBox(height: 16),
              Text(
                'Inject Crisis Signal (Simulation)',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  // fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Button 1 (Flood)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _fetchTacticalData('G-10 mein pani bhar gaya hai, gaariyan phans gayi hain!');
                  },
                  icon: const Icon(Icons.water_drop),
                  label: const Text('Simulate: G-10 Flash Flood'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: GoogleFonts.poppins(fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Button 2 (Fire)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _fetchTacticalData('Massive fire outbreak at F-8 Markaz plaza. People trapped on 3rd floor!');
                  },
                  icon: const Icon(Icons.local_fire_department),
                  label: const Text('Simulate: F-8 Markaz Commercial Fire'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: GoogleFonts.poppins(fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Button 3 (Accident)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _fetchTacticalData('Terrible 4-car pileup on Srinagar Highway near E-11. Total gridlock, ambulances needed.');
                  },
                  icon: const Icon(Icons.car_crash),
                  label: const Text('Simulate: E-11 Highway Pileup'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: GoogleFonts.poppins(fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.shield, color: Colors.amber),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'CIRO COMMAND CENTER',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _status == 'Ready' ? Colors.grey : 
                       _status == 'Success' ? Colors.greenAccent :
                       _status == 'Loading' ? Colors.amber : Colors.redAccent,
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
        actions: [
          if (isDesktop)
            IconButton(
              icon: const Icon(Icons.receipt_long, color: Colors.amber),
              tooltip: 'Complaint Registry',
              onPressed: _showComplaintRegistry,
            ),
          if (isDesktop) ...[
            const SizedBox(width: 8),
            const Text('اردو', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            Switch(
              value: _isUrdu,
              activeColor: Colors.amber,
              onChanged: (val) {
                setState(() {
                  _isUrdu = val;
                });
                _fetchTacticalData();
              },
            ),
            const SizedBox(width: 16),
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_circle, color: Colors.white70, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'CDA_officer',
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.logout, color: Colors.redAccent.withOpacity(0.8)),
              tooltip: 'Secure Logout',
              onPressed: () {
                _basicAuthHeader = null;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      endDrawer: isDesktop ? null : _buildMobileDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _showSignalInjector,
        backgroundColor: Colors.amber.shade700,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.podcasts),
        label: const Text('INJECT SIGNAL', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          if (_isLoading) const LinearProgressIndicator(color: Colors.amber),
          
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Section: Interactive Map
                  Container(
                    height: _isMapFullScreen ? MediaQuery.of(context).size.height * 0.8 : 350,
                    color: const Color(0xFFE5E5E5), // Prevents white flash
                    child: Stack(
                      children: [
                        FlutterMap(
                          options: const MapOptions(
                            initialCenter: LatLng(33.6850, 72.9950),
                            initialZoom: 13.0,
                            interactionOptions: InteractionOptions(
                              flags: InteractiveFlag.all,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              subdomains: const ['a', 'b', 'c'],
                              userAgentPackageName: 'com.ciro.dashboard',
                            ),
                            if (_analysisData != null) ...[
                              CircleLayer(
                                circles: [
                                  if (_analysisData!['epicenter'] != null)
                                    CircleMarker(
                                      point: LatLng(
                                        _analysisData!['epicenter']['lat'],
                                        _analysisData!['epicenter']['lng'],
                                      ),
                                      color: Colors.red.withOpacity(0.35),
                                      borderColor: Colors.red,
                                      borderStrokeWidth: 3,
                                      useRadiusInMeter: true,
                                      radius: 800, // 800m Critical Zone radius
                                    ),
                                ],
                              ),
                              PolylineLayer(
                                polylines: [
                                  if (_blockedRoutePoints.isNotEmpty)
                                    // Polyline 1 (BEFORE) - Blocked Route
                                    Polyline(
                                      points: _blockedRoutePoints,
                                      color: Colors.black87, // Changed from red for better contrast
                                      strokeWidth: 5.0,
                                    ),
                                  if (_detourRoutePoints.isNotEmpty)
                                    // Polyline 2 (AFTER) - Active Reroute
                                    Polyline(
                                      points: _detourRoutePoints,
                                      color: Colors.blue.shade800, // Darker blue
                                      strokeWidth: 4.0,
                                    ),
                                ],
                              ),
                              MarkerLayer(
                                markers: [
                                  if (_analysisData!['epicenter'] != null)
                                    Marker(
                                      point: LatLng(
                                        _analysisData!['epicenter']['lat'],
                                        _analysisData!['epicenter']['lng'],
                                      ),
                                      width: 150,
                                      height: 150,
                                      child: Tooltip(
                                        message: _analysisData!['crisis_type_short']?.toString() ?? 'Crisis Epicenter',
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.9),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        textStyle: GoogleFonts.poppins(color: Colors.white, fontSize: 12),
                                        child: _buildGlowingMarker(_analysisData!['crisis_type_short']?.toString() ?? 'CRISIS'),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            MarkerLayer(
                              markers: [
                                ..._liveReports.map((report) {
                                  final double lat = double.tryParse(report['lat']?.toString() ?? '33.6938') ?? 33.6938;
                                  final double lng = double.tryParse(report['lng']?.toString() ?? '73.0053') ?? 73.0053;
                                  final locName = report['location']?.toString() ?? '';
                                  return Marker(
                                    point: LatLng(lat, lng),
                                    width: 150,
                                    height: 150,
                                    child: Tooltip(
                                      message: report['crisis_type']?.toString() ?? 'Citizen Report',
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.9),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      textStyle: GoogleFonts.poppins(color: Colors.white, fontSize: 12),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          _fetchTacticalData(report['translated_summary']?.toString() ?? 'Emergency at $locName');
                                        },
                                        child: Container(
                                          alignment: Alignment.center,
                                          child: _buildGlowingMarker(report['crisis_type']?.toString() ?? 'REPORT'),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
                          ],
                        ),
                        
                        // Map Overlays
                        if (_analysisData == null && _liveReports.isEmpty)
                          Container(
                            color: Colors.black.withOpacity(0.75),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Colors.amber),
                                  SizedBox(height: 16),
                                  Text(
                                    'AWAITING TELEMETRY FUSION...',
                                    style: TextStyle(
                                      color: Colors.amber,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          Positioned(
                            top: 12,
                            left: 12,
                            right: 68, // Shifted to make room for full-screen toggle button
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black, // Solid black
                                    border: Border.all(color: Colors.red.withOpacity(0.5)),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'CRITICAL ZONES',
                                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black, // Solid black
                                    border: Border.all(color: Colors.blue.shade800.withOpacity(0.8)),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'ACTIVE REROUTE',
                                    style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold, fontSize: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_detourDistanceKm > 0)
                            Positioned(
                              top: 48,
                              left: 12,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.8),
                                  border: Border.all(color: Colors.amber, width: 1.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'TACTICAL REROUTE ACTIVE',
                                      style: GoogleFonts.poppins(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Distance: ${_detourDistanceKm.toStringAsFixed(1)} km',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Est. Delay: $_detourDurationMins mins',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Positioned(
                            bottom: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.location_on, color: Colors.red, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Locations',
                                        style: GoogleFonts.poppins(
                                          color: Colors.black,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        color: Colors.black87, // Updated to match the map line
                                        height: 4,
                                        width: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Critical Zone',
                                        style: GoogleFonts.poppins(
                                          color: Colors.black,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        color: Colors.blue.shade800, // Match the new darker blue line
                                        height: 4,
                                        width: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Active Reroute',
                                        style: GoogleFonts.poppins(
                                          color: Colors.black,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        
                        // Full Screen Toggle Button (Always visible on top right)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: CircleAvatar(
                            backgroundColor: Colors.black54,
                            radius: 20,
                            child: IconButton(
                              icon: Icon(_isMapFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white, size: 20),
                              onPressed: () {
                                setState(() {
                                  _isMapFullScreen = !_isMapFullScreen;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Section: AI Intelligence Report
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _analysisData == null
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: 40.0),
                              child: Text(
                                'AWAITING TACTICAL DATA',
                                style: TextStyle(color: Colors.white38, letterSpacing: 2.0),
                              ),
                            ),
                          )
                        : Directionality(
                            textDirection: _isUrdu ? TextDirection.rtl : TextDirection.ltr,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isUrdu ? 'مصنوعی ذہانت کی رپورٹ' : 'AI INTELLIGENCE REPORT',
                                  style: _isUrdu 
                                    ? GoogleFonts.notoNastaliqUrdu(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.w400)
                                    : GoogleFonts.inter(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.w400, letterSpacing: 1.5),
                                ),
                              const SizedBox(height: 8),
                              const Divider(color: Colors.white24),
                              const SizedBox(height: 16),

                              // Card 1: DETECTED SITUATION
                              _buildSectionCard(
                                title: _isUrdu ? 'دریافت شدہ صورتحال' : 'DETECTED SITUATION',
                                icon: Icons.warning_amber_rounded,
                                color: Colors.redAccent,
                                child: Text(
                                  _analysisData!['detected_situation']?.toString() ?? 'Unknown',
                                  style: _isUrdu 
                                    ? GoogleFonts.notoNastaliqUrdu(fontSize: 14, color: Colors.white, height: 1.8, fontWeight: FontWeight.w300)
                                    : GoogleFonts.poppins(fontSize: 14, color: Colors.white, height: 1.4, fontWeight: FontWeight.w300),
                                  textDirection: _isUrdu ? TextDirection.rtl : TextDirection.ltr,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Card 2: CURRENT IMPACTS
                              _buildSectionCard(
                                title: _isUrdu ? 'موجودہ اثرات' : 'CURRENT IMPACTS',
                                icon: Icons.flash_on,
                                color: Colors.orangeAccent,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: (_analysisData!['impact'] as List<dynamic>? ?? []).map((impact) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10.0),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(top: 4.0),
                                            child: Icon(Icons.circle, size: 6, color: Colors.orangeAccent),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              impact.toString(),
                                              style: _isUrdu 
                                                ? GoogleFonts.notoNastaliqUrdu(fontSize: 14, color: Colors.white, height: 1.8, fontWeight: FontWeight.w300)
                                                : GoogleFonts.poppins(fontSize: 14, color: Colors.white, height: 1.4, fontWeight: FontWeight.w300),
                                              textDirection: _isUrdu ? TextDirection.rtl : TextDirection.ltr,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Card 3: RECOMMENDED ACTIONS
                              _buildSectionCard(
                                title: _isUrdu ? 'تجویز کردہ اقدامات' : 'RECOMMENDED ACTIONS',
                                icon: Icons.check_circle_outline,
                                color: Colors.greenAccent,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: (_analysisData!['recommended_actions'] as List<dynamic>? ?? []).map((action) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10.0),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(top: 2.0),
                                            child: Icon(Icons.check, size: 16, color: Colors.greenAccent),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              action.toString(),
                                              style: _isUrdu 
                                                ? GoogleFonts.notoNastaliqUrdu(fontSize: 14, color: Colors.white, height: 1.8, fontWeight: FontWeight.w300)
                                                : GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w300, color: Colors.white, height: 1.4),
                                              textDirection: _isUrdu ? TextDirection.rtl : TextDirection.ltr,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Builder(
                                builder: (context) {
                                  final kpis = _analysisData!['resource_kpis'] as List<dynamic>?;
                                  
                                  String fireKpi = 'Pending';
                                  String ambKpi = 'Pending';
                                  String polKpi = 'Pending';
                                  
                                  String fireReasoning = 'Awaiting Agent Tactical Reasoning.';
                                  String ambReasoning = 'Awaiting Agent Tactical Reasoning.';
                                  String polReasoning = 'Awaiting Agent Tactical Reasoning.';
                                  
                                  if (kpis != null) {
                                    final fireUnit = kpis.firstWhere((k) => k['label'].toString().contains('Fire'), orElse: () => null);
                                    if (fireUnit != null) {
                                      fireKpi = '${fireUnit['value']} ${_kpisDispatched ? "Dispatched" : "Active"}';
                                      fireReasoning = fireUnit['reasoning']?.toString() ?? fireReasoning;
                                    }
                                    
                                    final ambUnit = kpis.firstWhere((k) => k['label'].toString().contains('Ambulance'), orElse: () => null);
                                    if (ambUnit != null) {
                                      ambKpi = '${ambUnit['value']} ${_kpisDispatched ? "Dispatched" : "En Route"}';
                                      ambReasoning = ambUnit['reasoning']?.toString() ?? ambReasoning;
                                    }
                                    
                                    final polUnit = kpis.firstWhere((k) => k['label'].toString().contains('Police'), orElse: () => null);
                                    if (polUnit != null) {
                                      polKpi = '${polUnit['value']} ${_kpisDispatched ? "Dispatched" : "Securing"}';
                                      polReasoning = polUnit['reasoning']?.toString() ?? polReasoning;
                                    }
                                  }

                                  // Responsive Layout Check
                                  if (isDesktop) {
                                    // Laptop/Web View: Side-by-side Row
                                    return Row(
                                      children: [
                                        Expanded(
                                          child: _buildKpiCard(
                                            title: 'Fire Units',
                                            icon: Icons.fire_truck,
                                            value: fireKpi,
                                            color: Colors.redAccent,
                                            reasoning: fireReasoning,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _buildKpiCard(
                                            title: 'Ambulances',
                                            icon: Icons.medical_services,
                                            value: ambKpi,
                                            color: Colors.blueAccent,
                                            reasoning: ambReasoning,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _buildKpiCard(
                                            title: 'Police',
                                            icon: Icons.local_police,
                                            value: polKpi,
                                            color: Colors.amber,
                                            reasoning: polReasoning,
                                          ),
                                        ),
                                      ],
                                    );
                                  } else {
                                    // Mobile View: Stacked Column
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        _buildKpiCard(
                                          title: 'Fire Units',
                                          icon: Icons.fire_truck,
                                          value: fireKpi,
                                          color: Colors.redAccent,
                                          reasoning: fireReasoning,
                                        ),
                                        const SizedBox(height: 12),
                                        _buildKpiCard(
                                          title: 'Ambulances',
                                          icon: Icons.medical_services,
                                          value: ambKpi,
                                          color: Colors.blueAccent,
                                          reasoning: ambReasoning,
                                        ),
                                        const SizedBox(height: 12),
                                        _buildKpiCard(
                                          title: 'Police',
                                          icon: Icons.local_police,
                                          value: polKpi,
                                          color: Colors.amber,
                                          reasoning: polReasoning,
                                        ),
                                      ],
                                    );
                                  }
                                } // This closes the builder function
                              ), // This closes the Builder widget

                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                  child: ElevatedButton.icon(
                                  onPressed: _isBroadcasting ? null : _executeCommunications,
                                  icon: _isBroadcasting 
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                      : const Icon(Icons.satellite_alt),
                                  label: Text(_isBroadcasting ? 'BROADCASTING...' : 'EXECUTE COMMUNICATIONS'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amber.shade600,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 80), // Padding for FAB
                            ],
                          ),
                          ), // End Directionality
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowingMarker(String crisisType) {
    return const Center(
      child: Icon(Icons.location_on, color: Colors.red, size: 48),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF090E14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: _isUrdu
                  ? GoogleFonts.notoNastaliqUrdu(color: color, fontWeight: FontWeight.w400, fontSize: 16)
                  : GoogleFonts.poppins(color: color, fontWeight: FontWeight.w400, letterSpacing: 1.1, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildKpiCard({required String title, required IconData icon, required String value, required Color color, required String reasoning}) {
    return InkWell(
      onTap: () => _showKpiReasoningDialog(context, title, reasoning),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF151C26),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 10,
              spreadRadius: 1,
            )
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The Main Centered Content
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 8),
                Text(title, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(value, style: GoogleFonts.poppins(color: color, fontSize: 14, fontWeight: FontWeight.w600), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
            // The Subtle Tap Icon in the Top Right
            const Positioned(
              top: 0,
              right: 0,
              child: Icon(
                Icons.touch_app, // A universal "tap here" hand icon
                color: Colors.white30, // Kept dim so it doesn't distract from the main data
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showKpiReasoningDialog(BuildContext context, String title, String reasoning) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151C26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.amber, width: 1)),
          title: Text('AI Tactical Reasoning:\n$title', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w400, fontSize: 18)),
          content: Text(reasoning, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14, height: 1.5, fontWeight: FontWeight.w300)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Acknowledge', style: GoogleFonts.poppins(color: Colors.amber, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }

  void _showComplaintRegistry() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF090E14),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          contentPadding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.amber, width: 1.5),
          ),
          title: Text(
            'CITIZEN COMPLAINT REGISTRY',
            style: GoogleFonts.poppins(
              color: Colors.amber,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: _liveReports.isEmpty
                ? Center(
                    child: Text(
                      'No complaints registered in system.',
                      style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w300),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: _liveReports.length,
                          itemBuilder: (context, index) {
                            final report = _liveReports[index];
                            final severity = report['severity']?.toString() ?? 'Unknown';
                            Color severityColor = Colors.green;
                            if (severity.toLowerCase().contains('high')) {
                              severityColor = Colors.redAccent;
                            } else if (severity.toLowerCase().contains('medium')) {
                              severityColor = Colors.amber;
                            }

                            return Card(
                              color: const Color(0xFF151C26),
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Top Row: Title + Severity Badge
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${report['crisis_type']?.toString() ?? 'Citizen Alert'} - ${report['location']?.toString() ?? 'Islamabad'}',
                                            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: severityColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: severityColor.withOpacity(0.4), width: 1),
                                          ),
                                          child: Text(severity.toUpperCase(), style: GoogleFonts.poppins(color: severityColor, fontWeight: FontWeight.w600, fontSize: 10)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // Middle: Subtitle (Full Width)
                                    Text(
                                      report['translated_summary']?.toString() ?? 'Evaluating situation...',
                                      style: GoogleFonts.poppins(color: Colors.white70, fontWeight: FontWeight.w300, fontSize: 12, height: 1.4),
                                    ),
                                    const SizedBox(height: 16),
                                    // Bottom Row: Delete Button (Right Aligned)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1.5),
                                        ),
                                        child: IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                          onPressed: () => _deleteSingleReport(report['id']?.toString() ?? '', context),
                                          tooltip: 'Delete Record',
                                          constraints: const BoxConstraints(), // Strips default material padding
                                          padding: const EdgeInsets.all(8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _showPurgeDialog(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade900,
                            foregroundColor: Colors.white,
                            elevation: 6,
                            shadowColor: Colors.redAccent.withOpacity(0.4),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Colors.redAccent.withOpacity(0.5), width: 1.5),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'DELETE ALL DATA',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'CLOSE TERMINAL',
                style: GoogleFonts.poppins(
                  color: Colors.amber,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteSingleReport(String id, BuildContext context) async {
    if (id.isEmpty) return;
    final String deleteBaseUrl = 'https://ciro-agentic-crisis-response-295512477034.us-central1.run.app/api/live-reports';
    final String deleteUrl = '$deleteBaseUrl/$id';
    try {
      final response = await http.delete(
        Uri.parse(deleteUrl),
        headers: {
          'Authorization': _basicAuthHeader!,
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report deleted successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        await _fetchLiveReports();
        Navigator.pop(context);
        _showComplaintRegistry();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete report: HTTP ${response.statusCode}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showPurgeDialog(BuildContext parentContext) {
    final TextEditingController confirmController = TextEditingController();
    bool isPurgeEnabled = false;
    showDialog(
      context: parentContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF090E14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.redAccent, width: 1.5),
              ),
              title: Text(
                '⚠️ SYSTEM PURGE',
                style: GoogleFonts.poppins(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'This action cannot be undone. Type PURGE to confirm deletion of all citizen records.',
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmController,
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Type PURGE here',
                      hintStyle: GoogleFonts.poppins(color: Colors.white30, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF151C26),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.redAccent),
                      ),
                    ),
                    onChanged: (val) {
                      setDialogState(() {
                        isPurgeEnabled = val == 'PURGE';
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'CANCEL',
                    style: GoogleFonts.poppins(color: Colors.white70, fontWeight: FontWeight.w500, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: isPurgeEnabled
                      ? () async {
                          final String purgeUrl = 'https://ciro-agentic-crisis-response-295512477034.us-central1.run.app/api/live-reports/purge/all';
                          try {
                            final response = await http.delete(
                              Uri.parse(purgeUrl),
                              headers: {
                                'Authorization': _basicAuthHeader!,
                                'Content-Type': 'application/json',
                              },
                            ).timeout(const Duration(seconds: 10));
                            if (response.statusCode == 200) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                const SnackBar(
                                  content: Text('All records successfully purged from system.'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              Navigator.pop(dialogContext);
                              Navigator.pop(parentContext);
                              await _fetchLiveReports();
                            } else {
                              if (!mounted) return;
                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                SnackBar(
                                  content: Text('Purge failed: HTTP ${response.statusCode}'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(
                                content: Text('Error: ${e.toString()}'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      : null,
                  child: Text(
                    'CONFIRM PURGE',
                    style: GoogleFonts.poppins(
                      color: isPurgeEnabled ? Colors.redAccent : Colors.white24,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF151C26),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFF05080C),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'CIRO COMMAND',
                  style: GoogleFonts.poppins(
                    color: Colors.amber,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.account_circle, color: Colors.white70, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'CDA_officer',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ListTile(
            title: Text(
              'Urdu Translation',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            ),
            trailing: Switch(
              value: _isUrdu,
              activeColor: Colors.amber,
              onChanged: (val) {
                setState(() {
                  _isUrdu = val;
                });
                _fetchTacticalData();
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long, color: Colors.amber),
            title: Text(
              'Complaint Registry',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            ),
            onTap: () {
              Navigator.pop(context); // Close drawer
              _showComplaintRegistry();
            },
          ),
          const Divider(color: Colors.white12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'LIVE CITIZEN REPORTS',
              style: GoogleFonts.poppins(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
          if (_liveReports.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'No active citizen reports.',
                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w300),
              ),
            )
          else
            ..._liveReports.map((report) {
              return ListTile(
                dense: true,
                leading: const Icon(Icons.emergency_share, color: Colors.redAccent, size: 20),
                title: Text(
                  report['crisis_type']?.toString() ?? 'Citizen Alert',
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
                ),
                subtitle: Text(
                  report['translated_summary']?.toString() ?? report['location']?.toString() ?? 'Evaluating situation...',
                  style: GoogleFonts.poppins(color: Colors.white70, fontWeight: FontWeight.w300, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.pop(context); // Close the drawer
                  _fetchTacticalData(report['translated_summary']?.toString() ?? 'Emergency at ${report['location']}');
                },
              );
            }).toList(),
          const Divider(color: Colors.white12),
          ListTile(
            leading: Icon(Icons.logout, color: Colors.redAccent.withOpacity(0.8)),
            title: Text(
              'Secure Logout',
              style: GoogleFonts.poppins(
                color: Colors.redAccent,
                fontWeight: FontWeight.w300,
                fontSize: 14,
              ),
            ),
            onTap: () {
              _basicAuthHeader = null;
              Navigator.pop(context); // Close the drawer
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _login() async {
    final String username = _usernameController.text.trim();
    final String password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both username and password'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final String credentials = base64Encode(utf8.encode('$username:$password'));
    final String authHeader = 'Basic $credentials';
    final String testUrl = 'https://ciro-agentic-crisis-response-295512477034.us-central1.run.app/api/live-reports';

    try {
      final response = await http.get(
        Uri.parse(testUrl),
        headers: {
          'Authorization': authHeader,
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _basicAuthHeader = authHeader;
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const CiroDashboardMobile()),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Access Denied: Invalid Credentials'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090E14),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 80,
                color: Colors.amber,
              ),
              const SizedBox(height: 24),
              Text(
                'CIRO COMMAND TERMINAL',
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'ISLAMABAD EMERGENCY SYSTEM',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.5,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _usernameController,
                style: GoogleFonts.poppins(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Username',
                  labelStyle: GoogleFonts.poppins(color: Colors.white70, fontWeight: FontWeight.w300),
                  prefixIcon: const Icon(Icons.person_outline, color: Colors.amber),
                  filled: true,
                  fillColor: const Color(0xFF151C26),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.amber, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: GoogleFonts.poppins(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: GoogleFonts.poppins(color: Colors.white70, fontWeight: FontWeight.w300),
                  prefixIcon: const Icon(Icons.lock_outline, color: Colors.amber),

                  // <-- NEW: The Eye Icon Button -->
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white54,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),

                  filled: true,
                  fillColor: const Color(0xFF151C26),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.amber, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    elevation: 4,
                    shadowColor: Colors.amber.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          'AUTHORIZE ACCESS',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}