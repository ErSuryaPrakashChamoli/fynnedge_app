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
import '../../core/widgets/surfaces.dart';
import '../../data/models/support.dart';
import 'support_controller.dart';

/// Screen 29 — asking FynnEdge for help.
///
/// NO ADVISOR SYSTEM OR CHAT PROVIDER IS CONNECTED, and the screen says
/// nothing that implies otherwise. There is no "an advisor is available",
/// no response time and no queue position, because none of those exists.
/// What a customer gets is a request that is genuinely recorded and a
/// number they can quote.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(supportControllerProvider);
    final controller = ref.read(supportControllerProvider.notifier);
    final t = Theme.of(context).textTheme;

    return FynnScaffold(
      title: 'Support',
      padHorizontal: false,
      child: switch (state) {
        SupportHomeState(loading: true) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: LoadingList(items: 4, itemHeight: 76),
        ),

        SupportHomeState(loadError: final error?) => ErrorState(
          message: messageForLoad(error),
          onRetry: controller.load,
        ),

        _ => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: staggered([
            Text('How can we help?', style: t.displaySmall),
            const SizedBox(height: 8),
            Text(
              // What is true: a person reads it. Not when, because nobody
              // has agreed a time and quoting one would be inventing it.
              'Tell us what you need and we will look into it. You will get '
              'a reference you can quote.',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 20),

            for (final category in state.categories.take(6))
              _CategoryTile(
                category: category,
                onTap: () => context.push(Routes.supportNew(category: category.id)),
              ),

            if (state.categories.length > 6)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _CategoryTile(
                  category: const SupportCategoryOption(
                    id: 'general',
                    label: 'Something else',
                    description: 'Anything that does not fit the rest.',
                  ),
                  onTap: () => context.push(Routes.supportNew()),
                ),
              ),

            const SizedBox(height: 26),

            if (state.cases.isNotEmpty) ...[
              const SectionHeader(title: 'Your requests'),
              for (final item in state.cases)
                _CaseTile(
                  item: item,
                  onTap: () => context.push(Routes.supportCase(item.id)),
                ),
            ] else
              const _NoRequestsYet(),
          ]),
        ),
      },
    );
  }
}

class _NoRequestsYet extends StatelessWidget {
  const _NoRequestsYet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.inbox_rounded,
            size: 18,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You have not asked us anything yet. When you do, your requests '
              'will be here.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final SupportCategoryOption category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${category.label}. ${category.description}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 15),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.label,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      category.description,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
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
      ),
    );
  }
}

/// The colour and icon for a status.
///
/// Only two states are given any emphasis: one that needs the customer, and
/// one that is finished. Everything else is neutral, because a support
/// screen full of amber badges reads as a product in trouble.
(IconData, Color) statusStyle(SupportCaseStatus status) => switch (status) {
  SupportCaseStatus.waitingForCustomer => (
    Icons.edit_note_rounded,
    AppColors.warning,
  ),
  SupportCaseStatus.resolved => (Icons.check_circle_rounded, AppColors.mint),
  SupportCaseStatus.closed => (
    Icons.check_circle_outline_rounded,
    AppColors.textTertiary,
  ),
  _ => (Icons.schedule_rounded, AppColors.blue),
};

class _CaseTile extends StatelessWidget {
  const _CaseTile({required this.item, required this.onTap});

  final SupportCase item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = statusStyle(item.status);

    return Semantics(
      button: true,
      label: '${item.reference}. ${item.categoryLabel}. ${item.statusLabel}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: item.isOpen ? 0.85 : 0.4),
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: item.status.needsCustomer
                  ? colour.withValues(alpha: 0.3)
                  : AppColors.borderSoft,
            ),
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
                    Text(
                      item.reference,
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.categoryLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text(
                          item.statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colour,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            Fmt.relative(item.createdAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
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
