import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Uygulama logosu için merkezi widget.
///
/// `assets/images/taby_logo.png` dosyası mevcut değilse [errorBuilder]
/// fallback olarak [Icons.delivery_dining_rounded] ikonunu gösterir.
/// Böylece PNG dosyası eklenmeden de UI çalışır.
class AppLogo extends StatelessWidget {
  static const String assetPath = 'assets/images/taby_logo.png';

  final double? size;
  final Color? fallbackColor;
  final BoxFit fit;

  const AppLogo({
    super.key,
    this.size,
    this.fallbackColor,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        return Icon(
          Icons.delivery_dining_rounded,
          size: size,
          color: fallbackColor ?? AppTheme.primaryColor,
        );
      },
    );
  }
}
