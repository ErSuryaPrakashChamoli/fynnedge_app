import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../app/routes.dart';

/// Screen 23 — bring us an offer you got elsewhere.
class SecondOpinionScreen extends StatelessWidget {
  const SecondOpinionScreen({super.key});

  static const _checks = <(IconData, String, String)>[
    (
      Icons.percent_rounded,
      'The real rate',
      'Flat versus reducing balance, and what it actually costs you',
    ),
    (
      Icons.receipt_long_rounded,
      'Every fee',
      'Processing, insurance bundles, documentation and stamp charges',
    ),
    (
      Icons.lock_clock_rounded,
      'The exit terms',
      'What it costs to prepay, foreclose or transfer the loan later',
    ),
    (
      Icons.gavel_rounded,
      'The clauses that matter',
      'Rate reset triggers, penalties and anything that can change on you',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return FynnScaffold(
      title: 'Second Opinion',
      padHorizontal: false,
      glowPrimary: AppColors.violet,
      bottomBar: PrimaryButton(
        label: 'Upload Offer',
        icon: Icons.upload_file_rounded,
        onPressed: () => context.push(Routes.scan),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: staggered([
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  AppColors.violet.withValues(alpha: 0.25),
                  AppColors.blue.withValues(alpha: 0.10),
                ],
              ),
              border: Border.all(
                color: AppColors.violet.withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.fact_check_outlined,
              size: 28,
              color: AppColors.violet,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Want a second\nopinion?',
            style: t.displaySmall?.copyWith(height: 1.18),
          ),
          const SizedBox(height: 12),
          Text(
            'Upload your offer and we will help you understand the important '
            'numbers and terms.',
            style: t.bodyLarge?.copyWith(height: 1.55),
          ),
          const SizedBox(height: 30),
          const Text(
            'WHAT WE LOOK AT',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          for (final (icon, title, detail) in _checks)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      color: AppColors.violet.withValues(alpha: 0.10),
                    ),
                    child: Icon(icon, size: 17, color: AppColors.violet),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          detail,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppTheme.rMd),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.balance_rounded,
                  size: 15,
                  color: AppColors.textTertiary,
                ),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'We will tell you if the offer you already have is the '
                    'better one. There is no obligation to move it to us.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.55,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ], step: const Duration(milliseconds: 60)),
      ),
    );
  }
}
