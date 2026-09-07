import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Three-segment progress bar shared by the onboarding screens so the
/// customer always knows how much is left.
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({super.key, required this.step, this.total = 3});

  final int step; // 1-based
  final int total;

  @override
  Widget build(BuildContext context) {
    // The gradient is painted once across the whole bar and masked by the
    // filled segments, so progress reads as a single ramp rather than the
    // same two colours repeating in every segment.
    return SizedBox(
      height: 3,
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) =>
            AppColors.brandGradient.createShader(bounds),
        child: Row(
          children: List.generate(total, (i) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    // Opaque where filled so the shader shows through;
                    // the muted track elsewhere.
                    color: i < step ? Colors.white : AppColors.surfaceHigh,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
