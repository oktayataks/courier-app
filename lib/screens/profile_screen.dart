import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../services/storage_service.dart';
import '../widgets/logo_background.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Map<String, dynamic>? _courierData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCourierData();
  }

  Future<void> _loadCourierData() async {
    try {
      final token = await StorageService.getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/couriers/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        setState(() {
          _courierData = json.decode(response.body) as Map<String, dynamic>;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    final courierUser =
        _courierData?['user'] as Map<String, dynamic>? ?? {};
    final fullName = courierUser['fullName'] as String? ??
        _courierData?['fullName'] as String? ??
        user?.name ??
        '-';
    final email = courierUser['email'] as String? ??
        _courierData?['email'] as String? ??
        user?.email ??
        '-';
    final phone = courierUser['phone'] as String? ??
        _courierData?['phone'] as String? ??
        user?.phone ??
        '-';
    final vehicleType =
        _courierData?['vehicleType'] as String? ?? '-';
    final rating = _courierData?['rating']?.toString() ?? '0.00';
    final totalDeliveries =
        _courierData?['totalDeliveries']?.toString() ?? '-';
    final isOnline = _courierData?['isOnline'] as bool? ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profilim'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadCourierData();
            },
          ),
        ],
      ),
      body: LogoBackground(
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryLight,
                  ),
                )
              : ListView(
                  children: [
                    const SizedBox(height: 16),
                    _buildProfileHeader(fullName, phone, isOnline),
                    const SizedBox(height: 16),
                    _buildStatsRow(totalDeliveries, rating),
                    const SizedBox(height: 8),
                    _buildMenuSection(
                      title: 'Kişisel Bilgiler',
                      items: [
                        _MenuItem(
                          icon: Icons.person_outline_rounded,
                          label: 'Ad Soyad',
                          trailing: fullName,
                          onTap: () {},
                        ),
                        _MenuItem(
                          icon: Icons.email_outlined,
                          label: 'E-posta',
                          trailing: email,
                          onTap: () {},
                        ),
                        _MenuItem(
                          icon: Icons.phone_outlined,
                          label: 'Telefon',
                          trailing: phone,
                          onTap: () {},
                        ),
                      ],
                    ),
                    _buildMenuSection(
                      title: 'Araç Bilgileri',
                      items: [
                        _MenuItem(
                          icon: Icons.directions_bike_rounded,
                          label: 'Araç Tipi',
                          trailing: _vehicleLabel(vehicleType),
                          onTap: () {},
                        ),
                        _MenuItem(
                          icon: Icons.star_outline_rounded,
                          label: 'Puan',
                          trailing: '$rating ⭐',
                          onTap: () {},
                        ),
                        _MenuItem(
                          icon: isOnline
                              ? Icons.check_circle_outline
                              : Icons.cancel_outlined,
                          label: 'Durum',
                          trailing: isOnline ? 'Çevrimiçi' : 'Çevrimdışı',
                          onTap: () {},
                        ),
                      ],
                    ),
                    _buildMenuSection(
                      title: 'Uygulama',
                      items: [
                        _MenuItem(
                          icon: Icons.notifications_outlined,
                          label: 'Bildirimler',
                          onTap: () {},
                        ),
                        _MenuItem(
                          icon: Icons.language_rounded,
                          label: 'Dil',
                          trailing: 'Türkçe',
                          onTap: () {},
                        ),
                      ],
                    ),
                    _buildMenuSection(
                      title: 'Destek',
                      items: [
                        _MenuItem(
                          icon: Icons.help_outline_rounded,
                          label: 'Yardım Merkezi',
                          onTap: () {},
                        ),
                        _MenuItem(
                          icon: Icons.info_outline_rounded,
                          label: 'Hakkında',
                          trailing: 'v1.0.0',
                          onTap: () {},
                        ),
                        _MenuItem(
                          icon: Icons.privacy_tip_outlined,
                          label: 'Gizlilik Politikası',
                          onTap: () {},
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton.icon(
                        onPressed: () => _handleLogout(context, ref),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          side: const BorderSide(color: AppColors.error),
                          foregroundColor: AppColors.error,
                        ),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text(
                          'Çıkış Yap',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
        ),
      ),
    );
  }

  String _vehicleLabel(String type) {
    switch (type) {
      case 'motorbike':
        return 'Motorsiklet';
      case 'bike':
        return 'Bisiklet';
      case 'car':
        return 'Araba';
      default:
        return type;
    }
  }

  Future<void> _handleLogout(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Çıkış yapmak istediğinize emin misiniz?'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    await ref.read(authProvider.notifier).logout();

    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.login,
      (_) => false,
    );
  }

  Widget _buildProfileHeader(
      String name, String phone, bool isOnline) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.circular(40),
            ),
            child: CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.surface,
              child: CircleAvatar(
                radius: 30,
                backgroundColor:
                    AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'K',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 24,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  phone,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (isOnline ? AppColors.success : AppColors.error)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOnline
                            ? Icons.verified_rounded
                            : Icons.cancel_outlined,
                        size: 12,
                        color: isOnline
                            ? AppColors.success
                            : AppColors.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isOnline ? 'Çevrimiçi' : 'Çevrimdışı',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isOnline
                              ? AppColors.success
                              : AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(String deliveries, String rating) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildStatCol('Teslimat', deliveries),
          _buildDivider(),
          _buildStatCol('Puan', rating),
          _buildDivider(),
          _buildStatCol('Durum', 'Aktif'),
        ],
      ),
    );
  }

  Widget _buildStatCol(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 32,
      color: AppColors.divider,
    );
  }

  Widget _buildMenuSection({
    required String title,
    required List<_MenuItem> items,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: items.asMap().entries.map((e) {
                final isLast = e.key == items.length - 1;
                return Column(
                  children: [
                    ListTile(
                      onTap: e.value.onTap,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          e.value.icon,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        e.value.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (e.value.trailing != null)
                            Flexible(
                              child: Text(
                                e.value.trailing!,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textHint,
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      const Padding(
                        padding: EdgeInsets.only(left: 60),
                        child: Divider(height: 1),
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;

  _MenuItem({
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
  });
}
