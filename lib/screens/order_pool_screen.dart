import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/constants.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../providers/orders_provider.dart';
import '../widgets/logo_background.dart';
import '../widgets/order_card.dart';

class OrderPoolScreen extends ConsumerWidget {
  const OrderPoolScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersAsyncProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sipariş Havuzu'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.headerGradient,
          ),
        ),
      ),
      body: LogoBackground(
        child: ordersAsync.when(
        data: (orders) {
          final pendingOrders =
              orders.where((o) => o.status == OrderStatus.pending).toList();

          if (pendingOrders.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_basket_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Havuzda bekleyen sipariş yok',
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
              itemCount: pendingOrders.length,
              itemBuilder: (context, index) {
                final order = pendingOrders[index];
                return OrderCard(
                  order: order,
                  onTap: () {
                    Navigator.of(context).pushNamed(
                      AppRoutes.orderDetail,
                      arguments: order,
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
            child: Text(
              'Hata: $error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
