import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/session.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/sample_data_notice.dart';
import '../../core/widgets/states.dart';
import '../../data/models/match.dart';
import 'loan_controller.dart';
import 'widgets/offer_card.dart';
import '../../app/routes.dart';

/// Screen 11 — the products that fit this request, and the ones that do not
/// with the reason stated. Ordered by how well each lined up, then by
/// FynnTrust — never by what pays us, and never by approval odds, which
/// FynnEdge does not calculate.
class LoanOptionsScreen extends ConsumerWidget {
  const LoanOptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fynnMatchProvider);
    final request = ref.watch(loanRequestProvider);
    final selected = ref.watch(compareProvider);

    return FynnScaffold(
      title: 'Your options',
      subtitle:
          '${Fmt.compactMoney(request.amount)} · '
          '${Fmt.months(request.tenureMonths)}',
      padHorizontal: false,
      actions: [
        IconButton(
          onPressed: () => context.push(Routes.loanDiscovery),
          icon: const Icon(Icons.tune_rounded, size: 20),
          style: IconButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            backgroundColor: AppColors.surface,
            fixedSize: const Size(40, 40),
            shape: const CircleBorder(
              side: BorderSide(color: AppColors.border),
            ),
          ),
        ),
      ],
      bottomBar: selected.isEmpty
          ? null
          : Row(
              children: [
                Expanded(
                  child: Text(
                    '${selected.length} selected',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                PrimaryButton(
                  label: 'Compare',
                  expand: false,
                  icon: Icons.compare_arrows_rounded,
                  onPressed: selected.length < 2
                      ? null
                      : () => context.push(Routes.compare),
                ),
              ],
            ),
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: LoadingList(items: 3, itemHeight: 168),
        ),
        error: (e, _) => ErrorState(
          message: messageForLoad(e),
          onRetry: () => ref.invalidate(fynnMatchProvider),
        ),
        data: (result) {
          final viable = result.viable;
          final rejected = result.rejected;

          if (viable.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Nothing in our set fits that yet',
                  message:
                      'None of the ${result.evaluatedCount} products we hold '
                      'covers ${Fmt.compactMoney(request.amount)} for that '
                      'purpose. Every one is listed below with the reason.',
                  actionLabel: 'Change my request',
                  onAction: () => context.push(Routes.loanDiscovery),
                ),
                if (rejected.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _WhyNot(matches: rejected),
                ],
                _Disclaimer(text: result.disclaimer),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: viable.length + 2,
            separatorBuilder: (_, _) => const SizedBox(height: 13),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Column(
                  children: [
                    _Explainer(
                      count: viable.length,
                      evaluated: result.evaluatedCount,
                    ),
                    if (result.isSampleCatalogue)
                      const SampleDataNotice(
                        margin: EdgeInsets.only(top: 10, bottom: 2),
                      ),
                  ],
                );
              }

              if (i == viable.length + 1) {
                return Column(
                  children: [
                    if (rejected.isNotEmpty) _WhyNot(matches: rejected),
                    _Disclaimer(text: result.disclaimer),
                  ],
                );
              }

              final match = viable[i - 1];
              return Entrance(
                delay: Duration(milliseconds: 60 * i),
                child: OfferCard(
                  match: match,
                  inCompare: selected.contains(match.product.id),
                  onTap: () => context.push(Routes.loan(match.product.id)),
                  onCompareToggle: () {
                    final ok = ref
                        .read(compareProvider.notifier)
                        .toggle(match.product.id);
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('You can compare up to 3 offers.'),
                        ),
                      );
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer({required this.count, required this.evaluated});
  final int count;
  final int evaluated;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        children: [
          const Icon(Icons.sort_rounded, size: 16, color: AppColors.mint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count of $evaluated products line up with what you asked '
              'for, ordered by how well they fit and then by FynnTrust. '
              'Never by what pays us.\n\n'
              // What the badge on each card actually means. Said once here
              // rather than repeated on every card, and never as a chance
              // of being approved — no lender has seen any of this.
              'Strong Match: every rule we can check passed. '
              'Good Match: they passed, but something could not be checked. '
              'Worth a Look: they passed, with something to weigh up. '
              'None of these is a chance of approval.',
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

/// The products that did not fit, each with the rule that stopped it. Shown
/// rather than hidden: a customer who cannot see why a product was left out
/// has no way to tell a bad request from a bad catalogue.
class _WhyNot extends StatelessWidget {
  const _WhyNot({required this.matches});
  final List<ProductMatch> matches;

  @override
  Widget build(BuildContext context) {
    // A Material, not a plain decorated box: the ExpansionTile paints its ink
    // on the nearest Material ancestor, and a background colour in between
    // would hide it.
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              iconColor: AppColors.textTertiary,
              collapsedIconColor: AppColors.textTertiary,
              title: Text(
                '${matches.length} did not fit this request',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              children: [
                for (final match in matches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${match.product.lender} · ${match.product.name}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        for (final reason in match.blockers)
                          Text(
                            reason,
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.45,
                              color: AppColors.textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// FynnMatch says what it is, on every screen that shows a match.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          height: 1.5,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}
