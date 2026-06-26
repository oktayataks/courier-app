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

  // ── Veri Yükleme ────────────────────────────────────────────────────────────

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

    if (activeOrders.length >= 4) {
      if (mounted) setState(() => _suggestedOrder = null);
      return;
    }

    if (activeOrders.isEmpty) {
      final nearest = await _findNearestOrder(availableOrders);
      if (mounted) setState(() => _suggestedOrder = nearest);
      return;
    }

    final compatible = await _findCompatibleOrder(availableOrders, activeOrders);
    if (mounted) setState(() => _suggestedOrder = compatible);
  }

  Future<Order?> _findCompatibleOrder(
    List<Order> available,
    List<Order> activeOrders,
  ) async {
    final compatible = <Order>[];

    for (final order in available) {
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

      final orderLat = order.deliveryLatitude;
      final orderLng = order.deliveryLongitude;
      if (orderLat == 0 && orderLng == 0) continue;

      final isClose = activeOrders.any((active) {
        final activeLat = active.deliveryLatitude;
        final activeLng = active.deliveryLongitude;
        if (activeLat == 0 && activeLng == 0) return false;
        final distance = Geolocator.distanceBetween(
          activeLat, activeLng, orderLat, orderLng,
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
        myPos.latitude, myPos.longitude, restaurantLat, restaurantLng,
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

      // 1. Kabul et (pending → assigned)
      final acceptResponse = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/orders/${order.id}/accept'),
        headers: headers,
      );
      debugPrint('✅ Accept: ${acceptResponse.statusCode}');

      if (!mounted) return;

      if (acceptResponse.statusCode == 200 || acceptResponse.statusCode == 201) {
        // 2. Otomatik yola çıktı (assigned → picked_up)
        final statusResponse = await http.patch(
          Uri.parse('${AppConstants.apiBaseUrl}/orders/${order.id}/status'),
          headers: headers,
          body: json.encode({'status': 'picked_up'}),
        );
        debugPrint('✅ Status picked_up: ${statusResponse.statusCode}');
        debugPrint('✅ Status body: ${statusResponse.body}');

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
          SnackBar(
            content: Text('❌ Sipariş alınamadı (${acceptResponse.statusCode})'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Kabul hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  Future<void> _toggleOnline() async {
    final courier = ref.read(courierProvider);
    if (courier == null) return;
    final wasOnline = courier.isOnline;
    await ref.read(courierProvider.notifier).toggleOnlineStatus();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(!wasOnline ? 'Çevrimiçi oldunuz' : 'Çevrimdışı oldunuz'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final courier = ref.watch(courierProvider);
    final ordersState = ref.watch(ordersProvider);
    final isOnline = courier?.isOnline ?? false;
    final activeOrder = _activeOrders.isNotEmpty ? _activeOrders.first : null;
    final displayOrder = activeOrder ?? _suggestedOrder;

    return Scaffold(
      // ── Kompakt AppBar ──────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        shadowColor: Colors.black12,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.black87),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: const AppLogo(),
            ),
            const SizedBox(width: 8),
            const Text(
              'KuryeApp',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          // Online/Offline pill toggle
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: _toggleOnline,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isOnline ? Colors.green.shade50 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isOnline ? Colors.green : Colors.grey.shade400,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        color: isOnline
                            ? Colors.green.shade800
                            : Colors.grey.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),

      drawer: _buildDrawer(context, user?.fullName),

      // ── Body: Stack (harita + kartlar) ─────────────────────────────────────
      body: Stack(
        children: [
          // Tam ekran harita
          _buildMap(displayOrder),

          // Yükleniyor göstergesi (sol üst)
          if (_isRefreshing)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),

          // 4 sipariş limit uyarısı (üstte)
          if (_activeOrders.length >= 4)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 8),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Maksimum 4 aktif siparişin var. Birini tamamla, sonra yeni alabilirsin.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Aktif sipariş sayacı (üst sol, limit yoksa)
          if (_activeOrders.isNotEmpty && _activeOrders.length < 4)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 6),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.delivery_dining, size: 16, color: Colors.orange),
                    const SizedBox(width: 6),
                    Text(
                      '${_activeOrders.length} / 4 Aktif',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Alt sipariş kartı
          if (displayOrder != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomOrderCard(displayOrder, activeOrder != null),
            ),

          // Hiç sipariş yoksa bilgi kartı
          if (displayOrder == null && !_isRefreshing)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 12),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(Icons.coffee_outlined, size: 36, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    const Text(
                      'Şu an müsait sipariş yok',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Yeni sipariş gelince bildirim alacaksın',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _refreshOrders,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Yenile'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Harita (flutter_map + OpenStreetMap) ─────────────────────────────────────
  Widget _buildMap(Order? displayOrder) {
    final myPos = _myPosition;

    // Varsayılan merkez: Türkiye ortası
    final defaultCenter = LatLng(39.9, 32.8);
    final center = myPos != null
        ? LatLng(myPos.latitude, myPos.longitude)
        : defaultCenter;

    final markers = <Marker>[];

    // Kurye konumu
    if (myPos != null) {
      markers.add(
        Marker(
          point: LatLng(myPos.latitude, myPos.longitude),
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
            ),
            child: const Icon(Icons.person_pin, color: Colors.white, size: 20),
          ),
        ),
      );
    }

    // Aktif siparişlerin teslimat noktaları (mavi)
    for (final order in _activeOrders) {
      final lat = order.deliveryLatitude;
      final lng = order.deliveryLongitude;
      if (lat == 0 && lng == 0) continue;
      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 36,
          height: 36,
          child: Tooltip(
            message: '#${order.orderNumber}',
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: const Icon(Icons.location_on, color: Colors.white, size: 18),
            ),
          ),
        ),
      );
    }

    // Önerilen siparişin restoranı (turuncu)
    if (_suggestedOrder != null) {
      final rLat = _suggestedOrder!.restaurant?.latitude;
      final rLng = _suggestedOrder!.restaurant?.longitude;
      if (rLat != null && rLng != null && rLat != 0 && rLng != 0) {
        markers.add(
          Marker(
            point: LatLng(rLat, rLng),
            width: 40,
            height: 40,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
              ),
              child: const Icon(Icons.store, color: Colors.white, size: 20),
            ),
          ),
        );
      }
    }

    return FlutterMap(
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
    );
  }

  // ── Alt Sipariş Kartı ────────────────────────────────────────────────────────
  Widget _buildBottomOrderCard(Order order, bool isActive) {
    final displayName = isActive
        ? order.customerName
        : (order.restaurant?.name ?? order.pickupAddress.title ?? 'Restoran');
    final displayAddress = isActive
        ? order.deliveryAddress.fullAddress
        : (order.restaurant?.address ?? order.pickupAddress.fullAddress);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tutamak çubuğu
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Ana içerik satırı
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OrderDetailScreen(order: order),
              ),
            ),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  // İkon
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.blue.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isActive ? Icons.delivery_dining : Icons.restaurant,
                      color: isActive ? Colors.blue : Colors.orange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Bilgiler
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '#${order.orderNumber}',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.location_on,
                                size: 13, color: Colors.grey.shade500),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                displayAddress,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
          // Kabul Et butonu (sadece öneri için)
          if (!isActive && _suggestedOrder != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isAccepting
                      ? null
                      : () => _acceptSuggestedOrder(_suggestedOrder!),
                  icon: _isAccepting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_circle_outline, size: 18),
                  label: Text(
                    _isAccepting
                        ? 'İşleniyor...'
                        : (_activeOrders.isEmpty
                            ? 'Siparişi Kabul Et'
                            : 'Bu Siparişi de Al'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          // Aktif sipariş varsa çoklu kart önizleme
          if (isActive && _activeOrders.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.layers_outlined,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_activeOrders.length} aktif sipariş — detay için dokun',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          if (isActive && _activeOrders.length == 1)
            const SizedBox(height: 6),
        ],
      ),
    );
  }

  // ── Drawer ───────────────────────────────────────────────────────────────────
  Widget _buildDrawer(BuildContext context, String? userName) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Stack(
        children: [
          // Arka plan logo
          Positioned(
            bottom: 40,
            right: -60,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.04,
                child: AppLogo(size: 220, fallbackColor: AppTheme.primaryLight),
              ),
            ),
          ),
          ListView(
            padding: EdgeInsets.zero,
            children: [
              // Header
              Container(
                height: 180,
                decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const AppLogo(),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          userName ?? 'Kurye',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'KuryeApp',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              _drawerItem(
                context,
                icon: Icons.home_rounded,
                color: AppTheme.primaryLight,
                title: 'Ana Sayfa',
                onTap: () => Navigator.pop(context),
              ),
              _drawerItem(
                context,
                icon: Icons.attach_money_rounded,
                color: Colors.green,
                title: 'Kazançlarım',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.earnings);
                },
              ),
              _drawerItem(
                context,
                icon: Icons.my_location_rounded,
                color: Colors.blue,
                title: 'Konumum',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.myLocation);
                },
              ),
              _drawerItem(
                context,
                icon: Icons.history_rounded,
                color: Colors.purple,
                title: 'Geçmiş Siparişler',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.orderHistory);
                },
              ),
              _drawerItem(
                context,
                icon: Icons.person_rounded,
                color: Colors.indigo,
                title: 'Profil',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.profile);
                },
              ),
              _drawerItem(
                context,
                icon: Icons.inventory_2_outlined,
                color: Colors.teal,
                title: 'Sipariş Havuzu',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.orderPool);
                },
              ),
              _drawerItem(
                context,
                icon: Icons.receipt_long_outlined,
                color: Colors.amber.shade700,
                title: 'Hesap Özeti',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.earningsReport);
                },
              ),
              _drawerItem(
                context,
                icon: Icons.local_shipping_outlined,
                color: Colors.brown,
                title: 'Teslimat Raporu',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.deliveryReport);
                },
              ),
              _drawerItem(
                context,
                icon: Icons.calendar_today_outlined,
                color: Colors.cyan.shade700,
                title: 'Vardiyalarım',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.shifts);
                },
              ),
              _drawerItem(
                context,
                icon: Icons.receipt_outlined,
                color: Colors.deepOrange,
                title: 'Faturalarım',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.invoices);
                },
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Divider(),
              ),

              _drawerItem(
                context,
                icon: Icons.support_agent_rounded,
                color: Colors.red,
                title: 'Yazılı Destek',
                subtitle: 'Mola, kaza, müşteri sorunları',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HelpScreen(
                        activeOrder: _activeOrders.firstOrNull,
                      ),
                    ),
                  );
                },
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Divider(),
              ),

              _drawerItem(
                context,
                icon: Icons.account_circle_outlined,
                color: Colors.grey,
                title: 'Kullanıcı Sözleşmesi',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.userAgreement);
                },
              ),
              _drawerItem(
                context,
                icon: Icons.privacy_tip_outlined,
                color: Colors.grey,
                title: 'Gizlilik Sözleşmesi',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.privacyPolicy);
                },
              ),
              _drawerItem(
                context,
                icon: Icons.shield_outlined,
                color: Colors.grey,
                title: 'KVKK',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.kvkk);
                },
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Divider(),
              ),

              _drawerItem(
                context,
                icon: Icons.logout_rounded,
                color: AppTheme.accentRed,
                title: 'Çıkış Yap',
                isDestructive: true,
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

              const SizedBox(height: 24),
            ],
          ),
        ],
      ),
    );
  }

  Widget _drawerItem(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: isDestructive ? AppTheme.accentRed : AppTheme.textPrimary,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 11))
          : null,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      dense: true,
    );
  }
}
