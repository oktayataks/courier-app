import 'package:flutter/material.dart';
import '../config/theme.dart';

enum ButtonType { primary, secondary, outline, danger }

class CustomButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonType type;
  final bool isLoading;
  final bool fullWidth;
  final double height;

  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.type = ButtonType.primary,
    this.isLoading = false,
    this.fullWidth = true,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _getColors();

    final button = SizedBox(
      width: fullWidth ? double.infinity : null,
      height: height,
      child: type == ButtonType.outline
          ? OutlinedButton(
              onPressed: isLoading ? null : onPressed,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.border, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: _buildContent(colors),
            )
          : ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.background,
                foregroundColor: colors.foreground,
                disabledBackgroundColor:
                    colors.background.withValues(alpha: 0.6),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: _buildContent(colors),
            ),
    );

    return button;
  }

  Widget _buildContent(_ButtonColors colors) {
    if (isLoading) {
      return SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(colors.foreground),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: colors.foreground),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: TextStyle(
            color: colors.foreground,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  _ButtonColors _getColors() {
    switch (type) {
      case ButtonType.primary:
        return _ButtonColors(
          background: AppColors.primary,
          foreground: Colors.white,
          border: AppColors.primary,
        );
      case ButtonType.secondary:
        return _ButtonColors(
          background: AppColors.secondary,
          foreground: Colors.white,
          border: AppColors.secondary,
        );
      case ButtonType.outline:
        return _ButtonColors(
          background: Colors.transparent,
          foreground: AppColors.primary,
          border: AppColors.primary,
        );
      case ButtonType.danger:
        return _ButtonColors(
          background: AppColors.error,
          foreground: Colors.white,
          border: AppColors.error,
        );
    }
  }
}

class _ButtonColors {
  final Color background;
  final Color foreground;
  final Color border;

  _ButtonColors({
    required this.background,
    required this.foreground,
    required this.border,
  });
}
