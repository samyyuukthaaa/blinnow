import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// ─────────────────────────────────────────────────────
/// PHONE / STUDENT SCREEN
/// • Listens to Firebase  bus/location  in real-time
/// • Gets this phone's own GPS
/// • Calculates distance (Haversine) → ETA
/// • Speaks ETA using flutter_tts
///   (auto every 30 s  OR  tap "Speak Now")
/// ─────────────────────────────────────────────────────
class LocationReceiverScreen extends StatefulWidget {
  const LocationReceiverScreen({super.key});

  @override
  State<LocationReceiverScreen> createState() =>
      _LocationReceiverScreenState();
}

class _LocationReceiverScreenState extends State<LocationReceiverScreen> {
  // ── Firebase ──────────────────────────────────
  final DatabaseReference _dbRef =
      FirebaseDatabase.instance.ref('bus/location');

  // ── TTS ───────────────────────────────────────
  final FlutterTts _tts = FlutterTts();

  // ── Bus data (from Firebase) ──────────────────
  double? _busLat;
  double? _busLng;
  DateTime? _busLastUpdate;

  // ── My location (this phone) ──────────────────
  double? _myLat;
  double? _myLng;

  // ── ETA results ───────────────────────────────
  double? _distanceMeters;
  String _etaText = '';
  String _etaDetail = '';
  String _status = '⏳ Waiting for bus location…';

  // ── Settings ──────────────────────────────────
  bool _voiceOn = true;
  DateTime? _lastSpoken;

  /// Change this to match your real bus speed in km/h
  static const double _busSpeedKmh = 20.0;

  // ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _setupTts();
    _getMyGps();
    _subscribeFirebase();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  // ── TTS setup ─────────────────────────────────
  Future<void> _setupTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.47);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  // ── Get this phone's GPS ──────────────────────
  Future<void> _getMyGps() async {
    setState(() => _status = '📡 Getting your GPS location…');

    bool serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      setState(() => _status = '❌ Location service disabled on this phone.');
      return;
    }

    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      setState(() => _status = '❌ Location permission denied.');
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _myLat = pos.latitude;
        _myLng = pos.longitude;
        _status = '✅ Your location found. Listening for bus…';
      });
      _recalculate();
    } catch (e) {
      setState(() => _status = '⚠️ GPS error: $e');
    }
  }

  // ── Listen to Firebase real-time ──────────────
  void _subscribeFirebase() {
    _dbRef.onValue.listen((event) {
      if (!event.snapshot.exists) {
        setState(() => _status = '⚠️ No bus data in Firebase yet.');
        return;
      }
      try {
        final raw = Map<String, dynamic>.from(
            event.snapshot.value as Map<dynamic, dynamic>);
        setState(() {
          _busLat = (raw['lat'] as num).toDouble();
          _busLng = (raw['lng'] as num).toDouble();
          _busLastUpdate = DateTime.now();
          _status = '🚌 Bus location received!';
        });
        _recalculate();
      } catch (e) {
        setState(() => _status = '⚠️ Firebase read error: $e');
      }
    });
  }

  // ── Distance + ETA calculation ────────────────
  void _recalculate() {
    if (_busLat == null || _myLat == null) return;

    final meters =
        _haversine(_myLat!, _myLng!, _busLat!, _busLng!);
    final km = meters / 1000.0;
    final mins = (km / _busSpeedKmh) * 60.0;

    String eta;
    String detail;

    if (meters < 80) {
      eta = 'The bus is arriving now!';
      detail = '${meters.round()} m away';
    } else if (mins < 1) {
      eta = 'Less than 1 minute away';
      detail =
          '${meters.round()} m — ~${(mins * 60).round()} seconds';
    } else if (mins < 2) {
      eta = 'About 1 minute away';
      detail = '${meters.round()} m away';
    } else {
      eta = 'About ${mins.round()} minutes away';
      detail =
          '${km.toStringAsFixed(2)} km at ${_busSpeedKmh.toInt()} km/h';
    }

    setState(() {
      _distanceMeters = meters;
      _etaText = eta;
      _etaDetail = detail;
    });

    _autoSpeak(eta);
  }

  // ── Auto-speak every 30 seconds ───────────────
  Future<void> _autoSpeak(String eta) async {
    if (!_voiceOn) return;
    final now = DateTime.now();
    if (_lastSpoken != null &&
        now.difference(_lastSpoken!).inSeconds < 30) return;
    _lastSpoken = now;
    await _tts.stop();
    await _tts.speak('Bus update. $eta');
  }

  // ── Manual speak button ───────────────────────
  Future<void> _speakNow() async {
    await _tts.stop();
    final text = _etaText.isEmpty
        ? 'Bus location not available yet.'
        : 'Bus update. $_etaText';
    await _tts.speak(text);
  }

  // ── Haversine distance (returns metres) ───────
  double _haversine(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _r(lat2 - lat1);
    final dLon = _r(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_r(lat1)) * cos(_r(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _r(double deg) => deg * pi / 180;
  String _fmt(DateTime dt) =>
      dt.toLocal().toString().substring(11, 19);

  // ── UI ────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool hasEta = _etaText.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🚌 STUDENT — Bus ETA'),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: _voiceOn ? 'Mute voice' : 'Unmute voice',
            icon: Icon(_voiceOn ? Icons.volume_up : Icons.volume_off),
            onPressed: () {
              setState(() => _voiceOn = !_voiceOn);
              if (!_voiceOn) _tts.stop();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Status chip ───────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                _status,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),

            // ── Big ETA card ──────────────────
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 36, horizontal: 24),
                child: Column(
                  children: [
                    Icon(
                      Icons.directions_bus_rounded,
                      size: 80,
                      color: hasEta
                          ? Colors.orange.shade600
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      hasEta ? _etaText : 'Calculating…',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: hasEta
                            ? Colors.orange.shade800
                            : Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_etaDetail.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _etaDetail,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Info tiles ────────────────────
            Row(
              children: [
                Expanded(
                  child: _Tile(
                    icon: Icons.person_pin_circle,
                    label: 'Your GPS',
                    value: _myLat != null
                        ? '${_myLat!.toStringAsFixed(5)}\n${_myLng!.toStringAsFixed(5)}'
                        : 'Not found',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Tile(
                    icon: Icons.directions_bus,
                    label: 'Bus GPS',
                    value: _busLat != null
                        ? '${_busLat!.toStringAsFixed(5)}\n${_busLng!.toStringAsFixed(5)}'
                        : 'No data yet',
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_busLastUpdate != null)
              Center(
                child: Text(
                  'Bus last seen: ${_fmt(_busLastUpdate!)}',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 28),

            // ── Speak Now button ──────────────
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _speakNow,
                icon: const Icon(Icons.volume_up, size: 24),
                label: const Text('Speak ETA Now',
                    style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Refresh my GPS ────────────────
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _getMyGps,
                icon: const Icon(Icons.my_location),
                label: const Text('Refresh My Location',
                    style: TextStyle(fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Voice auto-announces every 30 seconds.\nTap "Speak ETA Now" to hear it immediately.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small info tile widget ────────────────────────
class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}