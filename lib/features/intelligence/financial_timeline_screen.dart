import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../data/models/intelligence.dart';
import 'intelligence_controller.dart';

/// The customer's financial story: what changed, and what happened.
///
/// Two halves, and the difference between them is the point. Progress is
/// what FynnEdge observed *changing* — a figure it wrote down twice, with
/// different values. The story beneath it is what *happened*: goals set,
/// applications started, a score becoming available.
///
/// Not the audit log. Nothing here is a webhook, a retry, a storage
/// operation, a consent record or an authentication event — those are how
/// FynnEdge works, not what happened to somebody's money.
///
/// Nothing here is derived on this screen, and nothing compares a stored
/// figure with a live one. Both halves come from the server having actually
/// recorded something, and both are empty for a customer FynnEdge has not
/// yet observed twice — which the screen says, rather than drawing a chart
/// through one point.
class FinancialTimelineScreen extends ConsumerWidget {
  const FinancialTimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(financialTimelineProvider);

    return FynnScaffold(
      title: 'Your financial story',
      padHorizontal: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          const _Progress(),
          const SizedBox(height: 26),
          const SectionHeader(
            title: 'What happened',
            subtitle: 'The things FynnEdge recorded as they happened.',
          ),
          ...async.when(
            loading: () => const [LoadingList(items: 4, itemHeight: 72)],
            error: (e, _) => [
              ErrorState(
                message: messageForLoad(e),
                onRetry: () => ref.invalidate(financialTimelineProvider),
              ),
            ],
            data: (moments) => moments.isEmpty
                ? const [_NothingHappenedYet()]
                : [
                    for (var i = 0; i < moments.length; i++)
                      Entrance(
                        delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_monthOf(moments[i]) !=
                                _monthOf(i == 0 ? null : moments[i - 1]))
                              _MonthHeading(label: _monthOf(moments[i])),
                            _MomentTile(
                              moment: moments[i],
                              isLast: i == moments.length - 1,
                            ),
                          ],
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }

  String _monthOf(FinancialMoment? moment) {
    if (moment == null) return '';

    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    return '${months[moment.occurredAt.month - 1]} ${moment.occurredAt.year}';
  }
}

class _MonthHeading extends StatelessWidget {
  const _MonthHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _MomentTile extends StatelessWidget {
  const _MomentTile({required this.moment, required this.isLast});

  final FinancialMoment moment;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colour = moment.isMajor ? AppColors.mint : AppColors.blue;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The spine. Drawn rather than decorated: it is what makes a list
          // read as a sequence.
          Column(
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colour.withValues(alpha: moment.isMajor ? 1 : 0.5),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.borderSoft,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    moment.title,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    moment.description,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        Fmt.relative(moment.occurredAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      if (moment.contextReference != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(AppTheme.rSm),
                            ),
                            child: Text(
                              moment.contextReference!,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                letterSpacing: 0.3,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What FynnEdge has actually observed changing.
///
/// Every row names two figures it wrote down at two moments. There is no
/// chart, and that is deliberate rather than unfinished: a line needs points
/// between the ones that exist, and inventing them would turn a record of
/// what happened into a picture of what might have.
///
/// Silent when there is nothing to say. One observation is a baseline, not a
/// trend, and the empty state says which of the two the customer has.
class _Progress extends ConsumerWidget {
  const _Progress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(intelligenceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'What changed',
          subtitle: 'Figures FynnEdge recorded twice, with what each was.',
        ),
        async.when(
          loading: () => const LoadingList(items: 2, itemHeight: 74),
          error: (e, _) => ErrorState(
            message: messageForLoad(e),
            onRetry: () => ref.invalidate(intelligenceProvider),
          ),
          data: (data) => data.progress.isEmpty
              ? _NoChangesYet(observations: data.observations)
              : Column(
                  // Full width, whatever each row happens to contain. A
                  // Column sizes to its widest child otherwise, and a score
                  // change carrying a component line made the two rows
                  // beneath it narrower than itself.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < data.progress.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Entrance(
                          delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
                          child: _ChangeCard(change: data.progress[i]),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// The honest empty state, and it says which kind of empty.
///
/// "Nothing has changed" and "FynnEdge has not looked twice yet" are
/// different facts, and a customer who has just arrived deserves the second
/// rather than being told nothing about their money has moved.
class _NoChangesYet extends StatelessWidget {
  const _NoChangesYet({required this.observations});

  final int observations;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            observations < 2
                ? 'Nothing to compare yet'
                : 'No changes recorded',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            observations < 2
                ? 'FynnEdge writes down your figures when you change them. '
                      'Once it has written them down twice, what moved '
                      'between the two appears here.'
                : 'The figures FynnEdge has recorded have not moved.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NothingHappenedYet extends StatelessWidget {
  const _NothingHappenedYet();

  @override
  Widget build(BuildContext context) {
    return const FynnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nothing to show yet',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 6),
          // What will land here, and nothing promised beyond it.
          Text(
            'As you set goals, look at options and make decisions, the '
            'things that matter will appear here.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One observed change: what it was, what it became, and when.
///
/// The arrow is decoration. Both figures are text, the label names what they
/// are, and the whole row is announced as a sentence with the direction in
/// words — an arrow is legible on a screen and silent when read aloud.
///
/// Nothing is coloured by direction. Recorded monthly outgo going up is not
/// bad news and going down is not good news; which it is depends on the
/// customer's life, and FynnEdge is not entitled to an opinion.
class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.change});

  final ObservedChange change;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${change.spokenSummary} Recorded '
          '${Fmt.relative(change.observedAt)}.',
      excludeSemantics: true,
      child: FynnCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              change.label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 9,
              runSpacing: 4,
              children: [
                Text(
                  change.previousDisplay,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: AppColors.textTertiary,
                ),
                Text(
                  change.currentDisplay,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (change.bandChanged) ...[
              const SizedBox(height: 8),
              Text(
                'Band changed from ${_band(change.previousBand!)} to '
                '${_band(change.band!)}.',
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
            if (change.components.isNotEmpty) ...[
              const SizedBox(height: 10),
              const HairLine(),
              const SizedBox(height: 8),
              // What each component was worth when each score was
              // calculated. A statement about two moments, not a cause: the
              // model averages three of these, and several move at once.
              Text(
                'When each score was worked out:',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.2,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 6),
              for (final component in change.components)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '${component.label}: ${Fmt.trimmed(component.previousValue)}'
                    ' → ${Fmt.trimmed(component.currentValue)} '
                    '(${component.previousScore} → ${component.currentScore} '
                    'points)',
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(
              Fmt.relative(change.observedAt),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The band as the rest of the product writes it.
  static String _band(String value) => switch (value) {
    'strong' => 'Strong',
    'good' => 'Good',
    'needs_attention' => 'Needs Attention',
    'at_risk' => 'At Risk',
    _ => value,
  };
}
