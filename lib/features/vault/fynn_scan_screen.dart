import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/error_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/scan.dart';
import 'scan_controller.dart';
import 'vault_controller.dart';

/// FynnScan — what a document appears to contain.
///
/// The screen exists to keep two things apart, and says so in as many words:
///
///   Found in your document   what a machine read.
///   Confirmed by you         what the customer says it is.
///
/// Nothing on this screen calls a reading verified, and nothing reaches the
/// customer's financial profile without them tapping Save on that field.
class FynnScanScreen extends ConsumerWidget {
  const FynnScanScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanControllerProvider(documentId));
    final controller = ref.read(scanControllerProvider(documentId).notifier);
    final document = ref
        .watch(documentsProvider)
        .value
        ?.where((d) => d.id == documentId)
        .firstOrNull;

    final scan = state.scan;

    return FynnScaffold(
      title: 'FynnScan',
      subtitle: document?.name ?? 'Reading your document',
      padHorizontal: false,
      bottomBar: PrimaryButton(
        label: 'Back to vault',
        icon: Icons.arrow_back_rounded,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      child: state.loading && scan == null
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
                if (scan != null) ...[
                  _StateCard(scan: scan, state: state),
                  const SizedBox(height: 18),

                  if (state.failure != null) ...[
                    _FailureNotice(state: state),
                    const SizedBox(height: 18),
                  ],

                  if (scan.status.hasExtraction) ...[
                    _Extraction(
                      scan: scan,
                      state: state,
                      controller: controller,
                    ),
                    const SizedBox(height: 18),
                  ],

                  if (scan.canScan) ...[
                    _ScanAction(
                      scan: scan,
                      state: state,
                      controller: controller,
                    ),
                    const SizedBox(height: 18),
                  ],

                  _WhatThisIsNot(disclaimer: scan.disclaimer),
                ],
              ], step: const Duration(milliseconds: 60)),
            ),
    );
  }
}

/// Where the reading stands. Every branch says something true.
class _StateCard extends StatelessWidget {
  const _StateCard({required this.scan, required this.state});

  final DocumentScan scan;
  final ScanScreenState state;

  @override
  Widget build(BuildContext context) {
    if (state.scanning || scan.status.isWorking) {
      // Queued and reading are different facts, and the difference is
      // small but real: nothing has been asked of a provider yet when a
      // reading is only queued.
      final reading = scan.status == ScanStatus.processing || state.scanning;

      return _Message(
        icon: Icons.hourglass_empty_rounded,
        title: reading ? 'Reading your document…' : 'Waiting to be read',
        // No percentage. Nothing here knows how far along a provider is,
        // and a number that moves without meaning is worse than no number.
        body: reading
            ? 'This usually takes a moment.'
            : 'Your document is in the queue. This usually takes a moment.',
        busy: true,
      );
    }

    return switch (scan.status) {
      // The server says which of the two it is. Inferring it from
      // is_supported got this wrong: a deployment with no provider at all
      // reports nothing about families, and the customer was told FynnScan
      // does not read their document type when the truth was that FynnScan
      // reads nothing at all.
      ScanStatus.unavailable
          when scan.reason == 'document_family_not_supported' =>
        const _Message(
        icon: Icons.description_outlined,
        title: "FynnScan doesn't read this kind of document",
        body:
            'Your document is stored safely in FynnVault. FynnScan currently '
            'reads income documents such as a salary slip, and nothing has '
            'been read from this one.',
      ),

      ScanStatus.unavailable => _Message(
        icon: Icons.link_off_rounded,
        title: "FynnScan isn't connected yet",
        body:
            '${scan.message ?? 'Your document is stored safely, but FynnEdge '
                    'is not connected to a document-reading service. Nothing '
                    'has been extracted or interpreted.'}\n\n'
            'Your document has not been read, verified or shared. It is '
            'stored in FynnVault, where only you can open it.',
      ),

      ScanStatus.consentRequired => const _Message(
        icon: Icons.shield_outlined,
        title: 'Your permission comes first',
        body:
            'FynnEdge has not sent this document anywhere, and will not '
            'until you allow it. You can allow it under Privacy & Consent, '
            'and withdraw it at any time.',
        action: (label: 'Privacy & Consent', route: Routes.privacy),
      ),

      ScanStatus.notStarted => const _Message(
        icon: Icons.auto_awesome_outlined,
        title: 'Nothing read yet',
        body:
            'FynnEdge has not sent this document anywhere. When you want it '
            'read, ask below — and you will get the chance to check '
            'everything before anything is saved.',
      ),

      ScanStatus.failed => _Message(
        icon: Icons.cloud_off_rounded,
        title: 'We could not read this document',
        body:
            scan.message ??
            'FynnEdge received nothing back. That says nothing about what '
                'your document contains — it means we do not know.',
      ),

      ScanStatus.completed || ScanStatus.needsReview => _ReadHeader(scan: scan),

      _ => const _Message(
        icon: Icons.help_outline_rounded,
        title: 'FynnScan cannot say where this stands',
        body: 'Nothing has been assumed about your document.',
      ),
    };
  }
}

