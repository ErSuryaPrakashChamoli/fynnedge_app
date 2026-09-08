import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';

/// A quiet offer of human help, from wherever the customer is.
///
/// One widget rather than a card written afresh on every screen, so the
/// wording cannot drift and every one of them attaches the context it came
/// from. Nothing here says an advisor is available or quotes a time, because
/// NO ADVISOR SYSTEM IS CONNECTED — what is offered is a request that gets
/// recorded and a reference.
///
/// Deliberately understated. Support that shouts from every screen reads as
/// a product that expects to go wrong.
class GetHelpCard extends StatelessWidget {
  const GetHelpCard({
    super.key,
    required this.prompt,
    required this.category,
    this.contextType,
    this.contextId,
    this.subject,
    this.margin = EdgeInsets.zero,
  });

  /// The one line above the button, e.g. 'Questions about your score?'
  final String prompt;

  final String category;
  final String? contextType;
  final String? contextId;

  /// A title the request opens with, so the customer starts from something.
  final String? subject;

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 14, 12, 14),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border: Border.all(color: AppColors.borderSoft),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.support_agent_rounded,
              size: 18,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                prompt,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'Get help. $prompt',
              child: GestureDetector(
                onTap: () => context.push(
                  Routes.supportNew(
                    category: category,
                    contextType: contextType,
                    contextId: contextId,
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.mint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                    border: Border.all(
                      color: AppColors.mint.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Text(
                    'Get help',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.mint,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
