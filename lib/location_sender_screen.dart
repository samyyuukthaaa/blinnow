import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';

class LocationSenderScreen extends StatefulWidget {
  const LocationSenderScreen({super.key});

  @override
  State<LocationSenderScreen> createState() => _LocationSenderScreenState();
}

class _LocationSenderScreenState extends State<LocationSenderScreen> {
  final DatabaseReference _dbRef =
      FirebaseDatabase.instance.ref('bus/location');

  bool _sending = false;
  int _updateCount = 0;
  double? _lat, _lng;
  String _status = 'Press Start to begin sending location.';

  dynamic _positionStream;

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<bool> _requestPermission() async {
    bool serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      _set('❌ Location services are OFF. Enable in device Settings.');
      return false;
    }
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      _set('❌ Location permission denied.');
      return false;
    }
    return true;
  }

  Future<void> _start() async {
    if (!await _requestPermission()) return;
    setState(() {
      _sending = true;
      _updateCount = 0;
      _status = '🔍 Getting first location...';
    });

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2, // ← fires every 2 meters
      ),
    ).listen(
      (position) => _push(position),
      onError: (e) => _set('⚠️ GPS Error: $e'),
    );
  }

  Future<void> _push(position) async {
    try {
      await _dbRef.set({
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': ServerValue.timestamp,
      });
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _updateCount++;
        _status = '✅ Sent update #$_updateCount  (${_now()})\n📏 Triggered after ≥2m movement';
      });
    } catch (e) {
      _set('⚠️ Firebase error: $e');
    }
  }

  void _stop() {
    _positionStream?.cancel();
    setState(() {
      _sending = false;
      _status = '🛑 Stopped after $_updateCount updates.';
    });
  }

  void _set(String msg) => setState(() => _status = msg);
  String _now() => DateTime.now().toLocal().toString().substring(11, 19);

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
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Icon(
                  _sending ? Icons.gps_fixed : Icons.gps_not_fixed,
                  key: ValueKey(_sending),
                  size: 96,
                  color: _sending ? Colors.green : Colors.blue.shade300,
                ),
              ),
              const SizedBox(height: 8),
              if (_sending)
                const Text(
                  '🔴 LIVE — Updates every 2 meters',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              const SizedBox(height: 20),

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

              if (_lat != null)
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 24),
                    child: Column(
                      children: [
                        _coordRow(Icons.north, 'Latitude', _lat!, Colors.red),
                        const Divider(height: 16),
                        _coordRow(Icons.east, 'Longitude', _lng!, Colors.blue),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.upload, size: 18, color: Colors.green),
                            const SizedBox(width: 8),
                            Text(
                              'Total pushes to Firebase: $_updateCount',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 32),

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
                '📏 Firebase only updates when bus moves ≥2 meters',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coordRow(IconData icon, String label, double value, Color color) {
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
