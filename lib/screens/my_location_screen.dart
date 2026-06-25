import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../config/theme.dart';

class MyLocationScreen extends StatefulWidget {
  const MyLocationScreen({super.key});

  @override
  State<MyLocationScreen> createState() => _MyLocationScreenState();
}

class _MyLocationScreenState extends State<MyLocationScreen> {
  final MapController _mapController = MapController();
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  String _accuracy = '-';
  String _speed = '-';
  String _heading = '-';
  bool _isTracking = false;

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _startTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konum izni verilmedi'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
      return;
    }

    // İlk konumu hemen al
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) _updatePosition(position);
    } catch (_) {
      // Stream'den bekle
    }

    if (!mounted) return;
    setState(() => _isTracking = true);

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (position) {
        if (mounted) _updatePosition(position);
      },
      onError: (_) {
        if (mounted) setState(() => _isTracking = false);
      },
    );
  }

  void _updatePosition(Position position) {
    setState(() {
      _currentPosition = position;
      _accuracy = '${position.accuracy.toStringAsFixed(1)} m';
      _speed = '${(position.speed * 3.6).toStringAsFixed(1)} km/s';
      _heading = '${position.heading.toStringAsFixed(0)}°';
    });

    _mapController.move(
      LatLng(position.latitude, position.longitude),
      16,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = _currentPosition;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Konumum'),
        flexibleSpace: Container(
          decoration:
              const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        actions: [
          if (_isTracking)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'Canlı',
                    style: TextStyle(
                        fontSize: 12, color: Colors.greenAccent),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: pos == null
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                      color: AppTheme.primaryLight),
                  SizedBox(height: 16),
                  Text(
                    'Konum alınıyor...',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // OpenStreetMap haritası
                Expanded(
                  flex: 3,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter:
                          LatLng(pos.latitude, pos.longitude),
                      initialZoom: 16,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.courier_app',
                        maxZoom: 19,
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(
                                pos.latitude, pos.longitude),
                            width: 60,
                            height: 60,
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 48,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Bilgi paneli
                Container(
                  color: Colors.white,
                  padding:
                      const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _buildInfoCard(
                            icon: Icons.gps_fixed_rounded,
                            label: 'Doğruluk',
                            value: _accuracy,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 10),
                          _buildInfoCard(
                            icon: Icons.speed_rounded,
                            label: 'Hız',
                            value: _speed,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 10),
                          _buildInfoCard(
                            icon: Icons.explore_rounded,
                            label: 'Yön',
                            value: _heading,
                            color: Colors.purple,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            _buildRow('Enlem',
                                pos.latitude.toStringAsFixed(6)),
                            const SizedBox(height: 6),
                            _buildRow('Boylam',
                                pos.longitude.toStringAsFixed(6)),
                            const SizedBox(height: 6),
                            _buildRow('Rakım',
                                '${pos.altitude.toStringAsFixed(1)} m'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _isTracking
                              ? Colors.green.shade50
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isTracking
                                  ? Icons.circle
                                  : Icons.pause_circle,
                              size: 10,
                              color: _isTracking
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isTracking
                                  ? 'Canlı takip aktif'
                                  : 'Takip kapalı',
                              style: TextStyle(
                                fontSize: 12,
                                color: _isTracking
                                    ? Colors.green
                                    : Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style:
                  TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13, color: Colors.grey.shade600)),
        Text(value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
