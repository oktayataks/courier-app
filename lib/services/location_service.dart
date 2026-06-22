import 'dart:async';
import 'dart:convert';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import 'storage_service.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStream;
  final StreamController<Position> _positionController =
      StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _positionController.stream;

  bool get isTracking => _positionStream != null;

  static Timer? _timer;
  static String? _courierId;

  // ----- İzin yönetimi -----

  Future<bool> checkPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  // ----- Mevcut konum -----

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

  // ----- Konum takibi -----

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
        // İsteğe bağlı: hatayı subscribe edenlere ilet
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

  // ----- Mesafe -----

  double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  // ----- Geocoding (mevcut servisten korundu) -----

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

  // ----- Backend'e periyodik konum gönderimi -----

  static Future<bool> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<void> startBackendTracking(String courierId) async {
    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );

    if (!uuidRegex.hasMatch(courierId)) {
      print('❌ Geçersiz courier ID, tracking başlatılmıyor: $courierId');
      return;
    }

    _courierId = courierId;
    final hasPermission = await requestPermission();
    if (!hasPermission) return;

    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _sendLocation(),
    );

    await _sendLocation();
    print('🚀 Location tracking başladı: $courierId');
  }

  static void stopBackendTracking() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _sendLocation() async {
    print('📍 Konum gönderiliyor...');
    print('📍 Courier ID: $_courierId');

    if (_courierId == null) {
      print('❌ Courier ID yok!');
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      print('📍 Pozisyon: ${position.latitude}, ${position.longitude}');

      final token = await StorageService.getToken();

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

      print('📍 Response: ${response.statusCode} - ${response.body}');
    } catch (e) {
      print('❌ Konum gönderilemedi: $e');
    }
  }

  // ----- Cleanup -----

  void dispose() {
    _positionStream?.cancel();
    _positionStream = null;
    if (!_positionController.isClosed) {
      _positionController.close();
    }
  }
}
