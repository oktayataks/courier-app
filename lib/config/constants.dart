class AppConstants {
  AppConstants._();

  static const String appName = 'Kurye Uygulaması';
  static const String appVersion = '1.0.0';

  // Backend URL'ini ortama göre değiştirin:
  static const String apiBaseUrl = 'https://kurye-sistemi.onrender.com/api/v1'; // Android emulator
  // static const String apiBaseUrl = 'http://localhost:3000'; // iOS simulator
  // static const String apiBaseUrl = 'https://api.yourapp.com'; // Production
  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 20);

  static const String tokenKey = 'auth_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userKey = 'user_data';
  static const String onboardingKey = 'onboarding_completed';

  static const Duration locationUpdateInterval = Duration(seconds: 10);
  static const double locationDistanceFilter = 10.0;

  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';

  static const int splashDuration = 2;
  static const double defaultPadding = 16.0;
  static const double defaultRadius = 12.0;
}

class OrderStatus {
  OrderStatus._();

  static const String pending = 'pending';
  static const String assigned = 'assigned';
  static const String pickedUp = 'picked_up';
  static const String inTransit = 'in_transit';
  static const String delivered = 'delivered';
  static const String cancelled = 'cancelled';

  static String getLabel(String status) {
    switch (status) {
      case pending:
        return 'Bekliyor';
      case assigned:
        return 'Atandı';
      case pickedUp:
        return 'Teslim Alındı';
      case inTransit:
        return 'Yolda';
      case delivered:
        return 'Teslim Edildi';
      case cancelled:
        return 'İptal';
      default:
        return 'Bilinmiyor';
    }
  }
}

class CourierStatus {
  CourierStatus._();

  static const String online = 'online';
  static const String offline = 'offline';
  static const String busy = 'busy';
  static const String onBreak = 'on_break';
}
