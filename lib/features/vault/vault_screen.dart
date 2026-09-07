import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/document.dart';
import 'vault_controller.dart';
import '../../app/routes.dart';

/// Screen 21 — the customer's document locker, grouped by what each file is for.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  DocumentCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(documentsProvider);

    return FynnScaffold(
      title: 'FynnVault',
      subtitle: 'Your documents, stored once',
      padHorizontal: false,
      bottomBar: PrimaryButton(
        label: 'Upload Document',
        icon: Icons.upload_rounded,
        onPressed: () => context.push(Routes.scan),
      ),
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: LoadingList(items: 4, itemHeight: 68),
        ),
        error: (e, _) => ErrorState(
          message: messageForLoad(e),
          onRetry: () => ref.invalidate(documentsProvider),
        ),
        data: (docs) {
          final filtered = _filter == null
              ? docs
              : docs.where((d) => d.category == _filter);

          return Column(
            children: [
              _Filters(
                selected: _filter,
                counts: {
                  for (final c in DocumentCategory.values)
                    c: docs.where((d) => d.category == c).length,
                },
                onSelect: (c) => setState(() => _filter = c),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? EmptyState(
                        icon: Icons.folder_open_rounded,
                        title: _filter == null
                            ? 'Your vault is empty'
                            : 'Nothing filed under ${_filter!.label}',
                        message:
                            'Anything you add is stored against your '
                            'FynnEdge account, where only you can open it.',
                        actionLabel: 'Upload a document',
                        onAction: () => context.push(Routes.scan),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => Entrance(
                          delay: Duration(milliseconds: 45 * i),
                          child: _DocTile(doc: filtered.elementAt(i)),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final DocumentCategory? selected;
  final Map<DocumentCategory, int> counts;
  final ValueChanged<DocumentCategory?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _Chip(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final c in DocumentCategory.values)
            _Chip(
              label: '${c.label} (${counts[c] ?? 0})',
              selected: selected == c,
              onTap: () => onSelect(c),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.mint.withValues(alpha: 0.13)
                : AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppTheme.rSm),
            border: Border.all(
              color: selected
                  ? AppColors.mint.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.mint : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _DocTile extends ConsumerWidget {
  const _DocTile({required this.doc});
  final VaultDocument doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(vaultControllerProvider);
    final deleting = action.isDeleting(doc.id);

    return FynnCard(
      padding: const EdgeInsets.fromLTRB(15, 13, 8, 13),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              doc.isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  // Stored, when, and how big. Nothing about verification,
                  // because nothing has verified it.
                  '${doc.category.label} · ${doc.sizeLabel} · '
                  'Stored ${Fmt.date(doc.uploadedAt)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (deleting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textTertiary,
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
              color: AppColors.surfaceAlt,
              onSelected: (value) => switch (value) {
                'open' => _open(context, ref),
                'scan' => _scan(context),
                _ => _confirmDelete(context, ref),
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'open', child: Text('Open')),
                PopupMenuItem(value: 'scan', child: Text('FynnScan')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    );
  }

  /// FynnScan for this document. It will say that nothing can read it yet,
  /// which is the point: the route exists and tells the truth.
  Future<void> _scan(BuildContext context) async =>
      context.push(Routes.documentScan(doc.id));

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final bytes = await ref.read(vaultControllerProvider.notifier).open(doc.id);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          bytes == null
              ? 'That document could not be opened.'
              : '${doc.name} retrieved (${doc.sizeLabel}).',
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: const Text('Delete this document?'),
        content: Text(
          'The file is removed from FynnVault and cannot be recovered. '
          '${doc.name} will be gone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final ok = await ref.read(vaultControllerProvider.notifier).delete(doc.id);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Document deleted.' : 'That could not be deleted.'),
      ),
    );
  }
}
