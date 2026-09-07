import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/application.dart';

/// What has actually happened to an application, in order.
///
/// Only real events appear here — there are no greyed-out future steps.
/// A rail showing "Decision" as a pending step would be FynnEdge implying a
/// decision is on its way, which it cannot know.
class StatusTimeline extends StatelessWidget {
  const StatusTimeline({super.key, required this.events, this.compact = false});

  final List<ApplicationEvent> events;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          _Step(
            event: events[i],
            isLast: i == events.length - 1,
            isCurrent: i == events.length - 1,
            compact: compact,
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.event,
    required this.isLast,
    required this.isCurrent,
    required this.compact,
  });

  final ApplicationEvent event;
  final bool isLast;
  final bool isCurrent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = isCurrent
        ? AppColors.mint
        : AppColors.mint.withValues(alpha: 0.55);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.18),
                  border: Border.all(color: color, width: isCurrent ? 2 : 1.4),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: AppColors.mint.withValues(alpha: 0.35),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: Icon(Icons.check_rounded, size: 12, color: color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: AppColors.mint.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isLast ? 0 : (compact ? 16 : 22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        event.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      // Who is speaking. A simulated event must never be
                      // mistaken for something a provider actually did.
                      if (event.isSimulated) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text(
                            'SIMULATED',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (event.at != null)
                        Text(
                          Fmt.shortDate(event.at!),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                  if (event.detail.isNotEmpty && !compact) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.detail,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Colour for an application status, used in lists and headers.
Color statusColor(ApplicationStatus status) => switch (status) {
  ApplicationStatus.started => AppColors.textTertiary,
  ApplicationStatus.submitted => AppColors.blue,
  ApplicationStatus.underReview => AppColors.warning,
  ApplicationStatus.actionNeeded => AppColors.danger,
  ApplicationStatus.cancelled => AppColors.textTertiary,
  ApplicationStatus.approved => AppColors.mint,
  ApplicationStatus.disbursed => AppColors.mint,
  ApplicationStatus.declined => AppColors.danger,
};
