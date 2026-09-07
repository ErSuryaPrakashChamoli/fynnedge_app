import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/session.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../data/models/intent.dart';
import 'onboarding_shell.dart';
import '../../app/routes.dart';

/// Screen 7 — what the borrowing or planning is actually for.
/// Rendered as a grid rather than a list so it reads differently from Intent.
class GoalScreen extends ConsumerStatefulWidget {
  const GoalScreen({super.key});

  @override
  ConsumerState<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends ConsumerState<GoalScreen> {
  GoalCategory? _selected;

  Future<void> _continue() async {
    final choice = _selected;
    if (choice == null) return;
    final notifier = ref.read(sessionProvider.notifier);
    await notifier.setGoal(choice);
    await notifier.completeOnboarding();
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        intensity: 0.9,
        primary: AppColors.violet,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 18),
                const OnboardingProgress(step: 3),
                const SizedBox(height: 34),
                Entrance(
                  child: Text(
                    'What are you\nplanning for?',
                    style: t.displayMedium?.copyWith(height: 1.12),
                  ),
                ),
                const SizedBox(height: 10),
                Entrance(
                  delay: const Duration(milliseconds: 90),
                  child: Text(
                    'We will keep this in view as you explore your options.',
                    style: t.bodyLarge,
                  ),
                ),
                const SizedBox(height: 26),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 11,
                    crossAxisSpacing: 11,
                    childAspectRatio: 1.32,
                    padding: const EdgeInsets.only(bottom: 8),
                    children: staggered(
                      [
                        for (final goal in GoalCategory.values)
                          _GoalCard(
                            goal: goal,
                            selected: _selected == goal,
                            onTap: () => setState(() => _selected = goal),
                          ),
                      ],
                      start: const Duration(milliseconds: 150),
                      step: const Duration(milliseconds: 45),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                PrimaryButton(
                  label: 'Continue',
                  onPressed: _selected == null ? null : _continue,
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.selected,
    required this.onTap,
  });

  final GoalCategory goal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.violet.withValues(alpha: 0.12)
              : AppColors.surface.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          border: Border.all(
            color: selected
                ? AppColors.violet.withValues(alpha: 0.7)
                : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.violet.withValues(alpha: 0.18),
                    blurRadius: 22,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(
              goal.icon,
              size: 24,
              color: selected ? AppColors.violet : AppColors.textSecondary,
            ),
            Text(
              goal.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.25,
                letterSpacing: -0.2,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
