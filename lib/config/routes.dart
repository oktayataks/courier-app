import 'package:flutter/material.dart';
import '../models/order.dart';
import '../screens/document_screen.dart';
import '../screens/earnings_report_screen.dart';
import '../screens/earnings_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/navigation_screen.dart';
import '../screens/order_detail_screen.dart';
import '../screens/order_history_screen.dart';
import '../screens/order_pool_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/shifts_screen.dart';
import '../screens/splash_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String orderDetail = '/order-detail';
  static const String navigation = '/navigation';
  static const String earnings = '/earnings';
  static const String profile = '/profile';

  // Drawer sayfaları
  static const String orderPool = '/order-pool';
  static const String orderHistory = '/order-history';
  static const String earningsReport = '/earnings-report';
  static const String shifts = '/shifts';
  static const String userAgreement = '/user-agreement';
  static const String privacyPolicy = '/privacy-policy';
  static const String kvkk = '/kvkk';
  static const String appPermissions = '/app-permissions';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _buildRoute(const SplashScreen(), settings);
      case login:
        return _buildRoute(const LoginScreen(), settings);
      case home:
        return _buildRoute(const HomeScreen(), settings);
      case orderDetail:
        final order = settings.arguments as Order?;
        return _buildRoute(OrderDetailScreen(order: order), settings);
      case navigation:
        final order = settings.arguments as Order?;
        return _buildRoute(NavigationScreen(order: order), settings);
      case earnings:
        return _buildRoute(const EarningsScreen(), settings);
      case profile:
        return _buildRoute(const ProfileScreen(), settings);

      // Drawer sayfaları
      case orderPool:
        return _buildRoute(const OrderPoolScreen(), settings);
      case orderHistory:
        return _buildRoute(const OrderHistoryScreen(), settings);
      case earningsReport:
        return _buildRoute(const EarningsReportScreen(), settings);
      case shifts:
        return _buildRoute(const ShiftsScreen(), settings);
      case userAgreement:
        return _buildRoute(
          const DocumentScreen(
            title: 'Kullanıcı Sözleşmesi',
            content:
                'Kullanıcı sözleşmesi metni buraya gelecek.\n\n'
                'Bu metin daha sonra hukuk ekibinden alınacak olan resmi sözleşme '
                'içeriği ile değiştirilecektir.',
          ),
          settings,
        );
      case privacyPolicy:
        return _buildRoute(
          const DocumentScreen(
            title: 'Gizlilik Sözleşmesi',
            content:
                'Gizlilik sözleşmesi metni buraya gelecek.\n\n'
                'Bu metin daha sonra hukuk ekibinden alınacak olan resmi gizlilik '
                'politikası içeriği ile değiştirilecektir.',
          ),
          settings,
        );
      case kvkk:
        return _buildRoute(
          const DocumentScreen(
            title: 'KVKK Aydınlatma Metni',
            content:
                'KVKK aydınlatma metni buraya gelecek.\n\n'
                '6698 sayılı Kişisel Verilerin Korunması Kanunu kapsamında '
                'kullanıcılarımıza yönelik aydınlatma metni daha sonra eklenecektir.',
          ),
          settings,
        );
      case appPermissions:
        return _buildRoute(
          const DocumentScreen(
            title: 'Uygulama İzinleri',
            content:
                'Uygulama izinleri açıklaması buraya gelecek.\n\n'
                'Konum: Aktif sipariş takibi için kullanılır.\n'
                'Bildirim: Yeni sipariş bildirimleri için kullanılır.\n'
                'Telefon: Müşteriyi aramak için kullanılır.\n'
                'İnternet: Backend ile iletişim için kullanılır.',
          ),
          settings,
        );

      default:
        return _buildRoute(
          const Scaffold(
            body: Center(child: Text('Sayfa bulunamadı')),
          ),
          settings,
        );
    }
  }

  static MaterialPageRoute<T> _buildRoute<T>(
    Widget page,
    RouteSettings settings,
  ) {
    return MaterialPageRoute<T>(
      builder: (_) => page,
      settings: settings,
    );
  }
}
