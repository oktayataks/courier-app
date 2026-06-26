import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/constants.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../models/order.dart';
import '../providers/auth_provider.dart';
import '../providers/courier_provider.dart';
import '../providers/orders_provider.dart';
import '../services/storage_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/logo_background.dart';
import '../widgets/order_card.dart';
import 'help_screen.dart';
import 'order_detail_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<Order> _activeOrders = [];
  Order? _suggestedOrder;
  Position? _myPosition;
  bool _isRefreshing = false;
  bool _isAccepting = false;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      ref.read(courierProvider.notifier).loadCourier();
      _refreshOrders();
    });
  }

  Future<void> _refreshOrders() async {
    if (!mounted) return;
    setState(() => _isRefreshing = true);
    await ref.read(ordersProvider.notifier).loadOrders();
    await _updateSuggestedOrder();
    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<void> _updateSuggestedOrder() async {
    final ordersState = ref.read(ordersProvider);
    final activeOrders = ordersState.activeOrders;
    final availableOrders = ordersState.availableOrders;

    if (mounted) setState(() => _activeOrders = activeOrders);

    // Maksimum 4 sipariş
    if (activeOrders.length >= 4) {
      if (mounted) setState(() => _suggestedOrder = null);
      return;
    }

    // Aktif sipariş yoksa → en yakın pending
    if (activeOrders.isEmpty) {
      final nearest = await _findNearestOrder(availableOrders);
      if (mounted) setState(() => _suggestedOrder = nearest);
      return;
    }

    // Aktif sipariş varsa → uyumlu sipariş bul
    final compatible = await _findCompatibleOrder(availableOrders, activeOrders);
    if (mounted) setState(() => _suggestedOrder = compatible);
  }

  Future<Order?> _findCompatibleOrder(
    List<Order> available,
    List<Order> activeOrders,
  ) async {
    final compatible = <Order>[];

    for (final order in available) {
      // Aynı restoran mı?
      final sameRestaurant = activeOrders.any(
        (active) =>
            active.restaurantId != null &&
            order.restaurantId != null &&
            active.restaurantId == order.restaurantId,
      );

      if (sameRestaurant) {
        compatible.add(order);
        continue;
      }

      // Teslimat adresi 2km içinde mi?
      final orderLat = order.deliveryLatitude;
      final orderLng = order.deliveryLongitude;
      if (orderLat == 0 && orderLng == 0) continue;

      final isClose = activeOrders.any((active) {
        final activeLat = active.deliveryLatitude;
        final activeLng = active.deliveryLongitude;
        if (activeLat == 0 && activeLng == 0) return false;

        final distance = Geolocator.distanceBetween(
          activeLat,
          activeLng,
          orderLat,
          orderLng,
        );
        return distance <= 2000;
      });

      if (isClose) compatible.add(order);
    }

    if (compatible.isEmpty) return null;
    return await _findNearestOrder(compatible);
  }

  Future<Order?> _findNearestOrder(List<Order> orders) async {
    if (orders.isEmpty) return null;

    Position? myPos;
    try {
      myPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (mounted) setState(() => _myPosition = myPos);
    } catch (e) {
      return orders.first;
    }

    Order? nearest;
    double minDistance = double.infinity;

    for (final order in orders) {
      final restaurantLat = order.restaurant?.latitude;
      final restaurantLng = order.restaurant?.longitude;
      if (restaurantLat == null || restaurantLng == null) continue;

      final distance = Geolocator.distanceBetween(
        myPos.latitude,
        myPos.longitude,
        restaurantLat,
        restaurantLng,
      );

      if (distance < minDistance) {
        minDistance = distance;
        nearest = order;
      }
    }

    return nearest ?? orders.first;
  }

  Future<void> _acceptSuggestedOrder(Order order) async {
    if (_isAccepting) return;
    setState(() => _isAccepting = true);

    try {
      final token = await StorageService.getToken();
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final acceptResponse = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/orders/${order.id}/accept'),
        headers: headers,
      );

      if (!mounted) return;

      if (acceptResponse.statusCode == 200 || acceptResponse.statusCode == 201) {
        await http.patch(
          Uri.parse('${AppConstants.apiBaseUrl}/orders/${order.id}/status'),
          headers: headers,
          body: json.encode({'status': 'picked_up'}),
        );

        await _refreshOrders();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sipariş kabul edildi, yola çıktınız!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Sipariş alınamadı!'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final courier = ref.watch(courierProvider);
    final ordersState = ref.watch(ordersProvider);
    final isOnline = courier?.isOnline ?? false;
    final activeOrder = _activeOrders.isNotEmpty ? _activeOrders.first : null;

    return Scaffold(
      drawer: _buildDrawer(context),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HelpScreen(activeOrder: activeOrder),
          ),
        ),
        icon: const Icon(Icons.help_outline_rounded),
        label: const Text('Yardım'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 0,
        selectedItemColor: AppTheme.primaryLight,
        unselectedItemColor: AppTheme.textSecondary,
        onTap: (index) {
          switch (index) {
            case 1:
              Navigator.of(context).pushNamed(AppRoutes.myLocation);
            case 2:
              Navigator.of(context).pushNamed(AppRoutes.earnings);
            case 3:
              Navigator.of(context).pushNamed(AppRoutes.orderHistory);
            case 4:
              Navigator.of(context).pushNamed(AppRoutes.profile);
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Ana Sayfa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.my_location_rounded),
            label: 'Konumum',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.payments_outlined),
            label: 'Kazançlar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded),
            label: 'Geçmiş',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
      body: LogoBackground(
        child: Column(
          children: [
            // ── Gradient Header ──────────────────────────────────────
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

            // ── Online Toggle Kartı ───────────────────────────────────
            _buildOnlineToggleCard(context, courier, isOnline),

            // ── İçerik (harita + siparişler) ─────────────────────────
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshOrders,
                color: AppTheme.primaryLight,
                child: _buildContent(context, ordersState),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── İçerik (harita + siparişler) ────────────────────────────────────────────
  Widget _buildContent(BuildContext context, OrdersState ordersState) {
    final isLoading = (ordersState.isLoading || _isRefreshing) &&
        _activeOrders.isEmpty &&
        _suggestedOrder == null;

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryLight),
      );
    }

    if (ordersState.error != null && _activeOrders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppTheme.accentRed),
              const SizedBox(height: 16),
              Text(
                'Hata: ${ordersState.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _refreshOrders,
                child: const Text('Yeniden Dene'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Harita
          _buildMapSection(_activeOrders.firstOrNull ?? _suggestedOrder),

          // ── Aktif Siparişlerim ─────────────────────────────────────
          if (_activeOrders.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Aktif Siparişlerim',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_activeOrders.length} / 4',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 170,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _activeOrders.length,
                itemBuilder: (context, i) {
                  final order = _activeOrders[i];
                  return SizedBox(
                    width: 280,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: OrderCard(
                        order: order,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderDetailScreen(order: order),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ── 4 Sipariş Limit Uyarısı ───────────────────────────────
          if (_activeOrders.length >= 4)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.yellow.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.yellow.shade400),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Maksimum 4 aktif siparişin var. Birini tamamla, sonra yeni alabilirsin.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // ── Önerilen Sipariş ──────────────────────────────────────
          if (_suggestedOrder != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text(
                _activeOrders.isEmpty
                    ? '🎯 Sizin İçin Önerilen Sipariş'
                    : '🎯 Önerilen Yeni Sipariş',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.shade300, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Uyumluluk rozeti (aktif sipariş varsa)
                  if (_activeOrders.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Text(
                        '✅ Mevcut sipariş(ler)inle uyumlu',
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  // Sipariş bilgileri
                  OrderCard(
                    order: _suggestedOrder!,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            OrderDetailScreen(order: _suggestedOrder!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Kabul et butonu
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isAccepting
                          ? null
                          : () => _acceptSuggestedOrder(_suggestedOrder!),
                      icon: _isAccepting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_circle_outline),
                      label: Text(
                        _isAccepting
                            ? 'İşleniyor...'
                            : (_activeOrders.isEmpty
                                ? 'Siparişi Kabul Et'
                                : 'Bu Siparişi de Al'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Hiç sipariş yok ───────────────────────────────────────
          if (_activeOrders.isEmpty && _suggestedOrder == null)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.coffee_outlined,
                      size: 72,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Şu an müsait sipariş yok',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Yeni sipariş gelince bildirim alacaksın',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _refreshOrders,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Yenile'),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 90), // FAB boşluğu
        ],
      ),
    );
  }

  // ── Harita ─────────────────────────────────────────────────────────────────
  Widget _buildMapSection(Order? displayOrder) {
    final myPos = _myPosition;
    final restaurantLat = displayOrder?.restaurant?.latitude;
    final restaurantLng = displayOrder?.restaurant?.longitude;

    final hasMyPos = myPos != null;
    final hasRestaurant = restaurantLat != null &&
        restaurantLng != null &&
        restaurantLat != 0 &&
        restaurantLng != 0;

    if (!hasMyPos && !hasRestaurant) {
      return Container(
        height: 180,
        color: Colors.grey.shade100,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 40, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'Konum alınıyor...',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final center = hasMyPos
        ? LatLng(myPos.latitude, myPos.longitude)
        : LatLng(restaurantLat!, restaurantLng!);

    final markers = <Marker>[
      if (hasMyPos)
        Marker(
          point: LatLng(myPos.latitude, myPos.longitude),
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4),
              ],
            ),
            child: const Icon(Icons.person_pin, color: Colors.white, size: 18),
          ),
        ),
      if (hasRestaurant)
        Marker(
          point: LatLng(restaurantLat as double, restaurantLng as double),
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4),
              ],
            ),
            child: const Icon(Icons.store, color: Colors.white, size: 20),
          ),
        ),
    ];

    return SizedBox(
      height: 200,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 14,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.taby.courier',
          ),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }

  Widget _buildOnlineToggleCard(
      BuildContext context, courier, bool isOnline) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isOnline ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOnline ? Colors.green : Colors.grey.shade400,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.check_circle : Icons.pause_circle,
            color: isOnline ? Colors.green : Colors.grey,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOnline ? 'Çevrimiçi' : 'Çevrimdışı',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isOnline ? Colors.green : Colors.grey.shade700,
                  ),
                ),
                Text(
                  isOnline ? 'Sipariş alabilirsin' : 'Sipariş alamazsın',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Switch(
            value: isOnline,
            onChanged: courier == null
                ? null
                : (value) async {
                    await ref
                        .read(courierProvider.notifier)
                        .toggleOnlineStatus();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          value ? 'Çevrimiçi oldunuz' : 'Çevrimdışı oldunuz',
                        ),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
            activeColor: Colors.green,
          ),
        ],
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
                icon: Icons.my_location_rounded,
                title: 'Konumum',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.myLocation);
                },
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
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.earningsReport);
                },
              ),
              _buildDrawerItem(
                icon: Icons.local_shipping_outlined,
                title: 'Restoran Teslimat Raporu',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.deliveryReport);
                },
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
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.shifts);
                },
              ),
              _buildDrawerItem(
                icon: Icons.receipt_outlined,
                title: 'Faturalarım',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.invoices);
                },
              ),
              _buildDrawerItem(
                icon: Icons.help_outline_rounded,
                title: 'Yardım Merkezi',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HelpScreen(
                        activeOrder:
                            ref.read(ordersProvider).activeOrders.firstOrNull,
                      ),
                    ),
                  );
                },
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
