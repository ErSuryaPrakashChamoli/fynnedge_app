import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/surfaces.dart';
import '../../../data/models/application_documents.dart';
import 'application_documents_controller.dart';
import 'vault_picker_sheet.dart';

/// The documents an application needs, and where each one stands.
///
/// The one thing this card must never imply is that any of it has gone
/// anywhere. "Ready" here means the customer has what an application of this
/// kind needs — not that a lender has it, is looking at it, or has accepted
/// it.
class ApplicationDocumentsCard extends ConsumerWidget {
  const ApplicationDocumentsCard({super.key, required this.applicationId});

  final String applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(applicationDocumentsProvider(applicationId));
    final controller =
        ref.read(applicationDocumentsProvider(applicationId).notifier);
    final checklist = state.checklist;

    if (state.loading && checklist == null) {
      return const LoadingList(items: 1, itemHeight: 150);
    }

    if (state.loadError != null && checklist == null) {
      return ErrorState(
        message: messageForLoad(state.loadError!),
        onRetry: controller.load,
      );
    }

    if (checklist == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Application documents',
          subtitle:
              '${checklist.readyCount} of ${checklist.requiredCount} ready',
        ),

        if (checklist.ready) ...[
          const _ReadyBanner(),
          const SizedBox(height: 12),
        ],

        if (state.failure != null) ...[
          _FailureNotice(state: state),
          const SizedBox(height: 12),
        ],

        for (final item in checklist.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RequirementTile(
              item: item,
              busy: state.isBusy(item.code),
              controller: controller,
            ),
          ),

        if (checklist.disclaimer != null) ...[
          const SizedBox(height: 4),
          Text(
            checklist.disclaimer!,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.55,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Everything required is confirmed — and what that does and does not mean.
class _ReadyBanner extends StatelessWidget {
  const _ReadyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.26)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: AppColors.success,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your documents are ready',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 5),
                const Text(
                  // The sentence that stops "ready" being read as "sent".
                  'Everything this application needs is confirmed by you. '
                  'Nothing has been sent to any lender.',
                  style: TextStyle(
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

/// One requirement row.
class _RequirementTile extends StatelessWidget {
  const _RequirementTile({
    required this.item,
    required this.busy,
    required this.controller,
  });

  final ChecklistItem item;
  final bool busy;
  final ApplicationDocumentsController controller;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A tick or a circle, never colour alone: the status is
              // spelled out below it either way.
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  item.status.isReady
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 18,
                  color: item.status.isReady
                      ? AppColors.success
                      : AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        // Optional is stated, so its absence never looks
                        // like something outstanding.
                        if (!item.required)
                          const Pill(
                            label: 'Optional',
                            color: AppColors.textTertiary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    if (item.document != null)
                      Text(
                        item.document!.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),

                    const SizedBox(height: 4),
                    Text(
                      item.status.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: switch (item.status) {
                          RequirementStatus.ready => AppColors.success,
                          RequirementStatus.missing => AppColors.textTertiary,
                          _ => AppColors.warning,
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (item.notice != null) ...[
            const SizedBox(height: 10),
            _Notice(text: item.notice!),
          ],

          const SizedBox(height: 12),
          _Actions(item: item, busy: busy, controller: controller),
        ],
      ),
    );
  }
}

/// What the customer can do with this requirement.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.item,
    required this.busy,
    required this.controller,
  });

  final ChecklistItem item;
  final bool busy;
  final ApplicationDocumentsController controller;

  Future<void> _pick(BuildContext context) async {
    final documentId = await VaultPickerSheet.show(context, item);
    if (documentId != null) {
      await controller.attach(item.code, documentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (item.status.isReady) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: busy ? null : () => _pick(context),
            child: const Text(
              'Choose a different one',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      );
    }

    // Chosen, awaiting the customer's confirmation. This is the step that
    // turns a file into "the document I am using".
    if (item.status == RequirementStatus.available ||
        item.status == RequirementStatus.needsReview) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryButton(
            // Not "Approve" and not "Verify": the customer is saying this
            // is the one they mean.
            label: 'Use this document',
            icon: Icons.check_rounded,
            loading: busy,
            onPressed: busy ? null : () => controller.confirm(item.code),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: busy ? null : () => _pick(context),
                child: const Text(
                  'Choose another',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: busy ? null : () => controller.reject(item.code),
                child: const Text(
                  "This isn't right",
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return SecondaryButton(
      label: item.action ?? 'Add from FynnVault',
      icon: Icons.folder_outlined,
      onPressed: busy ? null : () => _pick(context),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
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
            size: 13,
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

class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.state});
  final DocumentsScreenState state;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (state.failure!) {
      DocumentActionFailure.notEditable => (
        'This application can no longer be changed',
        'Its documents are kept as they were.',
      ),
      DocumentActionFailure.unknownRequirement => (
        'That document is not part of this application',
        'Please refresh and try again.',
      ),
      DocumentActionFailure.wrongType => (
        'That is not the kind of document this needs',
        'Choose one that matches what is being asked for.',
      ),
      DocumentActionFailure.unavailable => (
        'That document is no longer available',
        'Please choose another document from FynnVault.',
      ),
      DocumentActionFailure.nothingSelected => (
        'Choose a document first',
        'There is nothing to confirm yet.',
      ),
      DocumentActionFailure.other => (
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
