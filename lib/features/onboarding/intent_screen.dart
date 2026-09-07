import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/session.dart';
import '../../app/theme/app_colors.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/selectable_tile.dart';
import '../../data/models/intent.dart';
import 'onboarding_shell.dart';
import '../../app/routes.dart';

/// Screen 6 — the answer that shapes the rest of the app.
class IntentScreen extends ConsumerStatefulWidget {
  const IntentScreen({super.key});

  @override
  ConsumerState<IntentScreen> createState() => _IntentScreenState();
}

class _IntentScreenState extends ConsumerState<IntentScreen> {
  IntentOption? _selected;

  Future<void> _continue() async {
    final choice = _selected;
    if (choice == null) return;
    await ref.read(sessionProvider.notifier).setIntent(choice);
    if (!mounted) return;

    // "Just exploring" does not need a goal — send them straight in.
    if (choice == IntentOption.exploring) {
      await ref.read(sessionProvider.notifier).completeOnboarding();
      if (mounted) context.go(Routes.home);
    } else {
      context.push(Routes.onboardingGoal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        intensity: 0.9,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 18),
                const OnboardingProgress(step: 2),
                const SizedBox(height: 34),
                Entrance(
                  child: Text(
                    'What brings you\nto FynnEdge?',
                    style: t.displayMedium?.copyWith(height: 1.12),
                  ),
                ),
                const SizedBox(height: 10),
                Entrance(
                  delay: const Duration(milliseconds: 90),
                  child: Text(
                    'Pick the one that fits best. You can change this later.',
                    style: t.bodyLarge,
                  ),
                ),
                const SizedBox(height: 26),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: staggered(
                      [
                        for (final option in IntentOption.values)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SelectableTile(
                              label: option.label,
                              description: option.description,
                              icon: option.icon,
                              selected: _selected == option,
                              onTap: () => setState(() => _selected = option),
                            ),
                          ),
                      ],
                      start: const Duration(milliseconds: 150),
                      step: const Duration(milliseconds: 55),
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
