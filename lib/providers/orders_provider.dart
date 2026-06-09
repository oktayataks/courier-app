import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/order.dart';
import '../services/storage_service.dart';

class OrdersState {
  final List<Order> activeOrders;
  final List<Order> completedOrders;
  final List<Order> availableOrders;
  final bool isLoading;
  final String? error;

  const OrdersState({
    this.activeOrders = const [],
    this.completedOrders = const [],
    this.availableOrders = const [],
    this.isLoading = false,
    this.error,
  });

  OrdersState copyWith({
    List<Order>? activeOrders,
    List<Order>? completedOrders,
    List<Order>? availableOrders,
    bool? isLoading,
    String? error,
  }) {
    return OrdersState(
      activeOrders: activeOrders ?? this.activeOrders,
      completedOrders: completedOrders ?? this.completedOrders,
      availableOrders: availableOrders ?? this.availableOrders,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class OrdersNotifier extends StateNotifier<OrdersState> {
  OrdersNotifier() : super(const OrdersState()) {
    loadOrders();
  }

  Future<void> loadOrders() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final token = await StorageService.getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/orders'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final raw = json.decode(response.body);
        final List<dynamic> data =
            raw is List ? raw : (raw['data'] as List? ?? []);
        final orders = data.map((o) => Order.fromJson(o)).toList();

        state = state.copyWith(
          availableOrders: orders
              .where((o) => o.status == OrderStatus.pending)
              .toList(),
          activeOrders: orders
              .where((o) =>
                  o.status == OrderStatus.assigned ||
                  o.status == OrderStatus.pickedUp)
              .toList(),
          completedOrders: orders
              .where((o) => o.status == OrderStatus.delivered)
              .toList(),
          isLoading: false,
        );
      } else {
        throw Exception('Siparişler yüklenemedi: ${response.statusCode}');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> acceptOrder(String orderId) async {
    try {
      final token = await StorageService.getToken();

      final response = await http.patch(
        Uri.parse('${AppConstants.apiBaseUrl}/orders/$orderId/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'status': 'picked_up'}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        await loadOrders();
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> updateOrderStatus(String orderId, String newStatus) async {
    try {
      final token = await StorageService.getToken();

      final response = await http.patch(
        Uri.parse('${AppConstants.apiBaseUrl}/orders/$orderId/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'status': newStatus}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        await loadOrders();
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> cancelOrder(String orderId, String reason) async {
    try {
      final token = await StorageService.getToken();

      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/orders/$orderId/cancel'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'reason': reason}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        state = state.copyWith(
          activeOrders:
              state.activeOrders.where((o) => o.id != orderId).toList(),
        );
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

}

final ordersProvider =
    StateNotifierProvider<OrdersNotifier, OrdersState>((ref) {
  return OrdersNotifier();
});

/// Tüm siparişleri tek listede [AsyncValue] olarak sunan selector.
///
/// `state.isLoading` -> [AsyncValue.loading], `state.error` -> [AsyncValue.error],
/// aksi halde available + active + completed siparişlerin birleşimi.
/// Template kodları (`ordersState.when(data:, loading:, error:)`) bu provider
/// üzerinden tüketmelidir.
final ordersAsyncProvider = Provider<AsyncValue<List<Order>>>((ref) {
  final state = ref.watch(ordersProvider);

  if (state.isLoading &&
      state.activeOrders.isEmpty &&
      state.availableOrders.isEmpty &&
      state.completedOrders.isEmpty) {
    return const AsyncValue<List<Order>>.loading();
  }

  if (state.error != null) {
    return AsyncValue<List<Order>>.error(state.error!, StackTrace.current);
  }

  final all = <Order>[
    ...state.availableOrders,
    ...state.activeOrders,
    ...state.completedOrders,
  ];
  return AsyncValue<List<Order>>.data(all);
});
