import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_logo.dart';
import '../../app/routes.dart';

/// Screen 2 — the product promise, before any form.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _pillars = [
    (
      Icons.visibility_outlined,
      'See the real cost',
      'Not just the headline rate',
    ),
    (Icons.balance_rounded, 'Compare honestly', 'Ranked by what suits you'),
    (Icons.shield_outlined, 'Decide with confidence', 'No pressure to borrow'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        intensity: 1.15,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 18),
                Entrance(
                  child: Row(
                    children: [
                      const FynnMark(size: 38),
                      const SizedBox(width: 12),
                      const FynnWordmark(fontSize: 21),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
                Entrance(
                  delay: const Duration(milliseconds: 120),
                  child: Text(
                    'Your money\ndeserves better\ndecisions.',
                    style: t.displayLarge?.copyWith(height: 1.08),
                  ),
                ),
                const SizedBox(height: 18),
                Entrance(
                  delay: const Duration(milliseconds: 240),
                  child: SizedBox(
                    width: 320,
                    child: Text(
                      'Understand your options, compare smarter and make '
                      'financial decisions with confidence.',
                      style: t.bodyLarge?.copyWith(height: 1.55),
                    ),
                  ),
                ),
                const Spacer(),
                ...staggered([
                  for (final (icon, title, sub) in _pillars)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: AppColors.mint.withValues(alpha: 0.10),
                              border: Border.all(
                                color: AppColors.mint.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Icon(icon, size: 18, color: AppColors.mint),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: t.titleMedium),
                              const SizedBox(height: 1),
                              Text(sub, style: t.bodySmall),
                            ],
                          ),
                        ],
                      ),
                    ),
                ], start: const Duration(milliseconds: 360)),
                const Spacer(),
                Entrance(
                  delay: const Duration(milliseconds: 620),
                  child: PrimaryButton(
                    label: 'Get Started',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () => context.push(Routes.login),
                  ),
                ),
                const SizedBox(height: 6),
                Entrance(
                  delay: const Duration(milliseconds: 700),
                  child: Center(
                    child: GhostButton(
                      label: 'I already have an account',
                      color: AppColors.textSecondary,
                      onPressed: () => context.push(Routes.login),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
