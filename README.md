# Kurye Mobil Uygulaması (Courier App)

Flutter ile geliştirilmiş, Riverpod tabanlı modern bir kurye/teslimat mobil uygulaması.

## Özellikler

- Riverpod ile state yönetimi
- Dio ile API entegrasyonu (interceptor, hata yönetimi)
- `flutter_secure_storage` ve `shared_preferences` ile güvenli depolama
- Google Maps & Geolocator ile harita ve canlı konum takibi
- Firebase Cloud Messaging + local notifications altyapısı
- Açık tema, modern UI bileşenleri

## Klasör Yapısı

```
lib/
├── main.dart
├── config/
│   ├── theme.dart
│   ├── routes.dart
│   └── constants.dart
├── models/
│   ├── user.dart
│   ├── order.dart
│   └── courier.dart
├── providers/
│   ├── auth_provider.dart
│   ├── orders_provider.dart
│   └── location_provider.dart
├── services/
│   ├── api_service.dart
│   ├── location_service.dart
│   └── notification_service.dart
├── screens/
│   ├── splash_screen.dart
│   ├── login_screen.dart
│   ├── home_screen.dart
│   ├── order_detail_screen.dart
│   ├── navigation_screen.dart
│   ├── earnings_screen.dart
│   └── profile_screen.dart
└── widgets/
    ├── order_card.dart
    ├── status_badge.dart
    └── custom_button.dart
```

## Kurulum

```bash
flutter pub get
flutter run
```

## Yapılandırma

Aşağıdaki yer tutucuları gerçek değerlerle değiştirin:

### Google Maps API Key
- `android/app/src/main/AndroidManifest.xml` → `YOUR_GOOGLE_MAPS_API_KEY`
- `ios/Runner/AppDelegate.swift` içindeki `GMSServices.provideAPIKey(...)` satırını uncomment edin
- `lib/config/constants.dart` → `googleMapsApiKey`

### API Base URL
`lib/config/constants.dart` içindeki `AppConstants.baseUrl` değerini API adresinizle değiştirin.

### Firebase
1. Android için `google-services.json` → `android/app/`
2. iOS için `GoogleService-Info.plist` → `ios/Runner/`
3. `lib/main.dart` içindeki `Firebase.initializeApp()` çağrısını aktive edin.

## Platform Hedefleri

- Android: minSdk 21 (Lollipop)
- iOS: 12.0+

## İzinler

Aşağıdaki izinler önceden tanımlanmıştır:

**Android:**
- `INTERNET`, `ACCESS_NETWORK_STATE`
- `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`
- `POST_NOTIFICATIONS`, `VIBRATE`, `WAKE_LOCK`
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`
- `CALL_PHONE`

**iOS (`Info.plist`):**
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `UIBackgroundModes`: fetch, location, remote-notification

## Test

```bash
flutter test
flutter analyze
```
