import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/session.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../data/models/goal.dart';
import 'goal_editor_sheet.dart';
import 'goals_controller.dart';

/// Screen 26 — goals with real progress, not aspirational fluff.
///
/// The screen renders GoalsState and opens the editor; it owns no business
/// state and never touches a repository or HTTP.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(goalsControllerProvider);
    final controller = ref.read(goalsControllerProvider.notifier);

    return FynnScaffold(
      title: 'My Financial Goals',
      subtitle: state.goals.isEmpty
          ? null
          : '${state.goals.length} in progress',
      padHorizontal: false,
      bottomBar: state.loadError != null && state.goals.isEmpty
          ? null
          : PrimaryButton(
              label: 'Add a goal',
              icon: Icons.add_rounded,
              onPressed: state.busy
                  ? null
                  : () => GoalEditorSheet.show(context),
            ),
      child: _Body(state: state, controller: controller),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.controller});

  final GoalsState state;
  final GoalsController controller;

  /// Starts the product search from this goal.
  ///
  /// It seeds Loan Discovery with what is still needed and the category the
  /// goal belongs to — the customer then answers the same questions as
  /// always and can change either. Nothing is matched here; FynnMatch is
  /// still the only thing that decides what fits.
  void _explore(BuildContext context, WidgetRef ref, Goal goal) {
    ref
        .read(loanRequestProvider.notifier)
        .update(
          amount: goal.remainingAmount,
          purpose: goal.category.exploreCategory.id,
        );
    context.push(Routes.loanDiscovery);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading && state.goals.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: LoadingList(items: 3, itemHeight: 150),
      );
    }

    if (state.loadError != null && state.goals.isEmpty) {
      return ErrorState(
        message: messageFor(state.loadError!),
        onRetry: controller.load,
      );
    }

    if (state.isEmpty) {
      return EmptyState(
        icon: Icons.flag_outlined,
        title: 'No goals yet',
        message:
            'A goal turns a vague intention into a monthly number. Add '
            'one and we will tell you what it takes.',
        actionLabel: 'Add your first goal',
        onAction: () => GoalEditorSheet.show(context),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      itemCount: state.goals.length + (state.actionError == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 13),
      itemBuilder: (context, i) {
        if (state.actionError != null && i == 0) {
          return _ActionBanner(message: state.actionError!);
        }
        final goal = state.goals[state.actionError == null ? i : i - 1];
        return Entrance(
          delay: Duration(milliseconds: 60 * i),
          child: _GoalCard(
            goal: goal,
            onTap: () => GoalEditorSheet.show(context, existing: goal),
            onExplore: () => _explore(context, ref, goal),
          ),
        );
      },
    );
  }
}

class _ActionBanner extends StatelessWidget {
  const _ActionBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 16,
            color: AppColors.danger,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({
    required this.goal,
    required this.onTap,
    required this.onExplore,
  });

  final Goal goal;
  final VoidCallback onTap;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onTrack = goal.monthsRemaining > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(17, 16, 17, 17),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.violet.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    goal.category.icon,
                    size: 19,
                    color: AppColors.violet,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.title,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Target ${Fmt.date(goal.targetDate)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(goal.progress * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.violet,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: goal.progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: t,
                  minHeight: 7,
                  backgroundColor: AppColors.surfaceHigh,
                  valueColor: const AlwaysStoppedAnimation(AppColors.violet),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  Fmt.compactMoney(goal.savedAmount),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Text(
                  '  saved of  ',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textTertiary,
                  ),
                ),
                Text(
                  Fmt.compactMoney(goal.targetAmount),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(AppTheme.rSm),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.trending_up_rounded,
                    size: 15,
                    color: AppColors.mint,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      onTrack
                          ? 'Set aside ${Fmt.money(goal.monthlyRequired)} a '
                                'month for ${goal.monthsRemaining} months to get '
                                'there.'
                          : 'The target date has passed. Adjust the date or the '
                                'amount.',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (goal.remainingAmount > 0) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onExplore,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.mint,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Explore options for this goal',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 5),
                      Icon(Icons.arrow_forward_rounded, size: 14),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
