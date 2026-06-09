import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/constants.dart';
import '../models/courier.dart';
import '../models/order.dart';
import '../models/user.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
          requestHeader: false,
          responseHeader: false,
          error: true,
        ),
      );
    }
  }

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Dio get dio => _dio;

  // ----- Token yönetimi -----

  Future<void> setToken(String token) async {
    await _storage.write(key: AppConstants.tokenKey, value: token);
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<String?> getToken() async {
    final token = await _storage.read(key: AppConstants.tokenKey);
    if (token != null && token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
    return token;
  }

  Future<void> clearToken() async {
    await _storage.delete(key: AppConstants.tokenKey);
    _dio.options.headers.remove('Authorization');
  }

  // ----- AUTH -----

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      if (kDebugMode) {
        debugPrint('🔐 Login isteği gönderiliyor...');
        debugPrint('📧 Email: $email');
      }

      final response = await _dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );

      if (kDebugMode) {
        debugPrint('✅ Login başarılı!');
        debugPrint('📦 Response: ${response.data}');
      }

      final data = response.data as Map<String, dynamic>;
      final token = (data['accessToken'] ?? data['access_token']) as String?;
      if (token != null) {
        await setToken(token);
      }
      return data;
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Login hatası: ${e.response?.data}');
      }
      throw ApiException(_handleError(e));
    }
  }

  Future<User> getMe() async {
    try {
      final response = await _dio.get('/auth/me');
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException(_handleError(e));
    }
  }

  // ----- COURIER -----

  Future<Courier> getMyCourier() async {
    try {
      final response = await _dio.get('/couriers/me');
      return Courier.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException(_handleError(e));
    }
  }

  Future<Courier> updateLocation(double lat, double lng) async {
    try {
      final response = await _dio.patch(
        '/couriers/me/location',
        data: {'latitude': lat, 'longitude': lng},
      );
      return Courier.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException(_handleError(e));
    }
  }

  Future<Courier> toggleOnlineStatus() async {
    try {
      final response = await _dio.patch('/couriers/me/status');
      return Courier.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException(_handleError(e));
    }
  }

  // ----- ORDERS -----

  Future<List<Order>> getMyOrders({String? status}) async {
    try {
      final response = await _dio.get(
        '/orders/my-orders',
        queryParameters: status != null ? {'status': status} : null,
      );

      final raw = response.data;
      final List<dynamic> data = raw is Map<String, dynamic>
          ? (raw['data'] as List<dynamic>? ?? const [])
          : (raw as List<dynamic>? ?? const []);
      return data
          .map((json) => Order.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException(_handleError(e));
    }
  }

  Future<Order> getOrder(String orderId) async {
    try {
      final response = await _dio.get('/orders/$orderId');
      return Order.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException(_handleError(e));
    }
  }

  Future<Order> acceptOrder(String orderId) async {
    try {
      final response = await _dio.post('/orders/$orderId/accept');
      return Order.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException(_handleError(e));
    }
  }

  Future<Order> rejectOrder(String orderId, String reason) async {
    try {
      final response = await _dio.post(
        '/orders/$orderId/reject',
        data: {'reason': reason},
      );
      return Order.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException(_handleError(e));
    }
  }

  Future<Order> updateOrderStatus(String orderId, String status) async {
    try {
      final response = await _dio.patch(
        '/orders/$orderId/status',
        data: {'status': status},
      );
      return Order.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException(_handleError(e));
    }
  }

  // ----- EARNINGS -----

  Future<Map<String, dynamic>> getEarnings({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await _dio.get(
        '/earnings/my-earnings',
        queryParameters: {
          'startDate': startDate.toIso8601String(),
          'endDate': endDate.toIso8601String(),
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException(_handleError(e));
    }
  }

  // ----- Error handling -----

  String _handleError(DioException e) {
    if (e.response != null) {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        final message = data['message'];
        // Backend'den gelen hata mesajları (NestJS class-validator
        // birden fazla mesajı liste olarak döndürebilir)
        if (message is String) return message;
        if (message is List && message.isNotEmpty) {
          return message.join(', ');
        }
      }
      return 'Sunucu hatası: ${e.response?.statusCode}';
    } else if (e.type == DioExceptionType.connectionTimeout) {
      return 'Bağlantı zaman aşımına uğradı';
    } else if (e.type == DioExceptionType.receiveTimeout) {
      return 'Sunucu yanıt vermiyor';
    } else if (e.type == DioExceptionType.cancel) {
      return 'İstek iptal edildi';
    } else {
      return 'İnternet bağlantınızı kontrol edin';
    }
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}
