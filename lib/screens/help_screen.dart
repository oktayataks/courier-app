import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/order.dart';

class HelpScreen extends StatelessWidget {
  final Order? activeOrder;

  const HelpScreen({super.key, this.activeOrder});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yardım Merkezi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (activeOrder != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.delivery_dining, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        'Aktif Sipariş',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '#${activeOrder!.orderNumber}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    activeOrder!.customerName,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          const Text(
            'Size Nasıl Yardımcı Olabiliriz?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          _buildHelpItem(
            context,
            icon: Icons.location_off,
            iconColor: Colors.red,
            title: 'Adres Yanlış',
            subtitle: 'Verilen adres hatalı veya bulunamıyor',
            onTap: () => _callAdmin(),
          ),
          _buildHelpItem(
            context,
            icon: Icons.phone_disabled,
            iconColor: Colors.orange,
            title: 'Müşteriye Ulaşılamıyor',
            subtitle: 'Telefon açılmıyor veya yanıt verilmiyor',
            onTap: () => _callAdmin(),
          ),
          _buildHelpItem(
            context,
            icon: Icons.cancel_outlined,
            iconColor: Colors.red,
            title: 'Siparişi İptal Et',
            subtitle: 'Teslim edilemiyor, iptal gerekli',
            onTap: () => _showCancelConfirm(context),
          ),
          _buildHelpItem(
            context,
            icon: Icons.storefront_outlined,
            iconColor: Colors.amber,
            title: 'Restoran Problemi',
            subtitle: 'Sipariş hazır değil veya hatalı hazırlanmış',
            onTap: () => _callAdmin(),
          ),
          _buildHelpItem(
            context,
            icon: Icons.traffic_outlined,
            iconColor: Colors.blue,
            title: 'Trafik / Kaza',
            subtitle: 'Gecikme yaşıyorum, durum bildirimi',
            onTap: () => _callAdmin(),
          ),
          _buildHelpItem(
            context,
            icon: Icons.directions_bike_outlined,
            iconColor: Colors.purple,
            title: 'Araç Arızası',
            subtitle: 'Araçta sorun var, destek gerekiyor',
            onTap: () => _callAdmin(),
          ),

          const SizedBox(height: 24),

          // Yöneticiyi ara butonu
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _callAdmin,
              icon: const Icon(Icons.support_agent),
              label: const Text(
                'Yöneticiyi Ara',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildHelpItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: iconColor.withValues(alpha: 0.12),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  void _showCancelConfirm(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Siparişi İptal Et'),
        content: const Text(
          'Siparişi iptal etmek için lütfen yöneticinizi arayın.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _callAdmin();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Yöneticiyi Ara'),
          ),
        ],
      ),
    );
  }

  Future<void> _callAdmin() async {
    const adminPhone = '05551234567';
    final uri = Uri.parse('tel:$adminPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
