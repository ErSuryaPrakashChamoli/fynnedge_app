import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/credit.dart';
import 'credit_controller.dart';

/// Credit information — what a bureau says, kept apart from what FynnEdge
/// says.
///
/// The screen has one job beyond showing a number: making sure the customer
/// never confuses these four things.
///   FynnScore         FynnEdge's view of financial health.
///   Bureau score      A credit bureau's view of credit history.
///   A requirement     Something a provider has published.
///   Approval          A provider's decision, which FynnEdge does not make.
class CreditScreen extends ConsumerWidget {
  const CreditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(creditControllerProvider);
    final controller = ref.read(creditControllerProvider.notifier);
    final credit = state.credit;

    return FynnScaffold(
      title: 'Credit Information',
      subtitle: 'What a credit bureau holds about you',
      padHorizontal: false,
      child: state.loading && credit == null
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: LoadingList(items: 2, itemHeight: 130),
            )
          : state.loadError != null
          ? ErrorState(
              message: messageForLoad(state.loadError!),
              onRetry: controller.load,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
              children: staggered([
                _StateCard(state: state),
                const SizedBox(height: 18),
                if (state.failure != null) ...[
                  _FailureNotice(state: state),
                  const SizedBox(height: 18),
                ],
                if (credit != null && credit.canCheck) ...[
                  _CheckAction(state: state, controller: controller),
                  const SizedBox(height: 18),
                ],
                const _NotTheSameThing(),
                const SizedBox(height: 18),
                const _WhatThisIsNot(),
              ], step: const Duration(milliseconds: 60)),
            ),
    );
  }
}

/// The one card that changes with the state. Every branch is truthful about
/// what FynnEdge knows; none of them shows a number it does not have.
class _StateCard extends StatelessWidget {
  const _StateCard({required this.state});
  final CreditScreenState state;

  @override
  Widget build(BuildContext context) {
    final credit = state.credit;
    if (credit == null) return const SizedBox.shrink();

    return switch (credit.status) {
      CreditReportStatus.available when credit.profile != null => _Report(
        profile: credit.profile!,
      ),

      CreditReportStatus.notConfigured => const _Message(
        icon: Icons.link_off_rounded,
        title: "FynnEdge isn't connected to a credit bureau",
        body:
            'No credit bureau is connected to FynnEdge, so there is nothing '
            'to check and nothing held about your credit history. If a '
            'product you are looking at lists a credit requirement, FynnEdge '
            'will say it could not check it — never that you passed it.',
      ),

      CreditReportStatus.consentRequired => const _Message(
        icon: Icons.shield_outlined,
        title: 'Your permission comes first',
        body:
            'FynnEdge has not asked any credit bureau about you, and will '
            'not until you allow it. You can allow it under Privacy & '
            'Consent, and withdraw it at any time.',
        action: (label: 'Privacy & Consent', route: Routes.privacy),
      ),

      CreditReportStatus.notRequested => const _Message(
        icon: Icons.search_rounded,
        title: 'Nothing checked yet',
        body:
            'You have allowed a credit check. FynnEdge has not made one — '
            'allowing it is permission to ask, not an instruction to. When '
            'you want it checked, ask below.',
      ),

      CreditReportStatus.failed => const _Message(
        icon: Icons.cloud_off_rounded,
        title: 'The last check did not come back',
        body:
            'FynnEdge did not receive your credit information. That says '
            'nothing about your credit — it means we do not know. Nothing '
            'has been assumed in its place.',
      ),

      // Reached only when a build meets a state it does not know, or an
      // available status arrives with no readable report.
      _ => const _Message(
        icon: Icons.help_outline_rounded,
        title: 'Credit information is unavailable',
        body:
            'FynnEdge cannot tell you where your credit check stands right '
            'now. Nothing has been assumed about it.',
      ),
    };
  }
}

/// The report itself. Score, model and scale, always together.
class _Report extends StatelessWidget {
  const _Report({required this.profile});
  final CreditProfile profile;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  profile.bureauLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              // A fictional score must be labelled as one, everywhere it
              // appears.
              if (profile.isSample)
                const Pill(label: 'Sample data', color: AppColors.warning),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${profile.score}',
                style: const TextStyle(
                  fontSize: 42,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              // The scale is not decoration. A number without it cannot be
              // read, and must never be shown alone.
              Text(
                'of ${profile.scaleLabel}',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: profile.positionOnScale,
              minHeight: 6,
              backgroundColor: AppColors.surfaceHigh,
              valueColor: const AlwaysStoppedAnimation(AppColors.blue),
            ),
          ),
          const SizedBox(height: 16),

