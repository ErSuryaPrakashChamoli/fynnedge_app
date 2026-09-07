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
import '../../data/models/kyc.dart';
import 'kyc_controller.dart';
import 'vault_controller.dart';

/// Identity verification on one stored document.
///
/// The screen exists to say precisely three things and never a fourth:
///
///   what was checked      the method, in words.
///   what was found        two findings, kept apart.
///   what it does not mean not approval, not proof of a person.
///
/// Nothing here calls a customer genuine, and nothing changes their profile
/// without them choosing it on that specific difference.
class KycScreen extends ConsumerWidget {
  const KycScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(kycControllerProvider(documentId));
    final controller = ref.read(kycControllerProvider(documentId).notifier);
    final document = ref
        .watch(documentsProvider)
        .value
        ?.where((d) => d.id == documentId)
        .firstOrNull;

    final result = state.verification;

    return FynnScaffold(
      title: 'Identity check',
      subtitle: document?.name ?? 'Checking your document',
      padHorizontal: false,
      bottomBar: PrimaryButton(
        label: 'Back to vault',
        icon: Icons.arrow_back_rounded,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      child: state.loading && result == null
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: LoadingList(items: 2, itemHeight: 120),
            )
          : state.loadError != null
          ? ErrorState(
              message: messageForLoad(state.loadError!),
              onRetry: controller.load,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
              children: staggered([
                if (result != null) ...[
                  _StateCard(result: result, state: state),
                  const SizedBox(height: 18),

                  if (state.failure != null) ...[
                    _FailureNotice(state: state),
                    const SizedBox(height: 18),
                  ],

                  if (result.status.hasResult) ...[
                    _WhatWasChecked(result: result),
                    const SizedBox(height: 18),
                  ],

                  for (final difference in result.differences) ...[
                    _Difference(
                      match: difference,
                      busy: state.isBusy(difference.field),
                      controller: controller,
                    ),
                    const SizedBox(height: 18),
                  ],

                  if (result.canVerify) ...[
                    _CheckAction(
                      result: result,
                      state: state,
                      controller: controller,
                    ),
                    const SizedBox(height: 18),
                  ],

                  _WhatThisIsNot(disclaimer: result.disclaimer),
                ],
              ], step: const Duration(milliseconds: 60)),
            ),
    );
  }
}

/// Where the check stands. Every branch says something true.
class _StateCard extends StatelessWidget {
  const _StateCard({required this.result, required this.state});

  final KycVerification result;
  final KycScreenState state;

  @override
  Widget build(BuildContext context) {
    if (state.checking || result.status.isWorking) {
      return const _Message(
        icon: Icons.hourglass_empty_rounded,
        title: 'Checking your document…',
        // No percentage. Nothing here knows how far along a service is.
        body: 'This usually takes a moment.',
        busy: true,
      );
    }

    return switch (result.status) {
      VerificationStatus.unavailable
          when result.reason == 'document_type_not_verifiable' =>
        const _Message(
          icon: Icons.description_outlined,
          title: "FynnEdge doesn't check this kind of document",
          body:
              'Your document is stored safely in FynnVault. FynnEdge '
              'currently checks identity documents, and nothing about this '
              'one has been checked.',
        ),

      // The sentence this whole screen exists to get right. Not available
      // is a fact about FynnEdge; it is not a finding about the customer.
      VerificationStatus.unavailable => _Message(
        icon: Icons.link_off_rounded,
        title: "Identity checks aren't available yet",
        body:
            result.message ??
            'FynnEdge is not connected to a verification service, so nothing '
                'about your document has been checked.',
      ),

      VerificationStatus.consentRequired => const _Message(
        icon: Icons.shield_outlined,
        title: 'Your permission comes first',
        body:
            'FynnEdge has not sent this document anywhere, and will not '
            'until you allow it. This is a separate permission from letting '
            'FynnEdge read a document — you can allow one and not the other.',
        action: (label: 'Privacy & Consent', route: Routes.privacy),
      ),

      VerificationStatus.notStarted => const _Message(
        icon: Icons.verified_user_outlined,
        title: 'Nothing checked yet',
        body:
            'FynnEdge has not sent this document anywhere. When you want it '
            'checked, ask below.',
      ),

      VerificationStatus.failed => _Message(
        icon: Icons.cloud_off_rounded,
        title: 'The check did not complete',
        body:
            result.message ??
            'FynnEdge received nothing back. Nothing has been concluded '
                'about you or your document.',
      ),

      VerificationStatus.verified ||
      VerificationStatus.notVerified ||
      VerificationStatus.needsReview ||
      VerificationStatus.expired => _ResultHeader(result: result),

      _ => const _Message(
        icon: Icons.help_outline_rounded,
        title: 'FynnEdge cannot say where this stands',
        body: 'Nothing has been concluded about your document.',
      ),
    };
  }
}

