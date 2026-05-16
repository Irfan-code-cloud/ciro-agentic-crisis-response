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

  // Note: If testing on a physical Android device, replace 10.0.2.2 with your PC's local IP address (e.g., 192.168.1.x).
  final String backendUrl = kIsWeb ? 'http://127.0.0.1:8000/api/analyze' : 'http://10.0.2.2:8000/api/analyze';

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
    }
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
              const Text(
                'Inject Crisis Signal (Simulation)',
                style: TextStyle(
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
                    backgroundColor: Colors.blueAccent.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                    backgroundColor: Colors.redAccent.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                  SizedBox(
                    height: 350,
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
                              urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
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
                          ],
                        ),
                        
                        // Map Overlays
                        if (_analysisData == null)
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
                                                : GoogleFonts.inter(fontSize: 14, color: Colors.white70, height: 1.4),
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
                                                : GoogleFonts.inter(fontSize: 14, color: Colors.white, height: 1.4),
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
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Tactical Brief securely forwarded to Mayor\'s Office.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        backgroundColor: Colors.green,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.send_to_mobile),
                                  label: Text(_isUrdu ? 'میئر / سی ڈی اے کو مطلع کریں' : 'Notify Mayor / CDA'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueGrey.shade800,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                  : GoogleFonts.inter(color: color, fontWeight: FontWeight.bold, letterSpacing: 1.1, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}