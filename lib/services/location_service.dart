import 'dart:async';
import 'dart:convert';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import 'storage_service.dart';

class LocationService {
  // ----- Instance API (location_provider.dart için) -----

  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStream;
  final StreamController<Position> _positionController =
      StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _positionController.stream;
  bool get isTracking => _positionStream != null;

  Future<bool> checkPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  Future<Position?> getCurrentPosition() async {
    final hasPermission = await checkPermission();
    if (!hasPermission) return null;
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> startTracking() async {
    if (_positionStream != null) return;
    final hasPermission = await checkPermission();
    if (!hasPermission) return;
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (position) => _positionController.add(position),
      onError: (Object error) {
        if (!_positionController.isClosed) {
          _positionController.addError(error);
        }
      },
    );
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  Future<String?> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        return '${place.street}, ${place.subLocality}, ${place.locality}';
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<List<Location>> getCoordinatesFromAddress(String address) async {
    try {
      return await locationFromAddress(address);
    } catch (_) {
      return [];
    }
  }

  void dispose() {
    _positionStream?.cancel();
    _positionStream = null;
    if (!_positionController.isClosed) {
      _positionController.close();
    }
  }

  // ----- Static API (backend konum gönderimi) -----

  static StreamSubscription<Position>? _backendStream;
  static String? _courierId;
  static DateTime? _lastSent;

  static Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return false;
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<void> startBackendTracking(String courierId) async {
    if (courierId.isEmpty) return;

    _courierId = courierId;
    print('🚀 Tracking başladı: $courierId');

    final hasPermission = await requestPermission();
    if (!hasPermission) {
      print('❌ Konum izni yok!');
      return;
    }

    await _backendStream?.cancel();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _backendStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) async {
        print('📍 Stream konum: ${position.latitude}, ${position.longitude}');
        final now = DateTime.now();
        if (_lastSent == null ||
            now.difference(_lastSent!).inSeconds >= 30) {
          _lastSent = now;
          await _sendLocation(position);
        }
      },
      onError: (error) {
        print('❌ Stream hatası: $error');
      },
    );
  }

  static void stopBackendTracking() {
    _backendStream?.cancel();
    _backendStream = null;
    _courierId = null;
    _lastSent = null;
    print('⏹ Tracking durduruldu');
  }

  static Future<void> _sendLocation(Position position) async {
    try {
      final token = await StorageService.getToken();
      if (token == null || _courierId == null || _courierId!.isEmpty) return;

      print('📍 Gönderiliyor: LAT=${position.latitude} LNG=${position.longitude}');

      final response = await http.patch(
        Uri.parse(
          '${AppConstants.apiBaseUrl}/couriers/$_courierId/location',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'latitude': position.latitude,
          'longitude': position.longitude,
        }),
      );

      print('📍 Response: ${response.statusCode}');
    } catch (e) {
      print('❌ Hata: $e');
    }
  }
}