/// The header over a completed check.
class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.result});
  final KycVerification result;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (result.status) {
      VerificationStatus.verified => (
        'Identity verification passed',
        'The verification service reported that the document passed its '
            'checks, and the name on it matched your profile.',
      ),
      VerificationStatus.needsReview => (
        'Please review a difference',
        'The check ran. Something needs your attention before this can '
            'settle.',
      ),
      VerificationStatus.notVerified => (
        "We couldn't establish this",
        'The verification service did not confirm what it set out to check. '
            'That is a finding about this document, not about you.',
      ),
      _ => (
        'No longer current',
        'This result is no longer considered current. It does not mean the '
            'check failed.',
      ),
    };

    return FynnCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              // A synthetic result is labelled as one, on the same card.
              if (result.isSample)
                const Pill(label: 'Sample check', color: AppColors.warning),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),

          if (result.isStale) ...[
            const SizedBox(height: 14),
            const _Warning(
              text:
                  'This document has changed since it was checked. What is '
                  'shown below describes the previous file. Check it again '
                  'to see what the current one gives.',
            ),
          ],

          if (result.maskedReference != null) ...[
            const SizedBox(height: 14),
            DetailRow(
              label: 'Document checked',
              value: result.maskedReference!,
              hint: 'Only the last few characters are kept.',
            ),
          ],
        ],
      ),
    );
  }
}

/// What was actually checked, and what each check said.
class _WhatWasChecked extends StatelessWidget {
  const _WhatWasChecked({required this.result});
  final KycVerification result;

  @override
  Widget build(BuildContext context) {
    final matches = result.fieldMatches ?? const <FieldMatch>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'What was checked'),
        FynnCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The two findings, side by side and never merged. A document
              // can pass its own checks while naming somebody else.
              if (result.documentResult != null)
                _Finding(
                  label: 'The document itself',
                  outcome: result.documentResult!.label,
                  detail: switch (result.documentResult!) {
                    CheckOutcome.passed =>
                      'The verification service reported that the document '
                          'passed its authenticity checks.',
                    CheckOutcome.failed =>
                      'The verification service did not pass this document. '
                          'That is a finding about the document.',
                    CheckOutcome.inconclusive =>
                      'The verification service could not reach a definite '
                          'answer about the document.',
                    CheckOutcome.notPerformed =>
                      'This was not checked.',
                  },
                  tone: _toneFor(result.documentResult!),
                ),

              if (result.identityResult != null) ...[
                const HairLine(),
                _Finding(
                  label: 'The details on it',
                  outcome: result.identityResult!.label,
                  detail: switch (result.identityResult!) {
                    CheckOutcome.passed =>
                      'The name matched the information on your profile.',
                    CheckOutcome.failed =>
                      'The name did not match the information on your '
                          'profile.',
                    CheckOutcome.inconclusive =>
                      'There was not enough to compare.',
                    CheckOutcome.notPerformed =>
                      'Not compared, because the document did not pass its '
                          'own checks first.',
                  },
                  tone: _toneFor(result.identityResult!),
                ),
              ],

              if (matches.isNotEmpty) ...[
                const HairLine(),
                const SizedBox(height: 10),
                for (final match in matches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _FieldRow(match: match),
                  ),
              ],

