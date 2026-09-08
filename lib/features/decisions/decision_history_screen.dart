import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../data/models/decision.dart';
import 'decision_controller.dart';

/// What the customer looked at, and what FynnEdge showed them.
///
/// Not an activity log. Nothing here records a screen being opened: every
/// entry is something the customer did — ran a simulation, put products
/// side by side, started an application — and each says only that.
///
/// A simulation is labelled a simulation on its own row, because a customer
/// scanning a list should not have to open something to find out whether it
/// was real.
class DecisionHistoryScreen extends ConsumerWidget {
  const DecisionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(decisionHistoryProvider);

    return FynnScaffold(
      title: 'What you explored',
      padHorizontal: false,
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: LoadingList(items: 4, itemHeight: 84),
        ),
        error: (e, _) => ErrorState(
          message: messageForLoad(e),
          onRetry: () => ref.invalidate(decisionHistoryProvider),
        ),
        data: (decisions) {
          if (decisions.isEmpty) {
            return const EmptyState(
              icon: Icons.history_rounded,
              title: 'Nothing here yet',
              // What lands here, and nothing implied about what they
              // should go and do.
              message:
                  'When you run a simulation, compare options or start an '
                  'application, what FynnEdge showed you will be here.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            itemCount: decisions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => Entrance(
              delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
              child: _DecisionTile(
                decision: decisions[i],
                onTap: () => context.push(Routes.decision(decisions[i].id)),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The icon and colour for a kind of exploration.
(IconData, Color) decisionStyle(String type) => switch (type) {
  'simulation' => (Icons.science_rounded, AppColors.violet),
  'comparison' => (Icons.compare_arrows_rounded, AppColors.blue),
  'application_submitted' => (Icons.send_rounded, AppColors.mint),
  _ => (Icons.receipt_long_rounded, AppColors.blue),
};

class _DecisionTile extends StatelessWidget {
  const _DecisionTile({required this.decision, required this.onTap});

  final Decision decision;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = decisionStyle(decision.type);

    return Semantics(
      button: true,
      label: '${decision.title}. ${decision.description}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: colour),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            decision.title,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        // Said on the row, not only inside. A customer
                        // scanning a list should not have to open something
                        // to learn whether it was real.
                        if (decision.isSimulated) const _SimulationChip(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      decision.description,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Text(
                          Fmt.relative(decision.occurredAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        if (decision.reference != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              decision.reference!,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                letterSpacing: 0.3,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimulationChip extends StatelessWidget {
  const _SimulationChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.violet.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.rSm),
      ),
      child: const Text(
        'SIMULATION',
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w800,
          color: AppColors.violet,
        ),
      ),
    );
  }
}
