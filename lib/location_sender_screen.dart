import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';

/// ─────────────────────────────────────────────
/// LAPTOP / BUS SCREEN
/// Gets GPS every 5 seconds → pushes to Firebase
/// at path:  bus/location  { lat, lng, timestamp }
/// ─────────────────────────────────────────────
class LocationSenderScreen extends StatefulWidget {
  const LocationSenderScreen({super.key});

  @override
  State<LocationSenderScreen> createState() => _LocationSenderScreenState();
}

class _LocationSenderScreenState extends State<LocationSenderScreen> {
  final DatabaseReference _dbRef =
      FirebaseDatabase.instance.ref('bus/location');

  Timer? _timer;
  bool _sending = false;
  int _updateCount = 0;
  double? _lat;
  double? _lng;
  String _status = 'Press Start to begin sending location.';

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Permission check ─────────────────────────
  Future<bool> _requestPermission() async {
    bool serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      _set('❌ Location services are OFF. Enable in device Settings.');
      return false;
    }
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      _set('❌ Location permission denied.');
      return false;
    }
    return true;
  }

  // ── Start ────────────────────────────────────
  Future<void> _start() async {
    if (!await _requestPermission()) return;
    setState(() {
      _sending = true;
      _updateCount = 0;
      _status = 'Starting...';
    });
    await _push(); // immediate first push
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _push());
  }

  // ── Push one GPS reading to Firebase ─────────
  Future<void> _push() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _dbRef.set({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'timestamp': ServerValue.timestamp,
      });
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _updateCount++;
        _status = '✅ Sent update #$_updateCount  (${_now()})';
      });
    } catch (e) {
      _set('⚠️ Error: $e');
    }
  }

  // ── Stop ─────────────────────────────────────
  void _stop() {
    _timer?.cancel();
    setState(() {
      _sending = false;
      _status = '🛑 Stopped after $_updateCount updates.';
    });
  }

  void _set(String msg) => setState(() => _status = msg);
  String _now() => DateTime.now().toLocal().toString().substring(11, 19);

  // ── UI ───────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📍 BUS — Location Sender'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // GPS icon pulses green when sending
              Icon(
                _sending ? Icons.gps_fixed : Icons.gps_not_fixed,
                size: 96,
                color: _sending ? Colors.green : Colors.blue.shade300,
              ),
              const SizedBox(height: 28),

              // Status box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Text(
                  _status,
                  style: const TextStyle(fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),

              // Coordinates card
              if (_lat != null)
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 24),
                    child: Column(
                      children: [
                        _coordRow(
                            Icons.north, 'Latitude', _lat!, Colors.red),
                        const Divider(height: 16),
                        _coordRow(Icons.east, 'Longitude', _lng!,
                            Colors.blue),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 32),

              // Start / Stop button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _sending ? _stop : _start,
                  icon: Icon(
                    _sending ? Icons.stop_circle : Icons.play_circle,
                    size: 26,
                  ),
                  label: Text(
                    _sending ? 'Stop Sending' : 'Start Sending Location',
                    style: const TextStyle(fontSize: 17),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _sending ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Pushes to Firebase → bus/location every 5 seconds',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coordRow(
      IconData icon, String label, double value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(value.toStringAsFixed(6)),
      ],
    );
  }
}