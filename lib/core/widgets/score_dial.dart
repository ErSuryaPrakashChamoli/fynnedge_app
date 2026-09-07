import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// The signature FynnEdge dial. Drives both FynnScore and FynnTrust so the
/// two concepts read as one family.
class ScoreDial extends StatelessWidget {
  const ScoreDial({
    super.key,
    required this.score,
    this.max = 100,
    this.size = 180,
    this.label,
    this.caption,
    this.strokeWidth = 12,
    this.animate = true,
  });

  final int score;
  final int max;
  final double size;
  final String? label;
  final String? caption;
  final double strokeWidth;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forScore((score / max * 100).round());
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score / max),
      duration: Duration(milliseconds: animate ? 1100 : 0),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(size),
                painter: _DialPainter(
                  progress: t,
                  color: color,
                  strokeWidth: strokeWidth,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(t * max).round()}',
                        style: TextStyle(
                          fontSize: size * 0.28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -2,
                          height: 1,
                          color: AppColors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        ' / $max',
                        style: TextStyle(
                          fontSize: size * 0.10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  if (label != null) ...[
                    SizedBox(height: size * 0.03),
                    Text(
                      label!,
                      style: TextStyle(
                        fontSize: size * 0.075,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: color,
                      ),
                    ),
                  ],
                  if (caption != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      caption!,
                      style: TextStyle(
                        fontSize: size * 0.062,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final double strokeWidth;

  static const double _start = math.pi * 0.75;
  static const double _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect =
        Offset(strokeWidth / 2, strokeWidth / 2) &
        Size(size.width - strokeWidth, size.height - strokeWidth);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = AppColors.surfaceHigh;
    canvas.drawArc(rect, _start, _sweep, false, track);

    if (progress <= 0) return;

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 6
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawArc(rect, _start, _sweep * progress, false, glow);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: _start,
        endAngle: _start + _sweep,
        colors: [color.withValues(alpha: 0.55), color],
        transform: GradientRotation(_start),
      ).createShader(rect);
    canvas.drawArc(rect, _start, _sweep * progress, false, arc);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.progress != progress || old.color != color;
}

/// Horizontal factor bar used in score breakdowns.
class FactorBar extends StatelessWidget {
  const FactorBar({
    super.key,
    required this.label,
    required this.value,
    this.max = 100,
    this.color,
    this.trailing,
  });

  final String label;
  final int value;
  final int max;
  final Color? color;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.forScore((value / max * 100).round());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                trailing ?? '$value',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: c,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (value / max).clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(height: 6, color: AppColors.surfaceHigh),
                  FractionallySizedBox(
                    widthFactor: t,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [c.withValues(alpha: 0.6), c],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
