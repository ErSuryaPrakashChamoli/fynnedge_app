import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/decision.dart';
import '../../data/models/goal.dart';
import '../../data/models/intelligence.dart';
import '../decisions/decision_controller.dart';
import '../intelligence/intelligence_controller.dart';

/// The customer's financial review.
///
/// It happens because they asked for it. Nothing here runs on a schedule,
/// nothing is written when the screen opens, and no review is recorded — so
/// there is no "last reviewed" date to show and the screen does not pretend
/// to one.
///
/// Everything on it already existed. The position is Module 34's, the score
/// is FynnScoreEngine's, the goals are the Goals module's own metrics, the
/// changes are Module 35's observations and the next step is Module 33's
/// ladder — all from **one** read of one customer, so no two sections here
/// can describe them at two different instants.
///
/// What it adds is the gathering. It computes nothing, decides nothing, and
/// grades nothing: there is no review score, no completeness percentage and
/// no overall verdict, because FynnScore already has bands and a second
/// opinion about somebody's finances is exactly what this must not be.
///
/// Sections with nothing to say are absent rather than filled.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(intelligenceProvider);

    return FynnScaffold(
      title: 'Your financial review',
      subtitle: 'What FynnEdge knows right now.',
      padHorizontal: false,
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: LoadingList(items: 4, itemHeight: 96),
        ),
        error: (e, _) => ErrorState(
          message: messageForLoad(e),
          onRetry: () => ref.invalidate(intelligenceProvider),
        ),
        data: (data) => _Review(data: data),
      ),
    );
  }
}

class _Review extends ConsumerWidget {
  const _Review({required this.data});

  final FinancialIntelligence data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    /*
     * The decisions come from their own request, and deliberately.
     *
     * Everything above describes the customer's state now, so it has to
     * come from one read — a goal edited between two requests would let the
     * goal section contradict the next step beside it. A recorded decision
     * cannot contradict a figure: it is an immutable fact with its own
     * timestamp, and a second read can only ever find more of them.
     */
    final decisions = ref.watch(decisionHistoryProvider).value ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
      children: [
        _Position(position: data.position),

        if (data.score.hasScore || data.score.missing.isNotEmpty) ...[
          const SizedBox(height: 22),
          _Score(score: data.score),
        ],

        if (data.goals.isNotEmpty) ...[
          const SizedBox(height: 22),
          _Goals(goals: data.goals, total: data.goalCount),
        ],

        if (data.progress.isNotEmpty) ...[
          const SizedBox(height: 22),
          _WhatChanged(changes: data.progress),
        ],

        if (decisions.isNotEmpty) ...[
          const SizedBox(height: 22),
          _Decisions(decisions: decisions),
        ],

        if (data.nextAction != null) ...[
          const SizedBox(height: 22),
          _NextStep(
            action: data.nextAction!,
            // The buffer rung's reason IS the buffer sentence, so on a
            // screen that already carries the position it would print
            // twice. The plan had the same fault for the same reason.
            alreadySaid: {
              data.position.statement,
              if (data.position.emergencyStatement != null)
                data.position.emergencyStatement!,
            },
          ),
        ],

        const SizedBox(height: 20),
        const _Footnote(),
      ],
    );
  }
}

/// Where the customer stands, in the server's own sentences.
class _Position extends StatelessWidget {
  const _Position({required this.position});

  final FinancialPosition position;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Financial position',
      route: Routes.financialProfile,
      actionLabel: 'Your figures',
      child: position.isMeasurable
          ? Column(
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
                const SizedBox(height: 4),
                DetailRow(
                  label: 'Monthly surplus',
                  value: Fmt.money(position.surplus),
                  emphasise: true,
                  // Colour is decoration: the sentence above and the sign on
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
                    padding: const EdgeInsets.only(top: 11),
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
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Missing(
                  // Said plainly, and no ₹0 anywhere. A customer who entered
                  // nothing has not recorded a surplus of zero.
                  headline: 'Your financial position cannot be worked out yet',
                  detail: position.statement,
                ),
                /*
                 * What is known, even when the position is not.
                 *
                 * How many months the recorded savings cover the recorded
                 * outgo is a division of two figures the customer entered
                 * and never needed an income. Withholding a true answer
                 * because a different one is missing would be the review
                 * knowing something and not saying it.
                 */
                if (position.emergencyStatement != null) ...[
                  const SizedBox(height: 11),
                  const HairLine(),
                  const SizedBox(height: 11),
                  Text(
                    position.emergencyStatement!,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.score});

  final ScoreSummary score;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'FynnScore',
      route: Routes.fynnScore,
      // There is nothing to break down until there is a score, and a link
      // that promised one would be the screen overstating itself.
      actionLabel: score.hasScore ? 'See the breakdown' : 'About FynnScore',
      child: score.hasScore
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${score.score}',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        height: 1,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '/ 100',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // The band as a word, not as a colour.
                    Text(
                      score.bandLabel ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  score.summary,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            )
          : _Missing(
              headline: 'No FynnScore yet',
              detail: score.summary,
            ),
    );
  }
}

