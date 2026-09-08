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
import '../../core/widgets/surfaces.dart';
import '../../data/models/goal.dart';
import '../../data/models/intelligence.dart';
import '../intelligence/intelligence_controller.dart';
import 'goal_editor_sheet.dart';
import 'goals_controller.dart';

/// Screen 26 — the customer's financial plan.
///
/// Three things, in the order a plan is actually read: where the figures
/// currently stand, what the customer is working toward, and one step they
/// could take next.
///
/// None of it is computed here. The position and its sentences come from
/// App\Domain\Financial\FinancialPosition, the goal figures from
/// FinancialEngine by way of each goal's `derived` block, and the next step
/// from the one action ladder Home reads as well. This screen renders three
/// answers to the same read of the same customer; it produces none of them,
/// which is why the plan and Home cannot suggest different things.
///
/// Nothing here predicts. There is no "on track", no projected completion
/// and no month by which anything will happen — only what was recorded,
/// what it works out to, and what the customer may choose to change.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(goalsControllerProvider);
    final controller = ref.read(goalsControllerProvider.notifier);

    return FynnScaffold(
      title: 'Your financial plan',
      /*
       * Counted, not labelled.
       *
       * FinancialGoal.status stays 'active' for a goal whose two amounts
       * have already met — completion is derived, not a status — so calling
       * every goal on this screen active would describe a reached one
       * wrongly using a word the customer reads differently from the
       * column.
       */
      subtitle: state.goals.isEmpty
          ? null
          : '${state.goals.length} ${state.goals.length == 1 ? 'goal' : 'goals'}',
      padHorizontal: false,
      bottomBar: state.loadError != null && state.goals.isEmpty
          ? null
          : PrimaryButton(
              label: 'Add a goal',
              icon: Icons.add_rounded,
              onPressed: state.busy ? null : () => GoalEditorSheet.show(context),
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

    final intelligence = ref.watch(intelligenceProvider);
    final position = intelligence.value?.position;

    /*
     * The borrowing shortcut, and when it is withheld.
     *
     * Never to somebody whose recorded outgo already exceeds their recorded
     * income: pointing a customer who cannot cover their current life at
     * loan discovery is the sales bias this product must not have, and the
     * action ladder refuses it for the same reason.
     *
     * Withheld too when the position has not loaded, which is the same
     * moment the card above says so and offers a retry. FynnEdge does not
     * know the surplus is safe, so it does not act as though it does.
     */
    final canExplore = position != null &&
        position.surplusState != SurplusState.negative;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      children: staggered([
        if (state.actionError != null) ...[
          _ActionBanner(message: state.actionError!),
          const SizedBox(height: 14),
        ],

        _PositionSection(
          intelligence: intelligence,
          onRetry: () => ref.invalidate(intelligenceProvider),
        ),

        const SizedBox(height: 22),

        if (state.isEmpty)
          const _NoGoalsYet()
        else ...[
          SectionHeader(
            title: 'What you are working toward',
            subtitle: state.goals.length == 1
                ? 'One goal.'
                : 'Nearest target date first.',
          ),
          for (final goal in state.goals) ...[
            _GoalCard(
              goal: goal,
              onTap: () => GoalEditorSheet.show(context, existing: goal),
              onExplore: canExplore ? () => _explore(context, ref, goal) : null,
            ),
            const SizedBox(height: 13),
          ],
        ],
      ], step: const Duration(milliseconds: 55)),
    );
  }
}

/// Where the customer stands, in the server's words.
///
/// Rendered from FinancialPosition and nothing else. When it cannot be
/// loaded the card says so and offers a retry rather than falling back to
/// figures from an earlier read — a stale surplus presented as the current
/// one is worse than no surplus at all.
class _PositionSection extends StatelessWidget {
  const _PositionSection({required this.intelligence, required this.onRetry});

  final AsyncValue<FinancialIntelligence> intelligence;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return intelligence.when(
      loading: () => const _PositionSkeleton(),
      error: (_, _) => _PositionUnavailable(onRetry: onRetry),
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Where you stand',
            subtitle: 'What FynnEdge has recorded, and what it works out to.',
          ),
          _PositionCard(position: data.position),
          if (data.nextAction != null) ...[
            const SizedBox(height: 13),
            _NextStepCard(
              action: data.nextAction!,
              // The buffer rung's reason IS the buffer sentence, so on this
              // screen it would print twice, one card under the other.
              alreadySaid: {
                data.position.statement,
                if (data.position.emergencyStatement != null)
                  data.position.emergencyStatement!,
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _PositionSkeleton extends StatelessWidget {
  const _PositionSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeader(title: 'Where you stand'),
      SkeletonBox(height: 132, radius: AppTheme.rLg),
    ],
  );
}

class _PositionUnavailable extends StatelessWidget {
  const _PositionUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Where you stand'),
        FynnCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your current position could not be loaded.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Your goals below are still what FynnEdge last saved. Nothing '
                'about your income or surplus is shown until it can be read '
                'again.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.mint,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Try again',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.position});

