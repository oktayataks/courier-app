import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../models/order.dart';
import '../providers/orders_provider.dart';
import '../widgets/custom_button.dart';
import '../widgets/logo_background.dart';
import '../widgets/status_badge.dart';

class OrderDetailScreen extends ConsumerWidget {
  final Order? order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (order == null) {
      return const Scaffold(
        body: Center(child: Text('Sipariş bulunamadı')),
      );
    }

    final o = order!;
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
          const SizedBox(height: 80),
        ],
        ),
      ),
      bottomSheet: _buildBottomActions(context, ref, o),
    );
  }

  Widget _buildBottomActions(BuildContext context, WidgetRef ref, Order o) {
    if (o.status == OrderStatus.cancelled) {
      return const SizedBox.shrink();
    }

    if (o.status == OrderStatus.delivered) {
      return Container(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          12 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.check_circle, color: AppColors.success, size: 24),
            SizedBox(width: 8),
            Text(
              'Teslim Edildi',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: CustomButton(
              label: 'Navigasyon',
              icon: Icons.navigation_rounded,
              type: ButtonType.outline,
              onPressed: () => Navigator.pushNamed(
                context,
                AppRoutes.navigation,
                arguments: o,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: CustomButton(
              label: _getActionLabel(o.status),
              icon: Icons.check_circle_rounded,
              onPressed: () => _handleStatusUpdate(context, ref, o),
            ),
          ),
        ],
      ),
    );
  }

  String _getActionLabel(String status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Kabul Et';
      case OrderStatus.assigned:
        return 'Yola Çıktım';
      case OrderStatus.pickedUp:
      case OrderStatus.inTransit:
        return 'Teslim Ettim';
      default:
        return 'Devam Et';
    }
  }

  Future<void> _handleStatusUpdate(
    BuildContext context,
    WidgetRef ref,
    Order o,
  ) async {
    String nextStatus;
    switch (o.status) {
      case OrderStatus.pending:
        nextStatus = OrderStatus.assigned;
        break;
      case OrderStatus.assigned:
        nextStatus = OrderStatus.pickedUp;
        break;
      case OrderStatus.pickedUp:
      case OrderStatus.inTransit:
        nextStatus = OrderStatus.delivered;
        break;
      default:
        return;
    }

    final ok = o.status == OrderStatus.pending
        ? await ref.read(ordersProvider.notifier).acceptOrder(o.id)
        : await ref.read(ordersProvider.notifier).updateOrderStatus(
              o.id,
              nextStatus,
            );

    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Durum güncellendi: ${OrderStatus.getLabel(nextStatus)}'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (nextStatus == OrderStatus.delivered) {
        Navigator.pop(context);
      }
    }
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
