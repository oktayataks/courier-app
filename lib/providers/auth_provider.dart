import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final User? user;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.user,
    this.error,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    User? user,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _apiService;
  final FlutterSecureStorage _storage;

  AuthNotifier(this._apiService, this._storage) : super(const AuthState());

  Future<void> checkAuthStatus() async {
    state = state.copyWith(isLoading: true);
    try {
      final token = await _apiService.getToken();
      if (token == null || token.isEmpty) {
        state = state.copyWith(isAuthenticated: false, isLoading: false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString(AppConstants.userKey);
      if (userData != null) {
        final user = User.fromJson(jsonDecode(userData) as Map<String, dynamic>);
        state = state.copyWith(
          isAuthenticated: true,
          user: user,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isAuthenticated: false, isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(
        isAuthenticated: false,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      if (email.trim().isEmpty || password.isEmpty) {
        throw Exception('E-posta ve şifre gereklidir');
      }

      final response = await _apiService.login(email, password);

      final accessToken = response['accessToken'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Sunucudan token alınamadı');
      }
      await _apiService.setToken(accessToken);

      final userJson = response['user'] as Map<String, dynamic>?;
      if (userJson == null) {
        throw Exception('Sunucudan kullanıcı bilgisi alınamadı');
      }
      final user = User(
        id: userJson['id']?.toString() ?? '',
        name: userJson['fullName'] as String? ?? '',
        email: userJson['email'] as String? ?? '',
        phone: userJson['phone'] as String? ?? '',
        role: userJson['role'] as String? ?? 'courier',
        createdAt: DateTime.now(),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppConstants.userKey,
        jsonEncode(user.toJson()),
      );

      state = state.copyWith(
        isAuthenticated: true,
        user: user,
        isLoading: false,
      );

      print('🚀 Login başarılı, userId: ${user.id}');
      _setupCourierServices(user.id, accessToken);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> _setupCourierServices(String userId, String token) async {
    print('🔍 _setupCourierServices başladı: $userId');
    try {
      final res = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/couriers/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('🔍 /couriers/me status: ${res.statusCode}');
      print('🔍 /couriers/me body: ${res.body}');

      if (res.statusCode != 200) {
        print('❌ Courier bulunamadı!');
        return;
      }

      final courierData = json.decode(res.body);
      print('🔍 courierData: $courierData');

      final courierId = courierData['id']?.toString();
      print('🔍 courierId: $courierId');

      if (courierId == null || courierId.isEmpty) {
        print('❌ Courier ID boş!');
        return;
      }
      print('🔍 Courier ID bulundu: $courierId');
      print('🔍 Tracking başlatılıyor...');
      await LocationService.startBackendTracking(courierId);
      print('✅ Tracking başlatıldı!');

      final fcmToken = await NotificationService().getFCMToken();
      print('🔍 FCM token: $fcmToken');

      if (fcmToken != null) {
        final fcmRes = await http.patch(
          Uri.parse(
            '${AppConstants.apiBaseUrl}/couriers/$courierId/fcm-token',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: json.encode({'fcmToken': fcmToken}),
        );
        print('✅ FCM token kaydedildi! Status: ${fcmRes.statusCode}');
      }
    } catch (e) {
      print('❌ _setupCourierServices hata: $e');
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    try {
      LocationService.stopBackendTracking();
      await _apiService.clearToken();
      await _storage.delete(key: AppConstants.refreshTokenKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.userKey);
      state = const AuthState();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final storage = ref.watch(secureStorageProvider);
  return AuthNotifier(apiService, storage);
});

/// Sadece oturum açmış kullanıcıyı döndüren selector.
/// `ref.watch(userProvider)` çağrısı `User?` verir.
final userProvider = Provider<User?>((ref) {
  return ref.watch(authProvider).user;
});
