import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/sample_data_notice.dart';
import '../../core/widgets/score_dial.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/score.dart';
import '../profile/profile_controller.dart';
import 'score_actions.dart';

/// Screen 17 — financial health, explained rather than just scored.
class FynnScoreScreen extends ConsumerWidget {
  const FynnScoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fynnScoreProvider);

    return FynnScaffold(
      title: 'FynnScore',
      padHorizontal: false,
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: LoadingList(items: 3, itemHeight: 120),
        ),
        error: (e, _) => ErrorState(
          message: messageFor(e),
          onRetry: () => ref.invalidate(fynnScoreProvider),
        ),
        data: (score) => score.hasScore
            ? _Body(score: score)
            : _InsufficientData(score: score),
      ),
    );
  }
}

/// Shown when the customer has not given us enough to calculate a score.
/// No number is invented, and the screen says exactly what is missing.
class _InsufficientData extends StatelessWidget {
  const _InsufficientData({required this.score});

  final FynnScore score;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: staggered([
        Center(
          child: Column(
            children: [
              Container(
                width: 150,
                height: 150,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border, width: 10),
                ),
                child: Text(
                  '—',
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textTertiary.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Not enough to score yet',
                style: t.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: 300,
                child: Text(
                  score.summary,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        if (score.missingRequirements.isNotEmpty) ...[
          const SectionHeader(title: 'What we still need'),
          FynnCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < score.missingRequirements.length; i++) ...[
                  if (i > 0) const HairLine(),
                  _MissingRow(field: score.missingRequirements[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        PrimaryButton(
          label: 'Complete my financial profile',
          icon: Icons.arrow_forward_rounded,
          onPressed: () => context.push(Routes.financialProfile),
        ),
        const SizedBox(height: 18),
        _Disclaimer(text: score.disclaimer),
      ], step: const Duration(milliseconds: 60)),
    );
  }
}

class _MissingRow extends StatelessWidget {
  const _MissingRow({required this.field});

  final String field;

  static const _labels = {
    'monthly_income': (
      'Monthly income',
      'Every ratio in your score is measured against it',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final entry = _labels[field] ?? (field, '');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          const Icon(
            Icons.radio_button_unchecked_rounded,
            size: 18,
            color: AppColors.warning,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.$1,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (entry.$2.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.$2,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.score});

  final FynnScore score;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: staggered([
        Center(
          child: Column(
            children: [
              ScoreDial(
                score: score.score!,
                size: 200,
                label: score.band!.label.toUpperCase(),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: 290,
                child: Text(
                  score.summary,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (score.inputsUpdatedAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Based on figures you last changed '
                  '${Fmt.relative(score.inputsUpdatedAt!)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        // What this number is, where the customer first meets it. The full
        // disclaimer stays at the foot; someone seeing "83 / 100" for the
        // first time should not have to scroll past five sections to learn
        // what it measures and what it is not.
        const _WhatThisIs(),
        const SizedBox(height: 22),
        const SampleDataNotice(
          margin: EdgeInsets.only(bottom: 24),
          message: SampleDataNotice.seededCustomerMessage,
        ),

        if (score.helping.isNotEmpty) ...[
          const SectionHeader(title: "What's helping"),
          _Checklist(
            items: score.helping,
            icon: Icons.check_rounded,
            color: AppColors.mint,
          ),
          const SizedBox(height: 22),
        ],

        if (score.needsAttention.isNotEmpty) ...[
          const SectionHeader(title: 'What needs attention'),
          _Checklist(
            items: score.needsAttention,
            icon: Icons.priority_high_rounded,
            color: AppColors.warning,
          ),
          const SizedBox(height: 22),
        ],

        const SectionHeader(
          title: 'The factors behind it',
          subtitle: 'Tap any factor to see what it means',
        ),
        FynnCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Column(
            children: [
              for (final d in score.dimensions) _ExpandableDimension(d),
            ],
          ),
        ),
        const SizedBox(height: 26),

        if (score.recommendations.isNotEmpty) ...[
          const SectionHeader(
            title: 'Improve next',
            subtitle: 'Ordered by how much they move the number',
          ),
          for (var i = 0; i < score.recommendations.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: _RecommendationCard(
                recommendation: score.recommendations[i],
                index: i + 1,
              ),
            ),
          const SizedBox(height: 10),
        ],

        SecondaryButton(
          label: 'Ask FynnAI how to improve this',
          icon: Icons.auto_awesome_rounded,
          onPressed: () => context.push(Routes.ai),
        ),
        const SizedBox(height: 16),
        _Disclaimer(text: score.disclaimer, version: score.modelVersion),
      ], step: const Duration(milliseconds: 55)),
    );
  }
}

/// FynnScore in two sentences, for someone who has never seen one.
class _WhatThisIs extends StatelessWidget {
  const _WhatThisIs();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What FynnScore is',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'Our own read of how comfortably your money is working, out of '
            '100. It looks at three things you told us: how much of your '
            'income goes to EMIs, how much goes to spending, and how many '
            'months your savings would cover.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 9),
          Text(
            'It is not a credit score, and no lender sees it or uses it.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer({required this.text, this.version});

  final String text;
  final String? version;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 11.5,
            height: 1.55,
            color: AppColors.textTertiary,
          ),
        ),
        if (version != null && version!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Scoring model $version',
            style: TextStyle(
              fontSize: 10.5,
              color: AppColors.textTertiary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist({
    required this.items,
    required this.icon,
    required this.color,
  });

  final List<String> items;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.13),
                  ),
                  child: Icon(icon, size: 13, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
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

class _ExpandableDimension extends StatefulWidget {
  const _ExpandableDimension(this.dimension);

  final ScoreDimension dimension;

  @override
  State<_ExpandableDimension> createState() => _ExpandableDimensionState();
}

class _ExpandableDimensionState extends State<_ExpandableDimension> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.dimension;

    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          // The customer's own figure alongside the sub-score. Without it
          // the row reads "EMI Burden — 100", which a first-time reader can
          // take to mean all of their income goes to EMIs, when 100 is in
          // fact full marks.
          FactorBar(
            label: '${d.name} · ${_metric(d)}',
            value: d.score,
            trailing: '${d.score}/100',
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 240),
            crossFadeState: _open
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.explanation,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.55,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // The anchors, so the customer can see what "good" is.
                  _AnchorRow(dimension: d),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// The dimension's own metric, in the customer's units.
String _metric(ScoreDimension d) => switch (d.metricUnit) {
  'percent_of_income' => '${Fmt.trimmed(d.metricValue)}% of income',
  'months_of_outgoings' => '${Fmt.monthsCovered(d.metricValue)} covered',
  _ => Fmt.trimmed(d.metricValue),
};

class _AnchorRow extends StatelessWidget {
  const _AnchorRow({required this.dimension});

  final ScoreDimension dimension;

  @override
  Widget build(BuildContext context) {
    final unit = dimension.metricUnit == 'percent_of_income' ? '%' : ' months';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.straighten_rounded,
            size: 13,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Now ${_trim(dimension.metricValue)}$unit · '
              '100 at ${_trim(dimension.fullMarksAt)}$unit · '
              '0 at ${_trim(dimension.zeroAt)}$unit',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.recommendation,
    required this.index,
  });

  final ScoreRecommendation recommendation;
  final int index;

  @override
  Widget build(BuildContext context) {
    final action = ScoreAction.forDimension(recommendation.dimension);

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceHigh,
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recommendation.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  recommendation.detail,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 7),
                // Reproducible, not an estimate: the score recalculated with
                // this one metric at its full-marks anchor.
                Text(
                  'Would take your score from '
                  '${recommendation.currentScore} to '
                  '${recommendation.projectedScore}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
                // Somewhere to actually do it, when FynnEdge has somewhere
                // worth sending them. No destination, no button.
                if (action != null) ...[
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => context.push(action.route),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.mint,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            action.label,
                            style: const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(Icons.arrow_forward_rounded, size: 14),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (recommendation.delta > 0) ...[
            const SizedBox(width: 10),
            Pill(label: '+${recommendation.delta}', color: AppColors.mint),
          ],
        ],
      ),
    );
  }
}
