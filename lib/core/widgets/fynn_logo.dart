import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// The FynnEdge mark: an ascending edge inside a rounded aperture.
/// Drawn rather than shipped as an asset so it scales and tints cleanly.
class FynnMark extends StatelessWidget {
  const FynnMark({super.key, this.size = 64, this.progress = 1});

  final double size;

  /// 0..1 — used by the splash to draw the mark on.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter(progress)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Rect.fromLTWH(0, 0, s, s);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.30));

    // Aperture
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16324A), Color(0xFF0B1424)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.mint.withValues(alpha: 0.35),
    );

    // Ascending edge — three rising strokes.
    final bars = [
      Rect.fromLTWH(s * 0.24, s * 0.56, s * 0.11, s * 0.20),
      Rect.fromLTWH(s * 0.445, s * 0.42, s * 0.11, s * 0.34),
      Rect.fromLTWH(s * 0.65, s * 0.24, s * 0.11, s * 0.52),
    ];
    for (var i = 0; i < bars.length; i++) {
      final t = ((progress - i * 0.18) / 0.55).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final b = bars[i];
      final grown = Rect.fromLTWH(
        b.left,
        b.bottom - b.height * t,
        b.width,
        b.height * t,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(grown, Radius.circular(s * 0.055)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [AppColors.blue.withValues(alpha: 0.9), AppColors.mint],
          ).createShader(b),
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.progress != progress;
}

/// "FynnEdge" wordmark with the brand gradient on "Edge".
class FynnWordmark extends StatelessWidget {
  const FynnWordmark({super.key, this.fontSize = 34});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Manrope',
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.4,
      height: 1,
      color: AppColors.textPrimary,
    );

    // ShaderMask is bounded by its own child, so the gradient runs across
    // "Edge" alone. A shader on a TextSpan would be measured from the start
    // of the whole wordmark and clamp to its end colour.
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('Fynn', style: style),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) =>
              AppColors.brandGradient.createShader(bounds),
          child: Text('Edge', style: style),
        ),
      ],
    );
  }
}
