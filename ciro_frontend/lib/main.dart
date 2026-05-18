import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';

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
      home: const CiroDashboardMobile(),
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

  // Feature A: WhatsApp Citizen Bot Live Reports
  List<dynamic> _liveReports = [];
  Timer? _pollingTimer;
  final String liveReportsUrl = kIsWeb ? 'http://127.0.0.1:8000/api/live-reports' : 'http://10.0.2.2:8000/api/live-reports';
  final String broadcastUrl = kIsWeb ? 'http://127.0.0.1:8000/api/broadcast' : 'http://10.0.2.2:8000/api/broadcast';

  // Note: If testing on a physical Android device, replace 10.0.2.2 with your PC's local IP address (e.g., 192.168.1.x).
  final String backendUrl = kIsWeb ? 'http://127.0.0.1:8000/api/analyze' : 'http://10.0.2.2:8000/api/analyze';

  LatLng? _geocode(String location) {
    final lowerLoc = location.toLowerCase();
    if (lowerLoc.contains('f-8')) return const LatLng(33.7104, 73.0369);
    if (lowerLoc.contains('g-10')) return const LatLng(33.6700, 73.0200);
    if (lowerLoc.contains('e-11')) return const LatLng(33.6980, 72.9750);
    if (lowerLoc.contains('kashmir') || lowerLoc.contains('srinagar')) return const LatLng(33.6850, 72.9950);
    return null;
  }

  Future<List<LatLng>> _getStreetRoute(LatLng start, LatLng end) async {
    try {
      final url = 'http://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?geometries=geojson';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(milliseconds: 1500));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final coordinates = data['routes'][0]['geometry']['coordinates'] as List;
          return coordinates.map((coord) => LatLng(coord[1] as double, coord[0] as double)).toList();
        }
      }
    } catch (e) {
      debugPrint('OSRM Routing Error: $e');
    }
    // Fallback to straight line if API fails
    return [start, end];
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
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final analysis = data['analysis'];
        
        setState(() {
          _analysisData = analysis;
          _blockedRoutePoints = []; // Clear old routes while computing
          _detourRoutePoints = [];
          _status = 'Success';
          _isLoading = false;
        });

        if (analysis['routing'] != null) {
          final routing = analysis['routing'];
          final blockedStart = LatLng(routing['blocked_start']['lat'], routing['blocked_start']['lng']);
          final blockedEnd = LatLng(routing['blocked_end']['lat'], routing['blocked_end']['lng']);
          final detourStart = LatLng(routing['detour_start']['lat'], routing['detour_start']['lng']);
          final detourEnd = LatLng(routing['detour_end']['lat'], routing['detour_end']['lng']);
          
          final blockedPoints = await _getStreetRoute(blockedStart, blockedEnd);
          final detourPoints = await _getStreetRoute(detourStart, detourEnd);
          
          setState(() {
            _blockedRoutePoints = blockedPoints;
            _detourRoutePoints = detourPoints;
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
      final response = await http.get(Uri.parse(liveReportsUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final reports = data['reports'] as List<dynamic>? ?? [];
        if (reports.length > _liveReports.length) {
          if (_liveReports.isNotEmpty || reports.isNotEmpty) {
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
            _liveReports = reports;
          });
        }
      }
    } catch (e) {
      // Fail silently to avoid interrupting the user on network blips
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
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 15));

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
                        fontWeight: FontWeight.bold,
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
                          Text('Official X/Twitter Draft', style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(comms['twitter_post']?.toString() ?? '', style: const TextStyle(color: Colors.white70, fontSize: 14)),
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
                          Text('Public SMS Alert (Roman Urdu)', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(comms['sms_alert']?.toString() ?? '', style: const TextStyle(color: Colors.white70, fontSize: 14)),
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
                          Text('Command Dispatch Email', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(comms['internal_email']?.toString() ?? '', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Publish Button
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('All communications successfully broadcasted to the public network.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.send),
                  label: const Text('Publish All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                  fontWeight: FontWeight.bold,
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
                    textStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
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
                    textStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
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
                    textStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
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
          ],
        ),
      ),
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
                    height: 350,
                    color: const Color(0xFF090E14), // Prevents white flash
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
                              urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                              subdomains: const ['a', 'b', 'c'],
                              userAgentPackageName: 'com.ciro.dashboard',
                            ),
                            if (_analysisData != null) ...[
                              PolylineLayer(
                                polylines: [
                                  if (_blockedRoutePoints.isNotEmpty)
                                    // Polyline 1 (BEFORE) - Blocked Route
                                    Polyline(
                                      points: _blockedRoutePoints,
                                      color: Colors.redAccent.withOpacity(0.5),
                                      strokeWidth: 5.0,
                                    ),
                                  if (_detourRoutePoints.isNotEmpty)
                                    // Polyline 2 (AFTER) - Active Reroute
                                    Polyline(
                                      points: _detourRoutePoints,
                                      color: Colors.greenAccent,
                                      strokeWidth: 6.0,
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
                                      child: _buildGlowingMarker(_analysisData!['crisis_type_short']?.toString() ?? 'CRISIS'),
                                    ),
                                ],
                              ),
                            ],
                            MarkerLayer(
                              markers: [
                                ..._liveReports.map((report) {
                                  final locName = report['location']?.toString() ?? '';
                                  final latLng = _geocode(locName);
                                  if (latLng == null) return null;
                                  return Marker(
                                    point: latLng,
                                    width: 150,
                                    height: 150,
                                    child: GestureDetector(
                                      onTap: () {
                                        _fetchTacticalData(report['translated_summary']?.toString() ?? 'Emergency at $locName');
                                      },
                                      child: _buildGlowingMarker(report['crisis_type']?.toString() ?? 'REPORT'),
                                    ),
                                  );
                                }).whereType<Marker>().toList(),
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
                            right: 12,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'CRITICAL ZONES',
                                    style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 10),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    border: Border.all(color: Colors.greenAccent.withOpacity(0.8)),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'ACTIVE REROUTE',
                                    style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]
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
                                    ? GoogleFonts.notoNastaliqUrdu(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)
                                    : GoogleFonts.inter(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
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
                                    ? GoogleFonts.notoNastaliqUrdu(fontSize: 15, color: Colors.white, height: 1.8)
                                    : GoogleFonts.inter(fontSize: 15, color: Colors.white, height: 1.4),
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
                                                ? GoogleFonts.notoNastaliqUrdu(fontSize: 14, color: Colors.white70, height: 1.8)
                                                : GoogleFonts.poppins(fontSize: 14, color: Colors.white70, height: 1.4),
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
                                                ? GoogleFonts.notoNastaliqUrdu(fontSize: 14, color: Colors.white, height: 1.8)
                                                : GoogleFonts.poppins(fontSize: 14, color: Colors.white, height: 1.4),
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
                                }
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isBroadcasting ? null : _executeCommunications,
                                  icon: _isBroadcasting 
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                      : const Icon(Icons.satellite_alt),
                                  label: Text(_isBroadcasting ? 'BROADCASTING...' : 'Execute Communications'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amber.shade600,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    textStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.1),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.redAccent.withOpacity(0.4),
            boxShadow: [
              BoxShadow(
                color: Colors.redAccent.withOpacity(0.9),
                blurRadius: 15,
                spreadRadius: 3,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          color: Colors.black87,
          child: Text('CRITICAL: $crisisType', style: const TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        ),
      ],
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
                  ? GoogleFonts.notoNastaliqUrdu(color: color, fontWeight: FontWeight.bold, fontSize: 14)
                  : GoogleFonts.poppins(color: color, fontWeight: FontWeight.bold, letterSpacing: 1.1, fontSize: 14),
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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(title, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(value, style: GoogleFonts.poppins(color: color, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
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
          title: Text('AI Tactical Reasoning:\n$title', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          content: Text(reasoning, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14, height: 1.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Acknowledge', style: GoogleFonts.poppins(color: Colors.amber, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}