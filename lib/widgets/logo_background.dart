import 'package:flutter/material.dart';
import '../config/theme.dart';
import 'app_logo.dart';

/// Sayfa zemini için merkezi watermark logo widget'ı.
///
/// `Scaffold.body`'sini sararak tüm uygulamada tutarlı bir arka plan
/// filigranı uygular. Logo cihaz ekran boyutuna göre orantılanır
/// (`shortestSide * 0.75`) ve [IgnorePointer] ile dokunuşları engellemez.
class LogoBackground extends StatelessWidget {
  final Widget child;
  final double opacity;

  const LogoBackground({
    super.key,
    required this.child,
    this.opacity = 0.05,
  });

  @override
  Widget build(BuildContext context) {
    final shortest = MediaQuery.of(context).size.shortestSide;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Opacity(
                opacity: opacity,
                child: AppLogo(
                  size: shortest * 0.75,
                  fallbackColor: AppTheme.primaryDark,
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