/// The header over a reading. Says what was found, and that it is not yet
/// the customer's data.
class _ReadHeader extends StatelessWidget {
  const _ReadHeader({required this.scan});
  final DocumentScan scan;

  @override
  Widget build(BuildContext context) {
    final toCheck = scan.fieldsToCheck.length;
    final saved = scan.reviews.any((r) => r.appliedToProfile);

    return FynnCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  toCheck == 0
                      ? 'Here is what we found'
                      : 'Please check what we found',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              // A synthetic reading is labelled as one, on the same card.
              if (scan.isSample)
                const Pill(label: 'Sample data', color: AppColors.warning),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            switch ((toCheck, saved)) {
              // Saying "nothing is saved yet" above a field that says it was
              // saved is the sort of small contradiction that makes a
              // customer stop trusting the rest of the screen.
              (_, true) => 'What you confirmed is saved to your profile. '
                  'Anything you have not decided on is not.',
              (0, _) => 'Nothing here is saved to your profile yet. Check '
                  'each value against your document, then choose what to '
                  'keep.',
              _ => 'We could not read $toCheck of these clearly. Have a look '
                  'before deciding what to keep.',
            },
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),

          if (scan.isStale) ...[
            const SizedBox(height: 14),
            const _Warning(
              text:
                  'This document has changed since it was read. What is '
                  'shown below describes the previous file. Read it again to '
                  'see what the current one contains.',
            ),
          ],

          if (scan.classificationMismatch) ...[
            const SizedBox(height: 14),
            const _Warning(
              text:
                  'This does not look like the kind of document it was filed '
                  'under. Please check you uploaded the right file — FynnEdge '
                  'has not changed how it is filed.',
            ),
          ],

          if (scan.documentPeriod != null) ...[
            const SizedBox(height: 14),
            DetailRow(label: 'Period covered', value: scan.documentPeriod!),
          ],
        ],
      ),
    );
  }
}

/// The fields, each with its own decision.
class _Extraction extends StatelessWidget {
  const _Extraction({
    required this.scan,
    required this.state,
    required this.controller,
  });

  final DocumentScan scan;
  final ScanScreenState state;
  final ScanController controller;

  @override
  Widget build(BuildContext context) {
    final fields = scan.extraction ?? const <ExtractedField>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Found in your document'),
        for (final field in fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FieldCard(
              field: field,
              review: scan.reviewFor(field.key),
              busy: state.isBusy(field.key),
              controller: controller,
            ),
          ),
      ],
    );
  }
}

/// One value, and what the customer has said about it.
class _FieldCard extends StatefulWidget {
  const _FieldCard({
    required this.field,
    required this.review,
    required this.busy,
    required this.controller,
  });

  final ExtractedField field;
  final FieldReview? review;
  final bool busy;
  final ScanController controller;

  @override
  State<_FieldCard> createState() => _FieldCardState();
}

class _FieldCardState extends State<_FieldCard> {
  late final TextEditingController _input = TextEditingController();
  bool _editing = false;

