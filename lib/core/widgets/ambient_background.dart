import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Soft off-screen colour blooms. This is what stops the dark canvas from
/// reading as "flat black app" and gives FynnEdge its depth.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    required this.child,
    this.primary = AppColors.mint,
    this.secondary = AppColors.blue,
    this.intensity = 1.0,
  });

  final Widget child;
  final Color primary;
  final Color secondary;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: AppColors.bg)),
        Positioned(
          top: -160,
          left: -120,
          child: _Bloom(color: primary, size: 380, opacity: 0.16 * intensity),
        ),
        Positioned(
          top: 60,
          right: -160,
          child: _Bloom(color: secondary, size: 420, opacity: 0.14 * intensity),
        ),
        Positioned(
          bottom: -200,
          left: 40,
          child: _Bloom(
            color: AppColors.violet,
            size: 360,
            opacity: 0.08 * intensity,
          ),
        ),
        child,
      ],
    );
  }
}

class _Bloom extends StatelessWidget {
  const _Bloom({
    required this.color,
    required this.size,
    required this.opacity,
  });

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              Colors.transparent,
            ],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}