class _Goals extends StatelessWidget {
  const _Goals({required this.goals, required this.total});

  final List<Goal> goals;
  final int total;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Goals',
      // Counted, never ranked. FynnEdge was never told which goal matters
      // most, and the ordering is the Goals module's own: nearest first.
      subtitle: total == 1
          ? 'One goal, and where it stands.'
          : '$total goals, nearest target date first.',
      route: Routes.goals,
      actionLabel: 'All goals',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < goals.length; i++) ...[
            if (i > 0) const HairLine(),
            _GoalLine(goal: goals[i]),
          ],
        ],
      ),
    );
  }
}

class _GoalLine extends StatelessWidget {
  const _GoalLine({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    /*
     * Three states, none of them a prediction.
     *
     * The monthly figure is what the arithmetic gives at the target and
     * date the customer chose, and it changes the moment they change
     * either. FynnEdge holds no savings commitment, so it may not describe
     * one — and it cannot say whether anybody will get there.
     */
    final note = goal.isComplete
        ? 'Goal reached.'
        : goal.isOverdue
        ? 'The target date has passed. Review the date or the amount.'
        : 'At the current target and date, the calculated monthly amount is '
              '${Fmt.money(goal.monthlyRequired)}.';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  goal.title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(goal.progress * 100).round()}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.violet,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${Fmt.money(goal.savedAmount)} saved toward '
            '${Fmt.money(goal.targetAmount)}',
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            note,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// What FynnEdge observed changing, from Module 35 and nowhere else.
class _WhatChanged extends StatelessWidget {
  const _WhatChanged({required this.changes});

  final List<ObservedChange> changes;

  /// Enough to be a review, few enough not to become the progress screen.
  static const int shown = 3;

  @override
  Widget build(BuildContext context) {
    final visible = changes.take(shown).toList();

    return _Section(
      title: 'What changed',
      subtitle: 'Figures FynnEdge recorded twice, with what each was.',
      route: Routes.financialTimeline,
      actionLabel: 'Your story',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(height: 7),
            Semantics(
              label: visible[i].spokenSummary,
              excludeSemantics: true,
              child: Text(
                // The server's sentence, so a figure quoted here and the
                // same figure on the progress screen cannot differ.
                visible[i].summary,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What the customer actually explored, from Module 32.
class _Decisions extends StatelessWidget {
  const _Decisions({required this.decisions});

  final List<Decision> decisions;

  static const int shown = 2;

  @override
  Widget build(BuildContext context) {
    final visible = decisions.take(shown).toList();

    return _Section(
      title: 'What you explored',
      subtitle: 'Things you asked FynnEdge to work out.',
      route: Routes.decisions,
      actionLabel: 'All of them',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(height: 7),
            // What they did, and when. Never what they wanted: "you were
            // considering this" is an inference about somebody's mind.
            Text(
              '${visible[i].title} · ${Fmt.relative(visible[i].occurredAt)}',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The one step, from the one ladder.
///
/// The same action Home shows and the plan begins with. There is no review
/// ladder: a second opinion about what to do next is how a product ends up
/// telling somebody two different things on two screens.
class _NextStep extends StatelessWidget {
  const _NextStep({required this.action, this.alreadySaid = const {}});

  final NextAction action;

  /// Sentences this review has already made. A reason repeated a few
  /// centimetres below itself reads as a rendering fault, not as emphasis.
  final Set<String> alreadySaid;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Next step',
      route: action.actionRoute,
      actionLabel: action.actionLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            action.title,
            style: const TextStyle(
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (!alreadySaid.contains(action.reason)) ...[
            const SizedBox(height: 4),
            Text(
              action.reason,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Said once, at the bottom, and not as a nudge.
///
/// No schedule, no due date and no reminder: FynnEdge records no review, so
/// it has no honest way to say when the last one was — and a product that
/// invented one would be teaching a habit rather than answering a question.
class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'This review is what FynnEdge knows right now. Come back whenever your '
      'circumstances change.',
      style: TextStyle(
        fontSize: 11.5,
        height: 1.5,
        color: AppColors.textTertiary,
      ),
    );
  }
}

/// A section that says what is missing instead of showing a figure.
class _Missing extends StatelessWidget {
  const _Missing({required this.headline, required this.detail});

  final String headline;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headline,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          detail,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// One titled block with a link to the screen that owns the subject.
///
/// Every destination already exists. The review gathers; it does not become
/// a second place to read any of this in full.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.route,
    required this.actionLabel,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String route;
  final String actionLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          subtitle: subtitle,
          actionLabel: actionLabel,
          onAction: () => context.push(route),
        ),
        FynnCard(child: child),
      ],
    );
  }
}