  /// Only income has somewhere to go in the profile today. The rest are
  /// confirmable as a record of what the document said, and no more.
  bool get _canSaveToProfile => widget.field.key == 'net_income';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String get _displayValue {
    final field = widget.field;
    if (!field.isPresent) return 'Not shown on this document';
    if (field.isMoney && field.amount != null) {
      return Fmt.money(field.amount!);
    }
    return field.value!;
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final review = widget.review;

    return FynnCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),

          Text(
            _displayValue,
            style: TextStyle(
              fontSize: field.isMoney ? 24 : 17,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: field.isPresent
                  ? AppColors.textPrimary
                  : AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 10),

          _Provenance(field: field, review: review),

          if (field.reviewReason != null) ...[
            const SizedBox(height: 10),
            _Warning(text: field.reviewReason!),
          ],

          if (review != null) ...[
            const SizedBox(height: 12),
            _Decision(review: review, isMoney: field.isMoney),
          ],

          if (_editing) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _input,
              autofocus: true,
              keyboardType: field.isMoney
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: 'The correct ${field.label.toLowerCase()}',
                prefixText: field.isMoney ? '₹ ' : null,
              ),
            ),
          ],

          const SizedBox(height: 14),
          _Actions(
            field: field,
            busy: widget.busy,
            editing: _editing,
            canSave: _canSaveToProfile,
            controller: widget.controller,
            input: _input,
            onToggleEdit: (editing) => setState(() {
              _editing = editing;
              if (editing) _input.text = field.value ?? '';
            }),
          ),
        ],
      ),
    );
  }
}

/// Where the value came from, and how sure the reading was.
class _Provenance extends StatelessWidget {
  const _Provenance({required this.field, required this.review});

  final ExtractedField field;
  final FieldReview? review;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Confidence is never a colour alone: the label carries the meaning
        // for anyone who cannot distinguish them.
        Pill(
          label: field.confidence.label,
          icon: switch (field.confidence) {
            ConfidenceLevel.high => Icons.check_circle_outline_rounded,
            ConfidenceLevel.medium => Icons.error_outline_rounded,
            ConfidenceLevel.low => Icons.priority_high_rounded,
            ConfidenceLevel.unavailable => Icons.help_outline_rounded,
          },
          color: switch (field.confidence) {
            ConfidenceLevel.high => AppColors.success,
            ConfidenceLevel.medium => AppColors.warning,
            ConfidenceLevel.low => AppColors.danger,
            ConfidenceLevel.unavailable => AppColors.textTertiary,
          },
        ),
        if (field.evidence != null)
          Pill(
            label: field.evidence!.description,
            icon: Icons.article_outlined,
            color: AppColors.textTertiary,
          ),
      ],
    );
  }
}

/// What the customer decided, once they have.
class _Decision extends StatelessWidget {
  const _Decision({required this.review, required this.isMoney});

  final FieldReview review;
  final bool isMoney;

