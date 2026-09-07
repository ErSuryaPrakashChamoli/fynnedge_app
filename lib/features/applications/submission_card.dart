import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/submission.dart';
import 'submission_controller.dart';

/// Where an application stands with an external provider.
///
/// Deliberately its own card, separate from the application's own status.
/// "Your application is ready in FynnEdge" and "a provider has it" are
/// different facts, and one status line would eventually be read as though
/// FynnEdge's own acknowledgement were a provider's.
class SubmissionCard extends ConsumerWidget {
  const SubmissionCard({super.key, required this.applicationId});

  final String applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(submissionControllerProvider(applicationId));
    final controller =
        ref.read(submissionControllerProvider(applicationId).notifier);
    final submission = state.submission;

    if (state.loading && submission == null) {
      return const FynnCard(
        padding: EdgeInsets.all(18),
        child: SizedBox(
          height: 60,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    if (submission == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Submission'),
        FynnCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Status(state: state, submission: submission),

              if (submission.destination.displayName != null) ...[
                const SizedBox(height: 14),
                DetailRow(
                  label: submission.destination.isSimulated
                      ? 'Would go to'
                      : 'Sent to',
                  value: submission.destination.displayName!,
                  hint: submission.destination.isSimulated
                      ? 'A simulated destination, not a real provider.'
                      : null,
                ),
              ],

              // The provider's reference, alongside FynnEdge's rather than
              // replacing it. Shown only when a provider actually gave one.
              if (submission.providerReference != null) ...[
                const SizedBox(height: 4),
                DetailRow(
                  label: 'Provider reference',
                  value: submission.providerReference!,
                ),
              ],

              if (state.failure != null) ...[
                const SizedBox(height: 14),
                _FailureNotice(state: state),
              ],

              const SizedBox(height: 16),
              _Action(
                state: state,
                submission: submission,
                controller: controller,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The status line, and the sentence that qualifies it.
class _Status extends StatelessWidget {
  const _Status({required this.state, required this.submission});

  final SubmissionScreenState state;
  final ApplicationSubmission submission;

  @override
  Widget build(BuildContext context) {
    if (state.submitting || submission.outcome.isWorking) {
      return const _Line(
        label: 'Sending your application…',
        // No percentage: nothing here knows how far along a provider is.
        detail: 'This usually takes a moment.',
        tone: AppColors.textSecondary,
      );
    }

    return switch (submission.outcome) {
      // The one outcome that means an external party has it.
      SubmissionOutcome.providerReceived => _Line(
        label: 'Received by the provider',
        detail: 'The provider confirmed it has your application. What '
            'happens next is their decision, and FynnEdge will tell you '
            'what it hears.',
        tone: AppColors.success,
        badge: submission.attemptedAt == null ? null : 'Confirmed',
      ),

      // Simulated gets the loudest label on the card, not a footnote.
      SubmissionOutcome.simulated => const _Line(
        label: 'Simulated — no lender received this',
        detail: 'FynnEdge is not connected to an application provider yet, '
            'so this submission went nowhere. Nothing has been sent to any '
            'lender, and no one is reviewing your application.',
        tone: AppColors.warning,
        badge: 'SIMULATED',
      ),

      SubmissionOutcome.acceptedForSubmission => const _Line(
        label: 'Accepted for submission',
        detail: 'The provider took your application and has not yet '
            'confirmed receipt.',
        tone: AppColors.textSecondary,
      ),

      // Never presented as a lending decision.
      SubmissionOutcome.rejectedByGateway => const _Line(
        label: 'Not accepted for submission',
        detail: 'The provider did not accept this application for sending. '
            'That is not a decision about lending to you — no lender has '
            'seen it.',
        tone: AppColors.warning,
      ),

      // The important one: not a failure, and no retry offered.
      SubmissionOutcome.unknown => const _Line(
        label: "We couldn't confirm delivery",
        detail: 'Your application was sent and we did not get a reply, so we '
            'cannot tell whether the provider received it. Please do not '
            'send it again — contact support and we will check first.',
        tone: AppColors.warning,
      ),

      SubmissionOutcome.failed => _Line(
        label: 'Could not be sent',
        detail: submission.message ??
            'The application provider is temporarily unavailable. Your '
                'application is safe in FynnEdge.',
        tone: AppColors.warning,
      ),

      SubmissionOutcome.unavailable => _Line(
        label: 'Not sent anywhere',
        detail: submission.message ??
            'FynnEdge is not connected to an application provider yet, so '
                'this application has not been sent. It is saved here and '
                'nothing about it has failed.',
        tone: AppColors.textTertiary,
      ),

      SubmissionOutcome.notAttempted => _Line(
        label: submission.needsConsent
            ? 'Your permission is needed'
            : 'Not yet sent',
        detail: submission.needsConsent
            ? 'FynnEdge has not sent this application anywhere, and will not '
                  'until you allow it.'
            : 'Your application is ready in FynnEdge. It has not been sent '
                  'to a provider yet.',
        tone: AppColors.textSecondary,
      ),

      _ => const _Line(
        label: 'Not sent anywhere',
        detail: 'Nothing has been assumed about this application.',
        tone: AppColors.textTertiary,
      ),
    };
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.detail,
    required this.tone,
    this.badge,
  });

  final String label;
  final String detail;
  final Color tone;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: tone,
                ),
              ),
            ),
            // The badge carries the meaning in a word, not only a colour.
            if (badge != null) ...[
              const SizedBox(width: 10),
              Pill(label: badge!, color: tone),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          detail,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.6,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// What the customer can do next, and nothing they cannot.
class _Action extends StatelessWidget {
  const _Action({
    required this.state,
    required this.submission,
    required this.controller,
  });

  final SubmissionScreenState state;
  final ApplicationSubmission submission;
  final SubmissionController controller;

  @override
  Widget build(BuildContext context) {
    if (submission.needsConsent) {
      return SecondaryButton(
        label: 'Review and allow sending',
        icon: Icons.shield_outlined,
        onPressed: () => context.push(Routes.privacy),
      );
    }

    // Deliberately absent after an unknown outcome: a "send again" button
    // there could create a second application at a provider that may
    // already hold this one.
    if (submission.needsReconciliation) {
      return const Text(
        'FynnEdge will not send this again until we know where the first '
        'one went.',
        style: TextStyle(
          fontSize: 12,
          height: 1.55,
          color: AppColors.textTertiary,
        ),
      );
    }

    if (!submission.canRetry) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          // Never "Get approved" or "Get loan now". Sending an application
          // is what happens; it is not a promise about the outcome.
          label: submission.hasBeenAttempted
              ? 'Try sending again'
              : 'Submit application',
          icon: Icons.send_rounded,
          loading: state.submitting,
          onPressed: state.submitting ? null : controller.submit,
        ),
        const SizedBox(height: 10),
        Text(
          submission.destination.isSimulated
              ? 'This will run a simulated submission. Nothing will be sent '
                    'to a lender.'
              : 'Your application is sent only when you tap this.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11.5,
            height: 1.55,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.state});
  final SubmissionScreenState state;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (state.failure!) {
      SubmissionFailure.notConfigured => (
        'Sending is not available',
        'FynnEdge is not connected to an application provider yet.',
      ),
      SubmissionFailure.consentRequired => (
        'Your permission is needed first',
        'Allow FynnEdge to send this application, then try again.',
      ),
      SubmissionFailure.notSubmittable => (
        'This application cannot be sent',
        'Its current state does not allow sending.',
      ),
      SubmissionFailure.mappingMissing => (
        'This product cannot be sent right now',
        'Your application is safe in FynnEdge.',
      ),
      SubmissionFailure.providerUnavailable => (
        'The provider is temporarily unavailable',
        'Your application is safe in FynnEdge and nothing about it has '
            'failed.',
      ),
      SubmissionFailure.tooManyAttempts => (
        'That is enough attempts for now',
        'Each attempt may create an application with the provider, so '
            'FynnEdge limits how often it sends. Please try again later.',
      ),
      SubmissionFailure.other => (
        'That did not work',
        state.failureMessage ?? 'Please try again.',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: AppColors.warning,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
