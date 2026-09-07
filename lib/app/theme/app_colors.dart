import 'package:flutter/material.dart';

/// FynnEdge palette — a dark "financial cockpit" surface with a signature
/// aqua→electric-blue accent. Everything else in the app should pull from here.
class AppColors {
  const AppColors._();

  // Canvas
  static const Color bg = Color(0xFF05070D);
  static const Color bgElevated = Color(0xFF090E18);
  static const Color surface = Color(0xFF0E1422);
  static const Color surfaceAlt = Color(0xFF141B2D);
  static const Color surfaceHigh = Color(0xFF1B2337);

  // Lines
  static const Color border = Color(0xFF1E2740);
  static const Color borderSoft = Color(0xFF161D30);

  // Text
  static const Color textPrimary = Color(0xFFEDF2FB);
  static const Color textSecondary = Color(0xFF9AA8C4);

  /// Captions and supporting detail.
  ///
  /// Lifted from 0xFF5E6D8C, which read at 3.5:1 on the card surface and so
  /// missed WCAG AA for the 11–12.5px it is used at. The captions carrying
  /// it are the ones that explain a figure — "FynnEdge references 45%",
  /// "Target is 6 months" — so they are exactly the text that has to be
  /// legible. Same hue, 4.5:1 or better on every surface in the app.
  static const Color textTertiary = Color(0xFF6D7EA2);

  // Brand accents
  static const Color mint = Color(0xFF26E0B0);
  static const Color blue = Color(0xFF4C7DFF);
  static const Color violet = Color(0xFF9B7BFF);

  // Semantic
  static const Color success = Color(0xFF2FD69B);
  static const Color warning = Color(0xFFFFB84D);
  static const Color danger = Color(0xFFFF6B8A);
  static const Color info = Color(0xFF4C7DFF);

  // Gradients
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [mint, blue],
  );

  static const LinearGradient aiGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, blue],
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF121A2B), Color(0xFF0B1120)],
  );

  /// Colour ramp used by every score dial in the app (FynnScore, FynnTrust).
  static Color forScore(int score) {
    if (score >= 75) return mint;
    if (score >= 55) return blue;
    if (score >= 40) return warning;
    return danger;
  }
}
