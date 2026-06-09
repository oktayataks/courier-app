import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../models/order.dart';
import '../providers/location_provider.dart';

class NavigationScreen extends ConsumerStatefulWidget {
  final Order? order;

  const NavigationScreen({super.key, required this.order});

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  bool _initialFitDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationProvider.notifier).getCurrentLocation();
      _setupMarkers();
    });
  }

  /// Alış + teslim noktalarını ekrana sığdıracak şekilde kamerayı çerçevele.
  /// Map controller hazır değilse no-op.
  Future<void> _fitToBounds() async {
    final controller = _mapController;
    final order = widget.order;
    if (controller == null || order == null) return;

    final pickupLat = order.pickupAddress.latitude;
    final pickupLng = order.pickupAddress.longitude;
    final deliveryLat = order.deliveryAddress.latitude;
    final deliveryLng = order.deliveryAddress.longitude;

    // Noktalar aynıysa veya geçersizse (0,0) tek noktaya zoom yap.
    if ((pickupLat == 0 && pickupLng == 0) ||
        (deliveryLat == 0 && deliveryLng == 0)) {
      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(
        pickupLat < deliveryLat ? pickupLat : deliveryLat,
        pickupLng < deliveryLng ? pickupLng : deliveryLng,
      ),
      northeast: LatLng(
        pickupLat > deliveryLat ? pickupLat : deliveryLat,
        pickupLng > deliveryLng ? pickupLng : deliveryLng,
      ),
    );
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  void _setupMarkers() {
    final order = widget.order;
    if (order == null) return;

    setState(() {
      _markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(
            order.pickupAddress.latitude,
            order.pickupAddress.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(
            title: 'Alış Noktası',
            snippet: order.pickupAddress.title ?? order.pickupAddress.fullAddress,
          ),
        ),
      );

      _markers.add(
        Marker(
          markerId: const MarkerId('delivery'),
          position: LatLng(
            order.deliveryAddress.latitude,
            order.deliveryAddress.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: 'Teslim Noktası',
            snippet: order.deliveryAddress.fullAddress,
          ),
        ),
      );

      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          color: AppColors.primary,
          width: 4,
          points: [
            LatLng(
              order.pickupAddress.latitude,
              order.pickupAddress.longitude,
            ),
            LatLng(
              order.deliveryAddress.latitude,
              order.deliveryAddress.longitude,
            ),
          ],
        ),
      );
    });
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

    final initialPosition = CameraPosition(
      target: LatLng(
        order.pickupAddress.latitude,
        order.pickupAddress.longitude,
      ),
      zoom: 14,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Navigasyon')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: initialPosition,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: locationState.hasPermission,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              if (!_initialFitDone) {
                _initialFitDone = true;
                Future.delayed(const Duration(milliseconds: 300), _fitToBounds);
              }
            },
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: _buildOrderInfo(order),
          ),
          Positioned(
            right: 16,
            bottom: 100,
            child: Column(
              children: [
                _buildMapButton(
                  icon: Icons.my_location_rounded,
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final notifier = ref.read(locationProvider.notifier);
                    await notifier.getCurrentLocation();
                    if (!mounted) return;

                    final pos = ref.read(locationProvider).currentPosition;
                    if (pos != null && _mapController != null) {
                      await _mapController!.animateCamera(
                        CameraUpdate.newLatLngZoom(
                          LatLng(pos.latitude, pos.longitude),
                          16,
                        ),
                      );
                      return;
                    }

                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Konum alınamadı. Ayarlardan konum izni verin.',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _buildMapButton(
                  icon: Icons.zoom_out_map_rounded,
                  onTap: () => _fitToBounds(),
                ),
              ],
            ),
          ),
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
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${order.distanceKm.toStringAsFixed(1)} km • ${order.estimatedMinutes} dk',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
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
