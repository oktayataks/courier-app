import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../models/order.dart';
import '../providers/location_provider.dart';

class NavigationScreen extends ConsumerStatefulWidget {
  final Order? order;

  const NavigationScreen({super.key, required this.order});

  @override
  ConsumerState<NavigationScreen> createState() =>
      _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  final MapController _mapController = MapController();
  bool _initialFitDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationProvider.notifier).getCurrentLocation();
      if (!_initialFitDone) {
        _initialFitDone = true;
        Future.delayed(const Duration(milliseconds: 500), _fitToBounds);
      }
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _fitToBounds() {
    final order = widget.order;
    if (order == null) return;

    final pickupLat = order.pickupAddress.latitude;
    final pickupLng = order.pickupAddress.longitude;
    final deliveryLat = order.deliveryAddress.latitude;
    final deliveryLng = order.deliveryAddress.longitude;

    if ((pickupLat == 0 && pickupLng == 0) ||
        (deliveryLat == 0 && deliveryLng == 0)) return;

    final bounds = LatLngBounds(
      LatLng(
        pickupLat < deliveryLat ? pickupLat : deliveryLat,
        pickupLng < deliveryLng ? pickupLng : deliveryLng,
      ),
      LatLng(
        pickupLat > deliveryLat ? pickupLat : deliveryLat,
        pickupLng > deliveryLng ? pickupLng : deliveryLng,
      ),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(60),
      ),
    );
  }

  Future<void> _openExternalNavigation() async {
    final order = widget.order;
    if (order == null) return;

    final url =
        'https://www.google.com/maps/dir/?api=1&destination=${order.deliveryAddress.latitude},${order.deliveryAddress.longitude}&travelmode=driving';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationState = ref.watch(locationProvider);
    final order = widget.order;

    if (order == null) {
      return const Scaffold(
        body: Center(child: Text('Sipariş bulunamadı')),
      );
    }

    final pickupLatLng = LatLng(
      order.pickupAddress.latitude,
      order.pickupAddress.longitude,
    );
    final deliveryLatLng = LatLng(
      order.deliveryAddress.latitude,
      order.deliveryAddress.longitude,
    );

    final currentPos = locationState.currentPosition;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigasyon'),
        flexibleSpace: Container(
          decoration:
              const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: pickupLatLng,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.courier_app',
                maxZoom: 19,
              ),
              // Rota çizgisi
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [pickupLatLng, deliveryLatLng],
                    color: AppColors.primary,
                    strokeWidth: 4,
                  ),
                ],
              ),
              // Marker'lar
              MarkerLayer(
                markers: [
                  // Alış noktası (turuncu)
                  Marker(
                    point: pickupLatLng,
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.store_rounded,
                      color: AppColors.accent,
                      size: 36,
                    ),
                  ),
                  // Teslim noktası (yeşil)
                  Marker(
                    point: deliveryLatLng,
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.location_pin,
                      color: AppColors.success,
                      size: 40,
                    ),
                  ),
                  // Mevcut konum (mavi)
                  if (currentPos != null)
                    Marker(
                      point: LatLng(
                          currentPos.latitude, currentPos.longitude),
                      width: 32,
                      height: 32,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.navigation_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Sipariş bilgisi (üst)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: _buildOrderInfo(order),
          ),

          // Harita kontrolleri (sağ)
          Positioned(
            right: 16,
            bottom: 100,
            child: Column(
              children: [
                _buildMapButton(
                  icon: Icons.my_location_rounded,
                  onTap: () async {
                    final notifier =
                        ref.read(locationProvider.notifier);
                    await notifier.getCurrentLocation();
                    if (!mounted) return;
                    final pos =
                        ref.read(locationProvider).currentPosition;
                    if (pos != null) {
                      _mapController.move(
                        LatLng(pos.latitude, pos.longitude),
                        16,
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                _buildMapButton(
                  icon: Icons.zoom_out_map_rounded,
                  onTap: _fitToBounds,
                ),
              ],
            ),
          ),

          // Navigasyon butonu (alt)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            child: ElevatedButton.icon(
              onPressed: _openExternalNavigation,
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Harici Navigasyon ile Aç'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderInfo(Order order) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.delivery_dining_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.orderNumber,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '${order.distanceKm.toStringAsFixed(1)} km • ${order.estimatedMinutes} dk',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