  final FinancialPosition position;

  @override
  Widget build(BuildContext context) {
    if (!position.isMeasurable) {
      return FynnCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              position.statement,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add your monthly figures and the rest of this plan fills in '
              'from them.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return FynnCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            position.statement,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          DetailRow(
            label: 'Monthly surplus',
            hint: 'Recorded income less recorded monthly outgo',
            value: Fmt.money(position.surplus),
            emphasise: true,
            // Colour is decoration here: the sentence above and the sign on
            // the figure both say which way it goes.
            valueColor: position.surplusState == SurplusState.negative
                ? AppColors.danger
                : AppColors.textPrimary,
          ),
          const HairLine(),
          DetailRow(
            label: 'Monthly outgo',
            value: Fmt.money(position.monthlyOutgo),
          ),
          if (position.emergencyStatement != null) ...[
            const HairLine(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    position.emergencyBelowReference
                        ? Icons.shield_outlined
                        : Icons.shield_rounded,
                    size: 15,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      position.emergencyStatement!,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One step, from the same ladder Home reads.
///
/// The plan does not rank anything of its own. If this card and Home's
/// primary action ever disagreed it would be because they had asked at two
/// different instants, not because two engines had two opinions.
class _NextStepCard extends StatelessWidget {
  const _NextStepCard({required this.action, this.alreadySaid = const {}});

  final NextAction action;

  /// Sentences the card above has already made. A reason repeated directly
  /// beneath itself reads as a rendering fault, not as emphasis.
  final Set<String> alreadySaid;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Next step. ${action.title}. ${action.reason}',
      child: FynnCard(
        onTap: () => context.push(action.actionRoute),
        padding: const EdgeInsets.fromLTRB(17, 15, 15, 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NEXT STEP',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppColors.mint,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    action.title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (!alreadySaid.contains(action.reason)) ...[
                    const SizedBox(height: 4),
                    Text(
                      action.reason,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoGoalsYet extends StatelessWidget {
  const _NoGoalsYet();

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No goals yet',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'A goal turns a vague intention into a monthly number. Add one '
            'and FynnEdge will work out what it comes to at the target and '
            'date you choose.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => GoalEditorSheet.show(context),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.mint,
                padding: const EdgeInsets.symmetric(vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Add your first goal',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
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

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.onTap,
    required this.onExplore,
  });

  final Goal goal;
  final VoidCallback onTap;

  /// Null when FynnEdge will not point this customer at borrowing.
  final VoidCallback? onExplore;

  @override
  Widget build(BuildContext context) {
    final percent = (goal.progress * 100).round();

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
                  '$percent%',
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
            // The bar is decoration; the percentage above and the amounts
            // below carry the same fact in text.
            Semantics(
              label: '$percent per cent of this goal saved',
              child: TweenAnimationBuilder<double>(
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
            ),
            const SizedBox(height: 12),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
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
            _GoalNote(goal: goal),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.violet,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Update what you have saved',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 5),
                    Icon(Icons.edit_outlined, size: 14),
                  ],
                ),
              ),
            ),
            if (onExplore != null && !goal.isComplete) ...[
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

/// The one line of derived text on a goal card.
///
/// Three states, and none of them predicts anything:
///
///   reached   the two amounts meet, which the server decided
///   past date the date has gone by; the customer chooses what to change
///   otherwise what the monthly amount comes to at the target and date they
///             set — a calculated reference, not a commitment
///
/// FynnEdge has no savings commitment to hold a customer to. Nothing was
/// promised, nothing is owed, and the wording says so: the figure is what
/// the arithmetic gives, and it changes the moment they change either input.
class _GoalNote extends StatelessWidget {
  const _GoalNote({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (goal) {
      _ when goal.isComplete => (
        Icons.check_circle_outline_rounded,
        'Goal reached. You have saved ${Fmt.money(goal.targetAmount)} '
            'toward this goal.',
      ),
      _ when goal.isOverdue => (
        Icons.event_busy_outlined,
        'The target date has passed. Review the date or the amount.',
      ),
      _ => (
        Icons.calculate_outlined,
        'At your current target and date, the calculated monthly amount is '
            '${Fmt.money(goal.monthlyRequired)} over '
            '${goal.monthsRemaining} months.',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.mint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
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