  /// The server records exact decimal strings. Rendering one raw shows a
  /// customer "75000.00" where every other figure in the app is ₹75,000.
  String _show(String? value) {
    if (value == null) return '—';
    if (!isMoney) return value;
    final parsed = num.tryParse(value);
    return parsed == null ? value : Fmt.money(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTheme.rSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 14,
                color: AppColors.mint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review.decision.label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          // Both facts, side by side. A correction does not erase what the
          // document appeared to say.
          if (review.wasCorrected) ...[
            const SizedBox(height: 6),
            Text(
              'We read ${_show(review.extractedValue)}. '
              'You said ${_show(review.customerValue)}.',
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textTertiary,
              ),
            ),
          ],

          if (review.appliedToProfile) ...[
            const SizedBox(height: 6),
            const Text(
              // What happened, and only what happened. Saving a figure is
              // not verifying a document.
              'Saved to your financial profile.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Confirm, correct, reject — and, separately, save.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.field,
    required this.busy,
    required this.editing,
    required this.canSave,
    required this.controller,
    required this.input,
    required this.onToggleEdit,
  });

  final ExtractedField field;
  final bool busy;
  final bool editing;
  final bool canSave;
  final ScanController controller;
  final TextEditingController input;
  final void Function(bool editing) onToggleEdit;

  @override
  Widget build(BuildContext context) {
    if (editing) {
      return Row(
        children: [
          Expanded(
            child: PrimaryButton(
              label: canSave ? 'Save this' : 'Save correction',
              loading: busy,
              onPressed: busy
                  ? null
                  : () async {
                      final ok = await controller.correct(
                        field.key,
                        input.text,
                        save: canSave,
                      );
                      if (ok) onToggleEdit(false);
                    },
            ),
          ),
          const SizedBox(width: 10),
          _TextAction(label: 'Cancel', onTap: () => onToggleEdit(false)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A value the provider was unsure about does not get the most
        // prominent button on the card. The strongest affordance nudges,
        // and nudging towards accepting a figure nobody could read
        // properly is the opposite of asking someone to check it.
        if (field.isPresent && canSave && field.needsReview)
          SecondaryButton(
            label: 'This is right — save it',
            icon: Icons.check_rounded,
            onPressed: busy
                ? null
                : () => controller.confirm(field.key, save: true),
          ),

        if (field.isPresent && canSave && !field.needsReview)
          PrimaryButton(
            // Deliberately not "Approve" or "Accept". The customer is
            // saying this is their figure, not approving anything.
            label: 'Save this figure',
            icon: Icons.check_rounded,
            loading: busy,
            onPressed: busy
                ? null
                : () => controller.confirm(field.key, save: true),
          ),

        if (field.isPresent && !canSave)
          SecondaryButton(
            label: 'This is right',
            icon: Icons.check_rounded,
            onPressed: busy ? null : () => controller.confirm(field.key),
          ),

        const SizedBox(height: 4),

        // Wrap rather than Row: on a narrow screen the two actions stack
        // instead of one of them being clipped off the edge.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            _TextAction(
              label: field.isPresent ? 'Correct this' : 'Enter it myself',
              onTap: () => onToggleEdit(true),
            ),
            if (field.isPresent)
              _TextAction(
                label: "That's not right",
                onTap: busy ? null : () => controller.reject(field.key),
              ),
          ],
        ),
      ],
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      ),
    );
  }
}

/// Asking for a reading, and never doing it unasked.
class _ScanAction extends StatelessWidget {
  const _ScanAction({
    required this.scan,
    required this.state,
    required this.controller,
  });

  final DocumentScan scan;
  final ScanScreenState state;
  final ScanController controller;

  @override
  Widget build(BuildContext context) {
    final again = scan.status.hasExtraction || scan.status == ScanStatus.failed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SecondaryButton(
          label: again ? 'Read it again' : 'Read this document',
          icon: Icons.auto_awesome_outlined,
          onPressed: state.scanning
              ? null
              : () => controller.scan(force: again),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your document is sent to be read only when you tap this.',
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
  final ScanScreenState state;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (state.failure!) {
      ScanFailure.notConfigured => (
        'FynnScan is not connected',
        'FynnEdge cannot read documents yet.',
      ),
      ScanFailure.unsupportedDocument => (
        'FynnScan does not read this kind of document',
        'It is stored safely, and nothing has been read from it.',
      ),
      ScanFailure.consentRequired => (
        'Your permission is needed first',
        'Allow document processing under Privacy & Consent, then try again.',
      ),
      ScanFailure.providerUnavailable => (
        'We could not read it right now',
        'FynnEdge received nothing back, so it knows nothing new about your '
            'document. You can try again later.',
      ),
      ScanFailure.tooManyScans => (
        'That is enough for now',
        'Reading a document repeatedly can cost you, so FynnEdge limits how '
            'often it asks. Please try again a little later.',
      ),
      ScanFailure.documentMissing => (
        'That file could not be opened',
        'FynnEdge could not read the stored file. Nothing has been assumed '
            'about what it contains.',
      ),
      ScanFailure.other => (
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
            'What FynnScan does not do',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          const _Limit(
            'It reads your document. It does not check whether the document '
            'is genuine.',
          ),
          const _Limit(
            'Nothing it finds is saved to your profile until you say so.',
          ),
          const _Limit('Your document is not sent to any lender.'),
          const _Limit(
            'It does not approve or decline you. Only a lender does that.',
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

/// A plain state message, with an optional way forward.
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
