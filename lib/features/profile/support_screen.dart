import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/surfaces.dart';
import '../../app/routes.dart';

/// Screen 29 — reaching a human.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  /// What can actually be reached today.
  ///
  /// This used to offer live chat, a callback booking and two support
  /// queues, with response times attached — none of which existed, and none
  /// of whose cards did anything when tapped. Email is the channel that is
  /// real, so email is what is offered.
  static const String supportEmail = 'support@fynnedge.com';

  static const _faqs = <(String, String)>[
    (
      'Does FynnEdge charge me anything?',
      'No. We are paid by lenders when a loan completes, at the same rate '
          'regardless of which lender you choose — which is why FynnTrust '
          'ranks on your interest, not ours.',
    ),
    (
      'Will using FynnEdge affect my credit score?',
      'No. FynnEdge has no connection to a credit bureau, so nothing here '
          'reads or writes your credit report — not when we match you to '
          'offers, and not when you start an application. If that ever '
          'changes we will ask your permission first.',
    ),
    (
      'What is FynnScore, exactly?',
      'It is our own read of your financial health, worked out from three '
          'things you told us: your EMI burden, your spending against your '
          'income, and how many months your savings would cover. It is not '
          'a credit bureau score, it is not a lender\'s approval score, and '
          'no lender sees it.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return FynnScaffold(
      title: 'Help & Support',
      padHorizontal: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: staggered([
          Text('Need help?', style: t.displaySmall),
          const SizedBox(height: 8),
          Text(
            'Write to us and a person will read it. For anything about your '
            'own figures, FynnAI can answer straight away.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 20),
          const SizedBox(height: 4),
          const SectionHeader(title: 'Common questions'),
          for (final (q, a) in _faqs) _Faq(question: q, answer: a),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppTheme.rMd),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'FynnEdge Advisory',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'support@fynnedge.com',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => context.go(Routes.ai),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 14,
                        color: AppColors.violet,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Or ask FynnAI first — it answers instantly',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.violet,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ], step: const Duration(milliseconds: 55)),
      ),
    );
  }
}

class _Faq extends StatefulWidget {
  const _Faq({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  State<_Faq> createState() => _FaqState();
}

class _FaqState extends State<_Faq> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => setState(() => _open = !_open),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 13, 14),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                crossFadeState: _open
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Padding(
                  padding: const EdgeInsets.only(top: 10, right: 20),
                  child: Text(
                    widget.answer,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                secondChild: const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
