import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

class LocationState {
  final Position? currentPosition;
  final bool isTracking;
  final bool hasPermission;
  final String? error;

  const LocationState({
    this.currentPosition,
    this.isTracking = false,
    this.hasPermission = false,
    this.error,
  });

  LocationState copyWith({
    Position? currentPosition,
    bool? isTracking,
    bool? hasPermission,
    String? error,
  }) {
    return LocationState(
      currentPosition: currentPosition ?? this.currentPosition,
      isTracking: isTracking ?? this.isTracking,
      hasPermission: hasPermission ?? this.hasPermission,
      error: error,
    );
  }
}

class LocationNotifier extends StateNotifier<LocationState> {
  final LocationService _locationService;
  StreamSubscription<Position>? _subscription;

  LocationNotifier(this._locationService) : super(const LocationState());

  Future<bool> requestPermission() async {
    final hasPermission = await _locationService.checkPermission();
    state = state.copyWith(hasPermission: hasPermission);
    return hasPermission;
  }

  Future<void> getCurrentLocation() async {
    try {
      final position = await _locationService.getCurrentPosition();
      if (position != null) {
        state = state.copyWith(currentPosition: position, hasPermission: true);
      } else {
        state = state.copyWith(
          hasPermission: false,
          error: 'Konum alınamadı',
        );
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> startTracking() async {
    if (state.isTracking) return;

    await _locationService.startTracking();
    _subscription = _locationService.positionStream.listen(
      (position) => state = state.copyWith(currentPosition: position),
      onError: (Object error) =>
          state = state.copyWith(error: error.toString()),
    );
    state = state.copyWith(isTracking: true);
  }

  void stopTracking() {
    _subscription?.cancel();
    _subscription = null;
    _locationService.stopTracking();
    state = state.copyWith(isTracking: false);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final locationProvider =
    StateNotifierProvider<LocationNotifier, LocationState>((ref) {
  final service = ref.watch(locationServiceProvider);
  return LocationNotifier(service);
});