              if (result.method != null) ...[
                const SizedBox(height: 10),
                Text(
                  result.method!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.55,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static Color _toneFor(CheckOutcome outcome) => switch (outcome) {
    CheckOutcome.passed => AppColors.success,
    CheckOutcome.failed => AppColors.danger,
    CheckOutcome.inconclusive => AppColors.warning,
    CheckOutcome.notPerformed => AppColors.textTertiary,
  };
}

class _Finding extends StatelessWidget {
  const _Finding({
    required this.label,
    required this.outcome,
    required this.detail,
    required this.tone,
  });

  final String label;
  final String outcome;
  final String detail;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              // The outcome is a word, not only a colour.
              Pill(label: outcome, color: tone),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.match});
  final FieldMatch match;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                match.label,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              if (match.reason != null) ...[
                const SizedBox(height: 3),
                Text(
                  match.reason!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          match.status.label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: switch (match.status) {
              MatchStatus.matched => AppColors.success,
              MatchStatus.mismatched => AppColors.warning,
              MatchStatus.unableToCompare => AppColors.textTertiary,
            },
          ),
        ),
      ],
    );
  }
}

/// A difference, and the customer's two ways out of it.
class _Difference extends StatelessWidget {
  const _Difference({
    required this.match,
    required this.busy,
    required this.controller,
  });

  final FieldMatch match;
  final bool busy;
  final KycController controller;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'We found a difference',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),

          _Side(label: '${match.label} on your profile', value: match.profileValue!),
          const SizedBox(height: 10),
          _Side(
            label: '${match.label} from the check',
            value: match.verifiedValue!,
          ),

          const SizedBox(height: 14),
          const Text(
            // Neither option is presented as the right one. FynnEdge cannot
            // tell which is correct, and pretending otherwise would push a
            // customer towards a change they may not want.
            'Please review this before changing anything. FynnEdge has not '
            'changed your profile.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),

          SecondaryButton(
            label: 'Keep what is on my profile',
            onPressed: busy ? null : () => controller.keepProfile(match.field),
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Update my profile to match',
            onPressed: busy ? null : () => controller.updateProfile(match.field),
          ),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _CheckAction extends StatelessWidget {
  const _CheckAction({
    required this.result,
    required this.state,
    required this.controller,
  });

  final KycVerification result;
  final KycScreenState state;
  final KycController controller;

  @override
  Widget build(BuildContext context) {
    final again = result.status.hasResult ||
        result.status == VerificationStatus.failed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SecondaryButton(
          label: again ? 'Check it again' : 'Check this document',
          icon: Icons.verified_user_outlined,
          onPressed: state.checking ? null : () => controller.verify(force: again),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your document is sent to be checked only when you tap this.',
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

class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.state});
  final KycScreenState state;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (state.failure!) {
      KycFailure.notConfigured => (
        'Identity checks are not available',
        'FynnEdge is not connected to a verification service.',
      ),
      KycFailure.unsupportedDocument => (
        'FynnEdge does not check this kind of document',
        'It is stored safely, and nothing has been checked.',
      ),
      KycFailure.consentRequired => (
        'Your permission is needed first',
        'Allow identity verification under Privacy & Consent, then try '
            'again.',
      ),
      KycFailure.providerUnavailable => (
        'We could not complete the check',
        'FynnEdge received nothing back, so it knows nothing new. Nothing '
            'has been concluded about you or your document.',
      ),
      KycFailure.tooManyChecks => (
        'That is enough checks for now',
        'Checking repeatedly can cost you, so FynnEdge limits how often it '
            'asks. Please try again a little later.',
      ),
      KycFailure.documentMissing => (
        'That file could not be opened',
        'FynnEdge could not read the stored file, so nothing was checked.',
      ),
      KycFailure.other => (
        'That did not work',
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

class _Warning extends StatelessWidget {
  const _Warning({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: AppColors.warning,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The limits, stated rather than left to be inferred.
class _WhatThisIsNot extends StatelessWidget {
  const _WhatThisIsNot({this.disclaimer});
  final String? disclaimer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What this does not mean',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          const _Limit(
            'It is not loan approval, and no lender has seen it.',
          ),
          const _Limit(
            'A check says what a verification service established about a '
            'document. It does not settle anything else about you.',
          ),
          const _Limit(
            'It does not change your FynnScore or which products fit you.',
          ),
          const _Limit(
            'Nothing on your profile changes unless you choose it.',
          ),
          if (disclaimer != null) ...[
            const SizedBox(height: 6),
            Text(
              disclaimer!,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.55,
                color: AppColors.textTertiary,
              ),
            ),
          ],
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

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final ({String label, String route})? action;
  final bool busy;

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
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(13),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textSecondary,
                    ),
                  )
                : Icon(icon, size: 21, color: AppColors.textSecondary),
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
