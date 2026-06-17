import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../models/order.dart';
import '../providers/orders_provider.dart';
import '../services/storage_service.dart';
import '../widgets/logo_background.dart';
import '../widgets/status_badge.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  final Order? order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  String? _selectedStatus;

  List<String> _getAvailableStatuses(String currentStatus) {
    final status = currentStatus.toLowerCase();
    if (status.contains('assigned')) {
      return ['picked_up', 'delivered'];
    } else if (status.contains('picked_up')) {
      return ['delivered'];
    }
    return [];
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'picked_up':
        return '🚴 Yola Çıktım';
      case 'delivered':
        return '✅ Teslim Ettim';
      case 'assigned':
        return '📦 Atandı';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    if (order == null) {
      return const Scaffold(
        body: Center(child: Text('Sipariş bulunamadı')),
      );
    }

    final o = order;
    final currency = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

    return Scaffold(
      appBar: AppBar(
        title: Text(o.orderNumber),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: LogoBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(child: StatusBadge(status: o.status, fontSize: 14)),
            const SizedBox(height: 16),
            _buildSection(
              title: 'Müşteri Bilgileri',
              child: Column(
                children: [
                  _buildInfoRow(
                    icon: Icons.person_rounded,
                    label: 'Ad Soyad',
                    value: o.customer.name,
                  ),
                  const Divider(height: 16),
                  _buildInfoRow(
                    icon: Icons.phone_rounded,
                    label: 'Telefon',
                    value: o.customer.phone,
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.call_rounded,
                        color: AppColors.success,
                      ),
                      onPressed: () => _launchUrl('tel:${o.customer.phone}'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildSection(
              title: 'Alış Adresi',
              icon: Icons.store_rounded,
              iconColor: AppColors.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (o.pickupAddress.title != null)
                    Text(
                      o.pickupAddress.title!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    o.pickupAddress.fullAddress,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildSection(
              title: 'Teslim Adresi',
              icon: Icons.location_on_rounded,
              iconColor: AppColors.accent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.deliveryAddress.fullAddress,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (o.deliveryAddress.floor != null ||
                      o.deliveryAddress.doorNo != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (o.deliveryAddress.floor != null)
                          _buildAddressTag('Kat: ${o.deliveryAddress.floor}'),
                        const SizedBox(width: 8),
                        if (o.deliveryAddress.doorNo != null)
                          _buildAddressTag('Daire: ${o.deliveryAddress.doorNo}'),
                      ],
                    ),
                  ],
                  if (o.notes != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: AppColors.warning,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(o.notes!)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (o.items.isNotEmpty)
              _buildSection(
                title: 'Sipariş İçeriği',
                child: Column(
                  children: o.items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${item.quantity}x',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(item.name)),
                          Text(
                            currency.format(item.price * item.quantity),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            if (o.items.isNotEmpty) const SizedBox(height: 12),
            _buildSection(
              title: 'Ödeme Özeti',
              child: Column(
                children: [
                  _buildPriceRow(
                    'Sipariş Tutarı',
                    currency.format(o.totalAmount),
                  ),
                  const SizedBox(height: 8),
                  _buildPriceRow(
                    'Teslimat Ücreti',
                    currency.format(o.deliveryFee),
                  ),
                  const Divider(height: 24),
                  _buildPriceRow(
                    'Toplam',
                    currency.format(o.totalAmount + o.deliveryFee),
                    isBold: true,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          o.paymentMethod == 'cash'
                              ? Icons.money_rounded
                              : Icons.credit_card_rounded,
                          color: AppColors.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          o.paymentMethod == 'cash' ? 'Nakit' : 'Kart',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildActionButtons(context, o),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, Order order) {
    final currentStatus = order.status.toLowerCase();

    if (currentStatus.contains('delivered')) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            '✅ Sipariş Teslim Edildi',
            style: TextStyle(
              color: Colors.green,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    if (currentStatus.contains('pending')) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () async {
            final token = await StorageService.getToken();

            final response = await http.post(
              Uri.parse(
                '${AppConstants.apiBaseUrl}/orders/${order.id}/accept',
              ),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
            );

            if (response.statusCode == 200 ||
                response.statusCode == 201) {
              await ref.read(ordersProvider.notifier).loadOrders();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Sipariş kabul edildi!'),
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.pop(context);
              }
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ Sipariş alınamadı!'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
          icon: const Icon(Icons.check_circle),
          label: const Text(
            'Siparişi Kabul Et',
            style: TextStyle(fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      );
    }

    final availableStatuses = _getAvailableStatuses(currentStatus);

    if (availableStatuses.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Durum Güncelle',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedStatus,
              hint: const Text('Durum seçin...'),
              isExpanded: true,
              items: availableStatuses.map((status) {
                return DropdownMenuItem<String>(
                  value: status,
                  child: Text(_getStatusLabel(status)),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedStatus = value;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _selectedStatus == null
                ? null
                : () async {
                    if (_selectedStatus == null) return;

                    final ok = await ref
                        .read(ordersProvider.notifier)
                        .updateOrderStatus(order.id, _selectedStatus!);

                    if (!context.mounted) return;
                    if (ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${_getStatusLabel(_selectedStatus!)} olarak güncellendi!',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                      Navigator.pop(context);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Durum güncellenemedi'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.update),
            label: const Text(
              'Durumu Güncelle',
              style: TextStyle(fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryLight,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required Widget child,
    IconData? icon,
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: (iconColor ?? AppColors.primary)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: iconColor ?? AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildAddressTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildPriceRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 18 : 14,
            fontWeight: FontWeight.w700,
            color: isBold ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
