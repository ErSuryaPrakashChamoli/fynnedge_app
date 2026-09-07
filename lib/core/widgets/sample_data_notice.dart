import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../data/services/api_config.dart';

/// Says plainly that the offers on screen are illustrative.
///
/// Renders only while the app is on mock data, so it disappears by itself the
/// moment a real lender catalogue is connected. Nothing in FynnEdge should
/// let a customer mistake a fictional lender for a live market offer.
class SampleDataNotice extends StatelessWidget {
  const SampleDataNotice({
    super.key,
    this.margin = EdgeInsets.zero,
    this.message = offersMessage,
  });

  final EdgeInsets margin;

  /// What exactly is sample data here. The default speaks about offers;
  /// screens showing something else should say what they mean.
  final String message;

  static const String offersMessage =
      'Sample data. These lenders and rates are illustrative, not live '
      'market offers.';

  /// For screens where the calculation is real but the customer is seeded.
  static const String seededCustomerMessage =
      'Sample customer. The score is calculated for real from these figures, '
      'but the figures themselves are sample data.';

  @override
  Widget build(BuildContext context) {
    if (!ApiConfig.useMock) return const SizedBox.shrink();

    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.science_outlined,
            size: 14,
            color: AppColors.warning,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: AppColors.warning.withValues(alpha: 0.92),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Marks a figure as computed from what the customer told us, not as anything
/// anyone has agreed to.
///
/// FynnEdge shows a lot of arithmetic about money the customer has not
/// borrowed yet. Every one of those numbers carries this, so none of them can
/// be mistaken for an offer, an approval, or a commitment.
class EstimateBadge extends StatelessWidget {
  const EstimateBadge({super.key, this.label = 'ESTIMATE'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.calculate_outlined,
            size: 11,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