          DetailRow(label: 'Scoring model', value: profile.scoreModel),
          DetailRow(
            label: 'Obtained',
            value: profile.obtainedAt == null
                ? 'Unavailable'
                : _on(profile.obtainedAt!),
          ),
          const SizedBox(height: 4),

          const Text(
            'This is what a credit bureau reported. FynnEdge did not '
            'calculate it, cannot change it, and does not judge you by it.',
            style: TextStyle(
              fontSize: 12,
              height: 1.55,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  static String _on(DateTime at) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = at.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}

/// A check the customer asks for, never one that happens on its own.
class _CheckAction extends StatelessWidget {
  const _CheckAction({required this.state, required this.controller});

  final CreditScreenState state;
  final CreditController controller;

  @override
  Widget build(BuildContext context) {
    final hasReport = state.credit?.hasReport ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          label: hasReport ? 'Check again' : 'Check my credit information',
          icon: Icons.refresh_rounded,
          loading: state.checking,
          onPressed: state.checking ? null : controller.check,
        ),
        const SizedBox(height: 10),
        const Text(
          // What FynnEdge can promise is what it does. What happens at the
          // bureau is the bureau's, and no claim is made about it here.
          'FynnEdge asks only when you tap this. We do not say what a bureau '
          'records when it is asked — that is between you and them, and we '
          'will not guess on their behalf.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.55,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// What went wrong, in the customer's terms. Never a score.
class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.state});
  final CreditScreenState state;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (state.failure!) {
      CreditFailure.notConfigured => (
        'No bureau is connected',
        'FynnEdge cannot check credit information yet.',
      ),
      CreditFailure.consentRequired => (
        'Your permission is needed first',
        'Allow a credit check under Privacy & Consent, then try again.',
      ),
      CreditFailure.bureauUnavailable => (
        'We could not reach the bureau',
        'FynnEdge received nothing, so it knows nothing new. Your credit '
            'has not been judged either way. You can try again later.',
      ),
      CreditFailure.tooManyChecks => (
        'That is enough checks for now',
        'Asking repeatedly can cost you, so FynnEdge limits how often it '
            'asks. Please try again a little later.',
      ),
      CreditFailure.other => (
        'The check did not complete',
        state.failureMessage ?? 'Please try again.',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
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
            size: 17,
            color: AppColors.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
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

/// The distinction the whole screen exists to protect.
class _NotTheSameThing extends StatelessWidget {
  const _NotTheSameThing();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Two different numbers'),
        FynnCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Distinction(
                title: 'Your FynnScore',
                body:
                    "FynnEdge's own view of your financial health, worked out "
                    'from the figures you entered. You can see exactly how it '
                    'is calculated.',
              ),
              const HairLine(),
              const _Distinction(
                title: 'A credit bureau score',
                body:
                    "A credit bureau's view of your borrowing history, on "
                    'their scale, by their method. FynnEdge only reports it.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Neither is calculated from the other, and neither one '
                'changes the other.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.55,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'How your FynnScore works',
                icon: Icons.insights_outlined,
                onPressed: () => context.push(Routes.fynnScore),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Distinction extends StatelessWidget {
  const _Distinction({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The limits, stated plainly rather than left to be inferred.
class _WhatThisIsNot extends StatelessWidget {
  const _WhatThisIsNot();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What this does not do',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 10),
          _Limit('It does not approve or decline you. Only a lender does.'),
          _Limit(
            'It is not sent to any lender. FynnEdge shares nothing without '
            'a separate permission from you.',
          ),
          _Limit(
            'It does not change your FynnScore, and never has.',
          ),
          _Limit(
            'Meeting a published requirement is not an offer. It means one '
            'stated condition is met, and nothing more.',
          ),
        ],
      ),
    );
  }
}

class _Limit extends StatelessWidget {
  const _Limit(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(
              Icons.remove_rounded,
              size: 12,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.55,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain state message, with an optional way forward.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final ({String label, String route})? action;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceHigh.withValues(alpha: 0.8),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, size: 21, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            SecondaryButton(
              label: action!.label,
              icon: Icons.arrow_forward_rounded,
              onPressed: () => context.push(action!.route),
            ),
          ],
        ],
      ),
    );
  }
}
