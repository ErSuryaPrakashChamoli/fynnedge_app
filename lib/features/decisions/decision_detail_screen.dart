import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/decision.dart';
import 'decision_controller.dart';
import 'decision_history_screen.dart' show decisionStyle;

/// Why FynnEdge showed what it showed.
///
/// Everything here is what was true at the time. The heading says so, and
/// each figure carries where it came from — a rate a lender published, an
/// amount the customer typed, a payment FynnEdge worked out.
///
/// Where FynnEdge could not work something out it says so, rather than
/// leaving a gap. A customer reading an affordability explanation with
/// nothing about approval in it could reasonably conclude that FynnEdge had
/// checked; it has not, and it cannot.
class DecisionDetailScreen extends ConsumerWidget {
  const DecisionDetailScreen({super.key, required this.decisionId});

  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(decisionProvider(decisionId));

    return FynnScaffold(
      title: 'What we showed you',
      padHorizontal: false,
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: LoadingList(items: 3, itemHeight: 110),
        ),
        error: (e, _) => ErrorState(
          message: messageForLoad(e),
          onRetry: () => ref.invalidate(decisionProvider(decisionId)),
        ),
        data: (decision) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            _Header(decision: decision),

            for (final explanation in decision.explanation) ...[
              const SizedBox(height: 20),
              _ExplanationCard(explanation: explanation),
            ],

            if (decision.explanation.isEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'There is nothing more to explain about this one.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.decision});

  final Decision decision;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (icon, colour) = decisionStyle(decision.type);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: colour),
            const SizedBox(width: 10),
            Expanded(child: Text(decision.title, style: t.displaySmall)),
          ],
        ),
        const SizedBox(height: 8),
        Text(decision.description, style: t.bodyMedium),
        const SizedBox(height: 14),

        /*
         * Said once, plainly, at the top.
         *
         * Everything below is what was true when the customer looked, not
         * what FynnEdge is claiming now — and a screen that left that
         * implicit would be showing old figures as current ones.
         */
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
          decoration: BoxDecoration(
            color: (decision.isSimulated ? AppColors.violet : AppColors.blue)
                .withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: (decision.isSimulated ? AppColors.violet : AppColors.blue)
                  .withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                decision.isSimulated
                    ? Icons.science_rounded
                    : Icons.history_rounded,
                size: 16,
                color: decision.isSimulated ? AppColors.violet : AppColors.blue,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  decision.isSimulated
                      ? 'A simulation, as it was ${Fmt.relative(decision.occurredAt).toLowerCase()}. '
                            'Nothing was applied for.'
                      : 'As it was ${Fmt.relative(decision.occurredAt).toLowerCase()}. '
                            'Later changes do not change what you were shown.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (decision.reference != null) ...[
          const SizedBox(height: 12),
          Text(
            decision.reference!,
            style: const TextStyle(
              fontSize: 11.5,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  const _ExplanationCard({required this.explanation});

  final DecisionExplanation explanation;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: explanation.title),

        Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                explanation.rule,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.55,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),

              for (final factor in explanation.factors)
                _FactorRow(factor: factor),

              if (explanation.result != null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: AppColors.borderSoft),
                ),
                _FactorRow(factor: explanation.result!, emphasised: true),
              ],

              if (explanation.notAssessed.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (final note in explanation.notAssessed)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.remove_circle_outline_rounded,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          // What FynnEdge did not check. Present rather
                          // than omitted: an absent line reads as a pass.
                          'Not assessed: $note',
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FactorRow extends StatelessWidget {
  const _FactorRow({required this.factor, this.emphasised = false});

  final ExplanationFactor factor;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  factor.label,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: emphasised ? FontWeight.w700 : FontWeight.w600,
                    color: emphasised
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                factor.value,
                style: TextStyle(
                  fontSize: emphasised ? 15 : 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            // Where the number came from, on every number.
            factor.note == null
                ? factor.sourceLabel
                : '${factor.sourceLabel} · ${factor.note}',
            style: const TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
