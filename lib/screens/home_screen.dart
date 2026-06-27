import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
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

enum CourierStatus { online, onBreak }

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

  // Çoklu sipariş gezme
  int _currentOrderIndex = 0;
  final PageController _pageController = PageController();

  // Kurye durumu
  CourierStatus _status = CourierStatus.online;
  DateTime? _breakUntil;
  Timer? _offerCheckTimer;
  Timer? _breakCheckTimer;
  Order? _currentOffer;

  // Backend'deki gerçek courier ID (lazy-fetch)
  String? _courierId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      ref.read(courierProvider.notifier).loadCourier();
      _refreshOrders();
    });
    _startOfferCheck();
    _startBreakCheck();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _offerCheckTimer?.cancel();
    _breakCheckTimer?.cancel();
    super.dispose();
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

  // ── Timer başlatıcılar ───────────────────────────────────────────────────────
  void _startOfferCheck() {
    _offerCheckTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkForOffer(),
    );
  }

  void _startBreakCheck() {
    _breakCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkBreakStatus(),
    );
  }

  Future<void> _checkBreakStatus() async {
    if (_status == CourierStatus.onBreak && _breakUntil != null) {
      if (DateTime.now().isAfter(_breakUntil!)) {
        setState(() {
          _status = CourierStatus.online;
          _breakUntil = null;
        });
        await _endBreakAPI();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('☕ Molan bitti, çevrimiçi oldun!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  // ── Durum menüsü ─────────────────────────────────────────────────────────────
  void _showStatusMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Durum',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Online seçeneği (molada değilse göster)
              if (_status != CourierStatus.online)
                _buildStatusOption(
                  icon: Icons.check_circle,
                  color: Colors.green,
                  title: 'Çevrimiçi',
                  subtitle: 'Yeni siparişler alabilirim',
                  onTap: () async {
                    if (_breakUntil != null &&
                        DateTime.now().isBefore(_breakUntil!)) {
                      final remaining =
                          _breakUntil!.difference(DateTime.now());
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '⏳ Mola bitmesine ${remaining.inMinutes} dakika var'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _status = CourierStatus.online;
                      _breakUntil = null;
                    });
                    Navigator.pop(ctx);
                    await _endBreakAPI();
                  },
                ),

              // Mola seçenekleri (online iken göster)
              if (_status == CourierStatus.online) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '☕ Mola Süresi',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ),
                _buildStatusOption(
                  icon: Icons.coffee,
                  color: Colors.orange,
                  title: '15 Dakika Mola',
                  subtitle: 'Kısa mola',
                  onTap: () => _startBreak(ctx, 15),
                ),
                _buildStatusOption(
                  icon: Icons.lunch_dining,
                  color: Colors.orange,
                  title: '30 Dakika Mola',
                  subtitle: 'Uzun mola',
                  onTap: () => _startBreak(ctx, 30),
                ),
              ],

              // Mola sayacı (molada iken göster)
              if (_status == CourierStatus.onBreak && _breakUntil != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.coffee, size: 32, color: Colors.orange),
                      const SizedBox(height: 8),
                      Text(
                        'Mola Bitiş',
                        style: TextStyle(color: Colors.orange.shade800),
                      ),
                      Text(
                        '${_breakUntil!.hour.toString().padLeft(2, '0')}:${_breakUntil!.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      Text(
                        '${_breakUntil!.difference(DateTime.now()).inMinutes} dakika kaldı',
                        style: TextStyle(color: Colors.orange.shade700),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Mola ─────────────────────────────────────────────────────────────────────
  Future<void> _startBreak(BuildContext ctx, int minutes) async {
    Navigator.pop(ctx);
    try {
      final token = await StorageService.getToken();
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/couriers/me/break'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'minutes': minutes}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        setState(() {
          _status = CourierStatus.onBreak;
          _breakUntil = DateTime.parse(data['breakUntil'] as String);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('☕ $minutes dakikalık mola başladı'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Mola hatası: $e');
    }
  }

  Future<void> _endBreakAPI() async {
    try {
      final token = await StorageService.getToken();
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/couriers/me/break/end'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      debugPrint('Mola bitirme hatası: $e');
    }
  }

  // ── Teklif Kontrol ───────────────────────────────────────────────────────────
  Future<void> _checkForOffer() async {
    if (_status != CourierStatus.online) return;
    if (_currentOffer != null) return; // Modal zaten açık
    try {
      final token = await StorageService.getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/orders/offered/me'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 &&
          response.body.isNotEmpty &&
          response.body != 'null') {
        final data = json.decode(response.body);
        if (data != null && data['id'] != null) {
          final offer = Order.fromJson(data as Map<String, dynamic>);
          if (mounted) _showOfferModal(offer);
        }
      }
    } catch (e) {
      debugPrint('Teklif kontrolü hatası: $e');
    }
  }

  void _showOfferModal(Order order) {
    _currentOffer = order;
    int remainingSeconds = 30;
    Timer? countdownTimer;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          countdownTimer ??= Timer.periodic(
            const Duration(seconds: 1),
            (timer) {
              if (remainingSeconds <= 0) {
                timer.cancel();
                Navigator.pop(ctx);
                _rejectOffer(order.id, isTimeout: true);
                return;
              }
              setModalState(() => remainingSeconds--);
            },
          );

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Geri sayım çemberi
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: remainingSeconds > 10
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: remainingSeconds > 10 ? Colors.green : Colors.red,
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$remainingSeconds',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color:
                            remainingSeconds > 10 ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '🛵 Yeni Sipariş!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Sipariş detayları
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${order.orderNumber}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.restaurant,
                            size: 15, color: Colors.orange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            order.restaurant?.name ?? 'Restoran',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.location_on,
                            size: 15, color: Colors.red),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            order.deliveryAddress.fullAddress,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      if (order.totalAmount != null)
                        Text(
                          '₺${order.totalAmount!.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.green,
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                Row(children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        countdownTimer?.cancel();
                        Navigator.pop(ctx);
                        _rejectOffer(order.id);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Reddet'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        countdownTimer?.cancel();
                        Navigator.pop(ctx);
                        _acceptOffer(order.id);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '✅ Kabul Et',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    ).then((_) {
      countdownTimer?.cancel();
      _currentOffer = null;
    });
  }

  Future<void> _acceptOffer(String orderId) async {
    try {
      final token = await StorageService.getToken();
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/orders/$orderId/accept-offer'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _refreshOrders();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Sipariş kabul edildi!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Teklif kabul hatası: $e');
    }
  }

  Future<void> _rejectOffer(String orderId, {bool isTimeout = false}) async {
    try {
      final token = await StorageService.getToken();
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/orders/$orderId/reject-offer'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      debugPrint('Teklif red hatası: $e');
    }

    if (!isTimeout && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sipariş reddedildi'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ── Courier ID (lazy-fetch) ──────────────────────────────────────────────────
  Future<String?> _fetchCourierId() async {
    if (_courierId != null) return _courierId;
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final res = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/couriers/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        _courierId = data['id']?.toString();
        debugPrint('🔍 Courier ID önbelleğe alındı: $_courierId');
      }
    } catch (e) {
      debugPrint('⚠️ Courier ID alınamadı: $e');
    }
    return _courierId;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    ref.watch(courierProvider); // reactive update
    ref.watch(ordersProvider);
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
          // Durum pill butonu (Online / Molada)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: _showStatusMenu,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _status == CourierStatus.online
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _status == CourierStatus.online
                        ? Colors.green
                        : Colors.orange,
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
                        color: _status == CourierStatus.online
                            ? Colors.green
                            : Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _status == CourierStatus.online ? 'Online' : 'Molada',
                      style: TextStyle(
                        color: _status == CourierStatus.online
                            ? Colors.green.shade800
                            : Colors.orange.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: _status == CourierStatus.online
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 3 nokta menü
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black54),
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  Navigator.of(context).pushNamed(AppRoutes.profile);
                case 'history':
                  Navigator.of(context).pushNamed(AppRoutes.orderHistory);
                case 'notifications':
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(children: [
                  Icon(Icons.person_outline_rounded, color: Colors.indigo),
                  SizedBox(width: 12),
                  Text('Profil'),
                ]),
              ),
              const PopupMenuItem(
                value: 'history',
                child: Row(children: [
                  Icon(Icons.history_rounded, color: Colors.purple),
                  SizedBox(width: 12),
                  Text('Geçmiş'),
                ]),
              ),
              const PopupMenuItem(
                value: 'notifications',
                child: Row(children: [
                  Icon(Icons.notifications_outlined, color: Colors.orange),
                  SizedBox(width: 12),
                  Text('Bildirimler'),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 4),
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
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showMarkerInfo(
              icon: '🏠',
              title: order.customerName,
              subtitle: order.deliveryAddress.fullAddress,
              orderNumber: '#${order.orderNumber}',
              phone: order.customerPhone,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
              ),
              child: const Icon(Icons.location_on, color: Colors.white, size: 20),
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
        final suggested = _suggestedOrder!;
        markers.add(
          Marker(
            point: LatLng(rLat, rLng),
            width: 44,
            height: 44,
            child: GestureDetector(
              onTap: () => _showMarkerInfo(
                icon: '🍽️',
                title: suggested.restaurant?.name ?? 'Restoran',
                subtitle: suggested.restaurant?.address ?? '',
                orderNumber: '#${suggested.orderNumber}',
                phone: suggested.restaurant?.phone,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                ),
                child: const Icon(Icons.store, color: Colors.white, size: 22),
              ),
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

  // ── Marker Bilgi Paneli ──────────────────────────────────────────────────────
  void _showMarkerInfo({
    required String icon,
    required String title,
    required String subtitle,
    String? orderNumber,
    String? phone,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (orderNumber != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          orderNumber,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (phone != null && phone.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final uri = Uri.parse(
                        'tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  icon: const Icon(Icons.phone, size: 18),
                  label: Text(phone),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Alt Sipariş Kartı (PageView destekli) ────────────────────────────────────
  Widget _buildBottomOrderCard(Order _, bool __) {
    // Aktif siparişler varsa PageView ile swipe
    if (_activeOrders.isNotEmpty) {
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
            // Tutamak
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
            SizedBox(
              height: 80,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _activeOrders.length,
                onPageChanged: (i) {
                  setState(() => _currentOrderIndex = i);
                  final order = _activeOrders[i];
                  final lat = order.deliveryLatitude;
                  final lng = order.deliveryLongitude;
                  if (lat != 0 && lng != 0) {
                    _mapController.move(LatLng(lat, lng), 15);
                  }
                },
                itemBuilder: (context, index) {
                  final order = _activeOrders[index];
                  return _buildOrderRow(order, isActive: true);
                },
              ),
            ),
            // Dots indicator
            if (_activeOrders.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_activeOrders.length, (i) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _currentOrderIndex ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: i == _currentOrderIndex
                            ? Colors.orange
                            : Colors.grey.shade300,
                      ),
                    );
                  }),
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      );
    }

    // Önerilen sipariş (tek kart)
    if (_suggestedOrder != null) {
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
            _buildOrderRow(_suggestedOrder!, isActive: false),
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
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildOrderRow(Order order, {required bool isActive}) {
    final displayName = isActive
        ? order.customerName
        : (order.restaurant?.name ?? order.pickupAddress.title ?? 'Restoran');
    final displayAddress = isActive
        ? order.deliveryAddress.fullAddress
        : (order.restaurant?.address ?? order.pickupAddress.fullAddress);

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderDetailScreen(order: order),
        ),
      ),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isActive ? Colors.blue.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isActive ? Icons.delivery_dining : Icons.restaurant,
                color: isActive ? Colors.blue : Colors.orange,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
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
                            fontSize: 14,
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
                          size: 12, color: Colors.grey.shade500),
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

              _drawerItem(
                context,
                icon: Icons.inventory_2_outlined,
                color: Colors.purple,
                title: 'Sipariş Havuzu',
                subtitle: 'Tüm bekleyen siparişler',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.orderPool);
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
