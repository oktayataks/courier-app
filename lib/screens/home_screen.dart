import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/courier_provider.dart';
import '../providers/orders_provider.dart';
import '../services/location_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/logo_background.dart';
import '../widgets/order_card.dart';
import 'order_detail_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (!mounted) return;
      await ref.read(courierProvider.notifier).loadCourier();
      ref.read(ordersProvider.notifier).loadOrders();

      final courier = ref.read(courierProvider);
      if (courier != null) {
        LocationService.startBackendTracking(courier.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final courier = ref.watch(courierProvider);
    final ordersAsync = ref.watch(ordersAsyncProvider);
    final isOnline = courier?.isOnline ?? false;

    return Scaffold(
      drawer: _buildDrawer(context),
      body: LogoBackground(
        child: Column(
          children: [
          Container(
            decoration: const BoxDecoration(
              gradient: AppTheme.headerGradient,
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 14),
                child: Row(
                  children: [
                    Builder(
                      builder: (ctx) => IconButton(
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                        icon: const Icon(
                          Icons.menu,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const AppLogo(fallbackColor: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'İsim: ${user?.fullName ?? ''}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Telefon: ${user?.phone ?? ''}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    _OnlineToggleButton(
                      isOnline: isOnline,
                      enabled: courier != null,
                      onPressed: () async {
                        if (courier == null) return;
                        final wasOnline = courier.isOnline;
                        await ref
                            .read(courierProvider.notifier)
                            .toggleOnlineStatus();
                        if (!context.mounted) return;
                        final nowOnline = !wasOnline;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              nowOnline
                                  ? 'Çevrimiçi oldunuz'
                                  : 'Çevrimdışı oldunuz',
                            ),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                    _HeaderIconButton(
                      icon: Icons.notifications_outlined,
                      onPressed: () {},
                    ),
                    const SizedBox(width: 6),
                    _HeaderIconButton(
                      icon: Icons.settings_outlined,
                      onPressed: () {
                        Navigator.of(context).pushNamed(AppRoutes.profile);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ordersAsync.when(
              data: (orders) {
                if (orders.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Henüz sipariş yok',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    await ref.read(ordersProvider.notifier).loadOrders();
                  },
                  color: AppTheme.primaryLight,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return OrderCard(
                        order: order,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => OrderDetailScreen(
                                order: orders[index],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryLight),
              ),
              error: (error, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: AppTheme.accentRed,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Hata: $error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          ref.read(ordersProvider.notifier).loadOrders();
                        },
                        child: const Text('Yeniden Dene'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final user = ref.watch(userProvider);
    return Drawer(
      backgroundColor: Colors.white,
      child: Stack(
        children: [
          Positioned(
            bottom: 40,
            right: -60,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.05,
                child: AppLogo(
                  size: 250,
                  fallbackColor: AppTheme.primaryLight,
                ),
              ),
            ),
          ),
          ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            height: 200,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: AppTheme.headerGradient,
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const AppLogo(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user?.fullName ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.phone ?? '',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildDrawerItem(
            icon: Icons.list_alt_outlined,
            title: 'Siparişlerim',
            onTap: () => Navigator.pop(context),
          ),
          _buildDrawerItem(
            icon: Icons.inventory_2_outlined,
            title: 'Sipariş Havuzu',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).pushNamed(AppRoutes.orderPool);
            },
          ),
          _buildDrawerItem(
            icon: Icons.history_outlined,
            title: 'Paket Geçmişi',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).pushNamed(AppRoutes.orderHistory);
            },
          ),
          _buildDrawerItem(
            icon: Icons.payments_outlined,
            title: 'Ödeme Raporu',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).pushNamed(AppRoutes.earnings);
            },
          ),
          _buildDrawerItem(
            icon: Icons.trending_up_outlined,
            title: 'Kazanç Raporu',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).pushNamed(AppRoutes.earningsReport);
            },
          ),
          _buildDrawerItem(
            icon: Icons.receipt_long_outlined,
            title: 'Hesap Özeti Raporu',
            onTap: () => Navigator.pop(context),
          ),
          _buildDrawerItem(
            icon: Icons.restaurant_outlined,
            title: 'Restoran Teslimat Raporu',
            onTap: () => Navigator.pop(context),
          ),
          _buildDrawerItem(
            icon: Icons.calendar_today_outlined,
            title: 'Vardiyalarım',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).pushNamed(AppRoutes.shifts);
            },
          ),
          _buildDrawerItem(
            icon: Icons.check_circle_outline,
            title: 'Vardiya Slot Seçimi',
            onTap: () => Navigator.pop(context),
          ),
          _buildDrawerItem(
            icon: Icons.receipt_outlined,
            title: 'Faturalarım',
            onTap: () => Navigator.pop(context),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(height: 1),
          ),
          _buildDrawerItem(
            icon: Icons.account_circle_outlined,
            title: 'Kullanıcı Sözleşmesi',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).pushNamed(AppRoutes.userAgreement);
            },
          ),
          _buildDrawerItem(
            icon: Icons.privacy_tip_outlined,
            title: 'Gizlilik Sözleşmesi',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).pushNamed(AppRoutes.privacyPolicy);
            },
          ),
          _buildDrawerItem(
            icon: Icons.shield_outlined,
            title: 'KVKK Aydınlatma Metni',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).pushNamed(AppRoutes.kvkk);
            },
          ),
          _buildDrawerItem(
            icon: Icons.info_outline,
            title: 'Uygulama İzinleri',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).pushNamed(AppRoutes.appPermissions);
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(height: 1),
          ),
          _buildDrawerItem(
            icon: Icons.logout,
            title: 'Çıkış Yap',
            textColor: AppTheme.accentRed,
            onTap: () async {
              Navigator.pop(context);
              await ref.read(authProvider.notifier).logout();
              if (!context.mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.login,
                (route) => false,
              );
            },
          ),
          const SizedBox(height: 20),
        ],
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: textColor ?? AppTheme.textSecondary,
        size: 22,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: textColor ?? AppTheme.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      dense: true,
    );
  }
}

class _OnlineToggleButton extends StatelessWidget {
  final bool isOnline;
  final bool enabled;
  final VoidCallback onPressed;

  const _OnlineToggleButton({
    required this.isOnline,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: isOnline ? AppTheme.successGreen : AppTheme.accentRed,
        foregroundColor: Colors.white,
        disabledBackgroundColor:
            (isOnline ? AppTheme.successGreen : AppTheme.accentRed)
                .withValues(alpha: 0.6),
        disabledForegroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      child: Text(
        isOnline ? 'Çevrimiçi' : 'Çevrimdışı',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _HeaderIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
