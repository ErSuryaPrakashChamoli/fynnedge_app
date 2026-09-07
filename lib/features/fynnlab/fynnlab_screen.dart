import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';

/// Screen 16 — the toolbox. Every tool runs on the same FinanceService the
/// rest of the app uses, so numbers never disagree between screens.
class FynnLabScreen extends StatelessWidget {
  const FynnLabScreen({super.key});

  static const _tools = <_Tool>[
    _Tool(
      'FynnTwin',
      'What a decision would do to your month',
      Icons.insights_rounded,
      Routes.fynnTwin,
      AppColors.blue,
      true,
    ),
    _Tool(
      'EMI Calculator',
      'What a loan costs each month',
      Icons.calculate_rounded,
      Routes.emiCalculator,
      AppColors.mint,
      true,
    ),
    _Tool(
      'Loan Affordability',
      'How much you can safely borrow',
      Icons.account_balance_wallet_rounded,
      Routes.affordability,
      AppColors.blue,
      true,
    ),
    _Tool(
      'Prepayment',
      'What a lump sum would save you',
      Icons.savings_rounded,
      Routes.prepayment,
      AppColors.mint,
      true,
    ),
    _Tool(
      'Balance Transfer',
      'Whether moving your loan pays off',
      Icons.swap_horiz_rounded,
      Routes.balanceTransfer,
      AppColors.violet,
      true,
    ),
    _Tool(
      'Emergency Fund',
      'How long your savings would last',
      Icons.shield_rounded,
      Routes.emergencyFund,
      AppColors.warning,
      true,
    ),
    _Tool(
      'Debt Calculator',
      'Your total debt position',
      Icons.donut_large_rounded,
      '',
      AppColors.danger,
      false,
    ),
    _Tool(
      'Future Simulator',
      'Project your position years ahead',
      Icons.insights_rounded,
      '',
      AppColors.blue,
      false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return FynnScaffold(
      title: 'FynnLab',
      padHorizontal: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: staggered([
          Text(
            'Run the numbers\nbefore you commit.',
            style: t.displaySmall?.copyWith(height: 1.2),
          ),
          const SizedBox(height: 8),
          Text(
            'Every tool uses your real income, expenses and EMIs.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 24),
          for (final tool in _tools)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: _ToolCard(tool: tool),
            ),
        ], step: const Duration(milliseconds: 55)),
      ),
    );
  }
}

class _Tool {
  const _Tool(
    this.title,
    this.subtitle,
    this.icon,
    this.route,
    this.accent,
    this.ready,
  );

  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final Color accent;
  final bool ready;
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool});
  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: tool.ready
          ? () => context.push(tool.route)
          : () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${tool.title} is next in the build.')),
            ),
      child: Opacity(
        opacity: tool.ready ? 1 : 0.5,
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 15, 14, 15),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tool.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(tool.icon, size: 19, color: tool.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tool.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!tool.ready)
                const Text(
                  'SOON',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: AppColors.textTertiary,
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
