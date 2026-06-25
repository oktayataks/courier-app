import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../services/storage_service.dart';
import '../widgets/logo_background.dart';

class DeliveryReportScreen extends StatefulWidget {
  const DeliveryReportScreen({super.key});

  @override
  State<DeliveryReportScreen> createState() => _DeliveryReportScreenState();
}

class _DeliveryReportScreenState extends State<DeliveryReportScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  String? _error;

  final _currency = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
  final _timeFmt = DateFormat('HH:mm', 'tr_TR');
  final _fullDateFmt = DateFormat('dd MMM yyyy', 'tr_TR');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final token = await StorageService.getToken();
      final res = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/orders/my-orders'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final raw =
            data is List ? data : (data['data'] ?? data['orders'] ?? []);
        setState(() {
          _orders = (raw as List)
              .cast<Map<String, dynamic>>()
              .where((o) => o['status'] == 'delivered')
              .toList()
            ..sort((a, b) {
              final da = _parseDate(a['deliveredAt'] ?? a['createdAt']);
              final db = _parseDate(b['deliveredAt'] ?? b['createdAt']);
              return db.compareTo(da);
            });
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Sunucu hatası: ${res.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Bağlantı hatası';
        _isLoading = false;
      });
    }
  }

  DateTime _parseDate(dynamic v) =>
      DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();

  double _fee(Map<String, dynamic> o) =>
      double.tryParse(o['deliveryFee']?.toString() ?? '0') ?? 0.0;

  String _duration(Map<String, dynamic> o) {
    final assigned = DateTime.tryParse(
        o['assignedAt']?.toString() ?? o['accepted_at']?.toString() ?? '');
    final delivered =
        DateTime.tryParse(o['deliveredAt']?.toString() ?? '');
    if (assigned == null || delivered == null) return '-';
    final diff = delivered.difference(assigned);
    if (diff.inHours > 0) return '${diff.inHours}s ${diff.inMinutes % 60}dk';
    return '${diff.inMinutes}dk';
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _grouped() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final groups = <String, List<Map<String, dynamic>>>{
      'Bugün': [],
      'Dün': [],
      'Bu Hafta': [],
      'Daha Önce': [],
    };

    for (final o in _orders) {
      final d = _parseDate(o['deliveredAt'] ?? o['createdAt']);
      final day = DateTime(d.year, d.month, d.day);
      if (day == today) {
        groups['Bugün']!.add(o);
      } else if (day == yesterday) {
        groups['Dün']!.add(o);
      } else if (day.isAfter(weekAgo)) {
        groups['Bu Hafta']!.add(o);
      } else {
        groups['Daha Önce']!.add(o);
      }
    }

    return groups.entries.where((e) => e.value.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teslimat Raporu'),
        flexibleSpace: Container(
          decoration:
              const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: LogoBackground(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                    color: AppTheme.primaryLight))
            : _error != null
                ? _buildError()
                : _orders.isEmpty
                    ? _buildEmpty()
                    : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final grouped = _grouped();
    final todayOrders = grouped
        .firstWhere((e) => e.key == 'Bugün',
            orElse: () => const MapEntry('Bugün', []))
        .value;
    final todayEarnings =
        todayOrders.fold<double>(0, (s, o) => s + _fee(o));

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              _statChip(
                icon: Icons.today_rounded,
                label: 'Bugün',
                value: '${todayOrders.length} teslimat',
                color: AppTheme.primaryLight,
              ),
              const SizedBox(width: 10),
              _statChip(
                icon: Icons.payments_rounded,
                label: 'Bugün Kazanç',
                value: _currency.format(todayEarnings),
                color: AppTheme.successGreen,
              ),
              const SizedBox(width: 10),
              _statChip(
                icon: Icons.all_inbox_rounded,
                label: 'Toplam',
                value: '${_orders.length} teslimat',
                color: AppTheme.orangePrice,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppTheme.primaryLight,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: _itemCount(grouped),
              itemBuilder: (_, i) => _itemAt(i, grouped),
            ),
          ),
        ),
      ],
    );
  }

  int _itemCount(
      List<MapEntry<String, List<Map<String, dynamic>>>> grouped) {
    return grouped.fold<int>(0, (sum, e) => sum + 1 + e.value.length);
  }

  Widget _itemAt(int index,
      List<MapEntry<String, List<Map<String, dynamic>>>> grouped) {
    var cursor = 0;
    for (final group in grouped) {
      if (index == cursor) return _groupHeader(group.key, group.value);
      cursor++;
      for (final order in group.value) {
        if (index == cursor) return _orderRow(order);
        cursor++;
      }
    }
    return const SizedBox.shrink();
  }

  Widget _groupHeader(
      String label, List<Map<String, dynamic>> items) {
    final total = items.fold<double>(0, (s, o) => s + _fee(o));
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${items.length} teslimat',
              style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.primaryLight,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const Spacer(),
          Text(_currency.format(total),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.successGreen)),
        ],
      ),
    );
  }

  Widget _orderRow(Map<String, dynamic> o) {
    final deliveredAt =
        DateTime.tryParse(o['deliveredAt']?.toString() ?? '') ??
            DateTime.tryParse(o['createdAt']?.toString() ?? '') ??
            DateTime.now();
    final customer = o['customer'] is Map
        ? (o['customer']['name']?.toString() ?? '-')
        : (o['customerName']?.toString() ?? '-');
    final address = () {
      if (o['delivery_address'] is Map) {
        return o['delivery_address']['fullAddress']?.toString() ?? '-';
      }
      if (o['deliveryAddress'] is Map) {
        return o['deliveryAddress']['fullAddress']?.toString() ?? '-';
      }
      return o['deliveryAddress']?.toString() ??
          o['delivery_address']?.toString() ??
          '-';
    }();
    final fee = _fee(o);
    final dur = _duration(o);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border:
            Border(bottom: BorderSide(color: AppTheme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppTheme.successGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(customer,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(_timeFmt.format(deliveredAt),
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(address,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Row(
                  children: [
                    if (dur != '-') ...[
                      const Icon(Icons.timer_outlined,
                          size: 12, color: AppTheme.textSecondary),
                      const SizedBox(width: 3),
                      Text(dur,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary)),
                      const SizedBox(width: 10),
                    ],
                    const Icon(Icons.payments_rounded,
                        size: 12, color: AppTheme.successGreen),
                    const SizedBox(width: 3),
                    Text('+${_currency.format(fee)}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.successGreen)),
                    const Spacer(),
                    Text(_fullDateFmt.format(deliveredAt),
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 9, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delivery_dining_rounded,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('Henüz tamamlanan teslimat yok',
              style: TextStyle(
                  fontSize: 16, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline,
              size: 56, color: AppTheme.accentRed),
          const SizedBox(height: 12),
          Text(_error!,
              style: const TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar Dene'),
          ),
        ],
      ),
    );
  }
}
