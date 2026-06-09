import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

/// Token ve kullanıcı verisi gibi kalıcı depolama işlemleri için yardımcı sınıf.
///
/// `ApiService` ile aynı [FlutterSecureStorage] anahtarlarını kullanır, böylece
/// login sonrası `ApiService.setToken()` ile kaydedilen token buradan da
/// okunabilir.
class StorageService {
  StorageService._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // ----- Token -----

  static Future<String?> getToken() async {
    return _secureStorage.read(key: AppConstants.tokenKey);
  }

  static Future<void> setToken(String token) async {
    await _secureStorage.write(key: AppConstants.tokenKey, value: token);
  }

  static Future<void> clearToken() async {
    await _secureStorage.delete(key: AppConstants.tokenKey);
  }

  // ----- Refresh Token -----

  static Future<String?> getRefreshToken() async {
    return _secureStorage.read(key: AppConstants.refreshTokenKey);
  }

  static Future<void> setRefreshToken(String token) async {
    await _secureStorage.write(
      key: AppConstants.refreshTokenKey,
      value: token,
    );
  }

  static Future<void> clearRefreshToken() async {
    await _secureStorage.delete(key: AppConstants.refreshTokenKey);
  }

  // ----- User Data (SharedPreferences) -----

  static Future<String?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.userKey);
  }

  static Future<void> setUserData(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.userKey, json);
  }

  static Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.userKey);
  }

  static Future<void> clearAll() async {
    await clearToken();
    await clearRefreshToken();
    await clearUserData();
  }
}
