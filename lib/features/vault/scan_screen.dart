import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/document.dart';
import 'add_document_controller.dart';
import 'vault_controller.dart';

/// Screen 22 — adding a document to FynnVault.
///
/// It files and stores. It does not read the document: FynnEdge has no
/// document-understanding provider, so this screen claims nothing about what
/// is inside the file.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // A fresh attempt each time the screen opens, so a file chosen on a
    // previous visit is not still sitting here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(addDocumentProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _store() async {
    final name = _nameController.text.trim();
    final stored = await ref
        .read(addDocumentProvider.notifier)
        .store(name: name.isEmpty ? null : name);

    if (!mounted || stored == null) return;
    _nameController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addDocumentProvider);
    final limits = ref.watch(vaultLimitsProvider).value ?? const VaultLimits();

    return FynnScaffold(
      title: 'Add a document',
      subtitle: 'Stored privately in your FynnEdge account',
      padHorizontal: false,
      bottomBar: switch (state.step) {
        AddDocumentStep.choose => null,
        AddDocumentStep.review => PrimaryButton(
          label: state.uploading ? 'Storing…' : 'Store in FynnVault',
          icon: Icons.lock_outline_rounded,
          loading: state.uploading,
          onPressed: state.busy ? null : _store,
        ),
        AddDocumentStep.stored => Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: 'Back to vault',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: PrimaryButton(
                label: 'Try FynnScan',
                icon: Icons.auto_awesome_rounded,
                onPressed: () =>
                    context.push(Routes.documentScan(state.stored!.id)),
              ),
            ),
          ],
        ),
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: staggered([
          if (state.error != null) ...[
            _Problem(
              message: state.error!,
              onDismiss: () =>
                  ref.read(addDocumentProvider.notifier).clearError(),
            ),
            const SizedBox(height: 18),
          ],

          switch (state.step) {
            AddDocumentStep.choose => _ChooseStep(state: state, limits: limits),
            AddDocumentStep.review => _ReviewStep(
              state: state,
              nameController: _nameController,
            ),
            AddDocumentStep.stored => _StoredStep(document: state.stored!),
          },
        ], step: const Duration(milliseconds: 55)),
      ),
    );
  }
}

/// Where the document comes from.
class _ChooseStep extends ConsumerWidget {
  const _ChooseStep({required this.state, required this.limits});

  final AddDocumentState state;
  final VaultLimits limits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'What would you like to add?'),
        _SourceTile(
          icon: Icons.folder_open_rounded,
          label: 'Choose from device',
          detail: 'PDFs and photos up to ${limits.maxSizeLabel}',
          busy: state.picking,
          onTap: () => ref.read(addDocumentProvider.notifier).choose(),
        ),
        const SizedBox(height: 10),
        // Not a button that looks like it works: FynnEdge has no camera
        // capture, and a tile that did nothing would be worse than saying so.
        const _SourceTile(
          icon: Icons.photo_camera_outlined,
          label: 'Take a photo',
          detail: 'Camera capture — coming soon',
          enabled: false,
        ),
        const SizedBox(height: 24),
        const _PrivacyNote(),
      ],
    );
  }
}

/// The file in hand, before anything is stored.
class _ReviewStep extends ConsumerWidget {
  const _ReviewStep({required this.state, required this.nameController});

  final AddDocumentState state;
  final TextEditingController nameController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picked = state.picked!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Check this over'),
        FynnCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Column(
            children: [
              DetailRow(label: 'File', value: picked.fileName),
              const HairLine(),
              DetailRow(label: 'Size', value: picked.sizeLabel),
              const HairLine(),
              DetailRow(
                label: 'Format',
                value: picked.extension.isEmpty
                    ? picked.mimeType
                    : picked.extension.toUpperCase(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        const SectionHeader(title: 'What is it?'),
        _TypePicker(
          selected: state.type,
          onSelect: (type) =>
              ref.read(addDocumentProvider.notifier).setType(type),
        ),
        const SizedBox(height: 22),

        const SectionHeader(
          title: 'Give it a name',
          subtitle: 'Optional — how you will recognise it later',
        ),
        FynnCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: nameController,
            style: const TextStyle(
              fontSize: 14.5,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: picked.fileName,
              hintStyle: const TextStyle(color: AppColors.textTertiary),
            ),
          ),
        ),
        const SizedBox(height: 22),

        const _PrivacyNote(),
      ],
    );
  }
}

/// Stored, and what that does and does not mean.
class _StoredStep extends StatelessWidget {
  const _StoredStep({required this.document});
  final VaultDocument document;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.mint.withValues(alpha: 0.12),
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            size: 25,
            color: AppColors.mint,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Document stored securely',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '${document.name} is in your FynnVault. Only you can open it.',
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.55,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        FynnCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Column(
            children: [
              DetailRow(label: 'Filed under', value: document.category.label),
              const HairLine(),
              DetailRow(label: 'Size', value: document.sizeLabel),
              const HairLine(),
              // Stored. Nothing else has happened to it.
              const DetailRow(label: 'Status', value: 'Stored'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _PrivacyNote(),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.label,
    required this.detail,
    this.onTap,
    this.busy = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback? onTap;
  final bool busy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colour = enabled ? AppColors.textPrimary : AppColors.textTertiary;

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: GestureDetector(
        onTap: enabled && !busy ? onTap : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: enabled ? AppColors.border : AppColors.borderSoft,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: colour),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: colour,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.mint,
                  ),
                )
              else if (enabled)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypePicker extends StatelessWidget {
  const _TypePicker({required this.selected, required this.onSelect});

  final DocumentCategory selected;
  final ValueChanged<DocumentCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        for (final category in DocumentCategory.values)
          GestureDetector(
            onTap: () => onSelect(category),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                color: category == selected
                    ? AppColors.mint.withValues(alpha: 0.13)
                    : AppColors.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppTheme.rSm),
                border: Border.all(
                  color: category == selected
                      ? AppColors.mint.withValues(alpha: 0.5)
                      : AppColors.border,
                ),
              ),
              child: Text(
                category.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: category == selected
                      ? AppColors.mint
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// What storing a document does, and what it does not.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        color: AppColors.surface.withValues(alpha: 0.4),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.mint),
              SizedBox(width: 9),
              Text(
                'What happens to it',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 11),
          _Point(
            'FynnVault stores your document privately in your FynnEdge '
            'account. Only you can open it.',
          ),
          _Point(
            'Nothing reads it. FynnEdge is not connected to a '
            'document-reading service.',
          ),
          _Point(
            'Nothing is verified, and nothing is sent to a provider — '
            'adding a document does not share it.',
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Icon(Icons.circle, size: 4, color: AppColors.textTertiary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Something the customer needs to know about, stated plainly.
class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 16),
            color: AppColors.textTertiary,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
