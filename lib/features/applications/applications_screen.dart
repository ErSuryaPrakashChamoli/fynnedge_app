import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/application.dart';
import 'application_controller.dart';
import 'widgets/status_timeline.dart';
import '../../app/routes.dart';

/// Screen 19 — everything in flight, and everything closed.
class ApplicationsScreen extends ConsumerWidget {
  const ApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(applicationsProvider);
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        intensity: 0.6,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: LoadingList(items: 3, itemHeight: 150),
            ),
            error: (e, _) => ErrorState(
              message: messageForLoad(e),
              onRetry: () => ref.invalidate(applicationsProvider),
            ),
            data: (apps) {
              if (apps.isEmpty) {
                return EmptyState(
                  icon: Icons.inbox_rounded,
                  title: 'Nothing in progress',
                  message:
                      'When you apply for a loan through FynnEdge, you '
                      'will be able to follow every step of it here.',
                  actionLabel: 'Explore options',
                  onAction: () => context.go(Routes.explore),
                );
              }

              final active = apps.where((a) => !a.status.isTerminal).toList();
              final closed = apps.where((a) => a.status.isTerminal).toList();

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                children: staggered([
                  Text('Applications', style: t.displaySmall),
                  const SizedBox(height: 14),
                  if (active.isNotEmpty) ...[
                    SectionHeader(
                      title: 'Active',
                      subtitle: '${active.length} in progress',
                    ),
                    for (final app in active)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 13),
                        child: _ApplicationCard(app: app, expanded: true),
                      ),
                    const SizedBox(height: 16),
                  ],
                  if (closed.isNotEmpty) ...[
                    const SectionHeader(title: 'Completed'),
                    for (final app in closed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 13),
                        child: _ApplicationCard(app: app, expanded: false),
                      ),
                  ],
                ], step: const Duration(milliseconds: 65)),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.app, required this.expanded});

  final LoanApplication app;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(app.status);

    return FynnCard(
      onTap: () => context.push(Routes.application(app.id)),
      padding: const EdgeInsets.fromLTRB(17, 16, 17, 16),
      borderColor: expanded ? color.withValues(alpha: 0.28) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.productName,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${app.lender} · ${app.reference}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Pill(label: app.label, color: color, filled: true),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Metric(label: 'Amount', value: Fmt.compactMoney(app.amount)),
              const SizedBox(width: 22),
              _Metric(label: 'EMI', value: Fmt.money(app.emi)),
              const SizedBox(width: 22),
              _Metric(label: 'Tenure', value: Fmt.months(app.tenureMonths)),
            ],
          ),
          if (app.isSimulated) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.science_outlined,
                  size: 13,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Simulated submission — no provider has received this.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.warning.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (expanded) ...[
            const SizedBox(height: 16),
            const HairLine(),
            const SizedBox(height: 14),
            StatusTimeline(events: app.events, compact: true),
            if (app.nextAction.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppTheme.rSm),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.pending_actions_rounded,
                      size: 15,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        app.nextAction,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'View application',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: expanded ? color : AppColors.textSecondary,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: expanded ? color : AppColors.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
