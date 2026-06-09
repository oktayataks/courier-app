import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/courier.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

/// Courier state'ini yöneten notifier.
///
/// State doğrudan [Courier]? tutar; null ise henüz yüklenmemiş demektir.
class CourierNotifier extends StateNotifier<Courier?> {
  CourierNotifier(this._apiService) : super(null);

  // ignore: unused_field
  final ApiService _apiService;

  /// Backend'den courier bilgilerini yükler. Şimdilik mock data döner.
  Future<void> loadCourier() async {
    try {
      // NOTE: gerçek backend hazır olduğunda aşağıdaki çağrıyı aktive edin.
      // final response = await _apiService.getMyCourier();
      // state = Courier.fromJson(response['courier'] as Map<String, dynamic>);

      await Future.delayed(const Duration(milliseconds: 400));
      state = const Courier(
        id: '1',
        userId: '1',
        name: 'Demo Kurye',
        phone: '+90 555 000 0001',
        status: 'online',
        vehicleType: 'motorbike',
        vehiclePlate: '34 ABC 123',
        rating: 4.8,
        totalDeliveries: 245,
        totalEarnings: 12450.0,
        todayEarnings: 380.50,
        todayDeliveries: 8,
        isAvailable: true,
        activeOrders: 2,
      );
    } catch (e) {
      state = null;
    }
  }

  /// Çevrimiçi/çevrimdışı durumunu değiştirir. Optimistic update + rollback.
  Future<void> toggleOnlineStatus() async {
    final current = state;
    if (current == null) return;

    final newStatus = !current.isOnline;
    state = current.copyWith(
      isOnline: newStatus,
      status: newStatus ? 'online' : 'offline',
    );

    try {
      // NOTE: gerçek backend çağrısı:
      // await _apiService.toggleOnlineStatus(newStatus);
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      state = current;
      rethrow;
    }
  }

  /// Aktif konum güncellemesi (LocationService stream'inden çağrılır).
  void updateLocation(double latitude, double longitude) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Aktif sipariş sayısını günceller (orders_provider akışından çağrılabilir).
  void setActiveOrders(int count) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(activeOrders: count);
  }
}

final courierProvider =
    StateNotifierProvider<CourierNotifier, Courier?>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return CourierNotifier(apiService);
});
