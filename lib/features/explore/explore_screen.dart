import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/session.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/loan.dart';

/// Screen 9 — the whole product, grouped by what the customer is trying to do.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  /// Borrowing, by what the money is for.
  ///
  /// These used to be four links to `/loan-options?c=...` — a query
  /// parameter nothing read, so every one of them opened the same
  /// unfiltered list. Each now sets the purpose on the shared loan request
  /// and opens Loan Discovery, which is the screen that asks the rest of
  /// the questions FynnMatch needs.
  static const _borrow = <(String, IconData, LoanCategory)>[
    ('Personal Loan', Icons.person_outline_rounded, LoanCategory.personal),
    ('Business Loan', Icons.storefront_outlined, LoanCategory.business),
    ('Home Loan', Icons.home_outlined, LoanCategory.home),
    ('Loan Against Property', Icons.apartment_rounded, LoanCategory.lap),
  ];

  /// Each row goes to the calculator it names. Three of these used to land
  /// on the FynnLab index instead, leaving the customer to find the tool
  /// they had just asked for.
  static const _optimize = <(String, IconData, String)>[
    ('Prepayment', Icons.payments_outlined, Routes.prepayment),
    ('Balance transfer', Icons.swap_horiz_rounded, Routes.balanceTransfer),
    ('EMI calculator', Icons.calculate_rounded, Routes.emiCalculator),
    ('Compare loans', Icons.compare_arrows_rounded, Routes.loanOptions),
    ('All calculators', Icons.calculate_outlined, Routes.fynnLab),
  ];

  static const _plan = <(String, IconData, String)>[
    ('FynnScore', Icons.favorite_outline_rounded, Routes.fynnScore),
    ('Your goals', Icons.flag_outlined, Routes.goals),
    ('Emergency fund', Icons.shield_outlined, Routes.emergencyFund),
    // The financial simulator is FynnTwin, not the FynnLab index this used
    // to point at.
    ('FynnTwin', Icons.insights_rounded, Routes.fynnTwin),
  ];

  static const _documents = <(String, IconData, String)>[
    ('FynnVault', Icons.folder_outlined, Routes.vault),
    ('Add a document', Icons.upload_file_rounded, Routes.scan),
    // Was reachable only by typing the URL.
    ('Second opinion on an offer', Icons.balance_rounded, Routes.secondOpinion),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        intensity: 0.7,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
            children: staggered([
              Text(
                'What can we help\nyou with?',
                style: t.displaySmall?.copyWith(height: 1.18),
              ),
              const SizedBox(height: 22),
              const _AskFynnBanner(),
              const SizedBox(height: 28),
              _Group(
                title: 'Borrow',
                caption: 'Find money on terms that work',
                accent: AppColors.mint,
                items: [
                  for (final (label, icon, category) in _borrow)
                    (
                      label,
                      icon,
                      () {
                        ref
                            .read(loanRequestProvider.notifier)
                            .update(purpose: category.id);
                        context.push(Routes.loanDiscovery);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 26),
              _Group(
                title: 'Optimize',
                caption: 'Pay less for what you already owe',
                accent: AppColors.blue,
                items: _routed(context, _optimize),
              ),
              const SizedBox(height: 26),
              _Group(
                title: 'Plan',
                caption: 'Get ahead of what is coming',
                accent: AppColors.violet,
                items: _routed(context, _plan),
              ),
              const SizedBox(height: 26),
              _Group(
                title: 'Documents',
                caption: 'Kept private to your account',
                accent: AppColors.warning,
                items: _routed(context, _documents),
              ),
            ], step: const Duration(milliseconds: 70)),
          ),
        ),
      ),
    );
  }
}

/// Turns fixed destinations into the tap handlers the rows take.
List<(String, IconData, VoidCallback)> _routed(
  BuildContext context,
  List<(String, IconData, String)> items,
) => [
  for (final (label, icon, route) in items)
    (label, icon, () => context.push(route)),
];

class _AskFynnBanner extends StatelessWidget {
  const _AskFynnBanner();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(Routes.ai),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.violet.withValues(alpha: 0.20),
              AppColors.blue.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(color: AppColors.violet.withValues(alpha: 0.32)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.aiGradient,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 21,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ask FynnAI',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Describe your situation in your own words',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: AppColors.violet,
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.caption,
    required this.accent,
    required this.items,
  });

  final String title;
  final String caption;
  final Color accent;
  final List<(String, IconData, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 15,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(caption, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(height: 13),
        // Rows with hairlines, not four more cards — Explore is a directory.
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const HairLine(indent: 52),
                _Row(
                  label: items[i].$1,
                  icon: items[i].$2,
                  accent: accent,
                  onTap: items[i].$3,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 19, color: accent),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
