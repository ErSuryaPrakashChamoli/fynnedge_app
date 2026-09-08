import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../data/models/support.dart';
import 'support_controller.dart';

/// Asking for help, with what the customer was doing already attached.
///
/// The context arrives in the route rather than being gathered here, so
/// support opened from an application knows which application without the
/// customer typing a reference. What travels is a type and an id; the
/// server checks both belong to them before anything is attached.
class SupportRequestScreen extends ConsumerStatefulWidget {
  const SupportRequestScreen({
    super.key,
    this.category,
    this.contextType,
    this.contextId,
    this.suggestedSubject,
  });

  final String? category;
  final String? contextType;
  final String? contextId;
  final String? suggestedSubject;

  @override
  ConsumerState<SupportRequestScreen> createState() =>
      _SupportRequestScreenState();
}

class _SupportRequestScreenState extends ConsumerState<SupportRequestScreen> {
  late final TextEditingController _subject = TextEditingController(
    text: widget.suggestedSubject ?? '',
  );
  final TextEditingController _description = TextEditingController();

  String? _category;
  bool _sending = false;
  String? _error;

  /// One key for one attempt at this form.
  ///
  /// Stable across taps of the button, so a double tap is one request —
  /// the server recognises it and returns the case it already made.
  late final String _idempotencyKey =
      'support-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _category = widget.category;
  }

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _category != null &&
      _subject.text.trim().length >= 3 &&
      _description.text.trim().length >= 10;

  Future<void> _send() async {
    if (!_canSend || _sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    final created = await ref
        .read(supportControllerProvider.notifier)
        .create(
          SupportRequestDraft(
            category: _category!,
            subject: _subject.text.trim(),
            description: _description.text.trim(),
            contextType: widget.contextType,
            contextId: widget.contextId,
            idempotencyKey: _idempotencyKey,
          ),
        );

    if (!mounted) return;

    if (created == null) {
      setState(() {
        _sending = false;
        _error =
            'We could not send that just now. Please check your connection '
            'and try again.';
      });
      return;
    }

    // Straight to the request, so the first thing they see is that it
    // exists and what its number is.
    context.pushReplacement(Routes.supportCase(created.id));
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(supportCategoriesProvider);
    final t = Theme.of(context).textTheme;

    return FynnScaffold(
      title: 'New request',
      child: categories.when(
        loading: () => const LoadingList(items: 3, itemHeight: 64),
        error: (e, _) => ErrorState(
          message: messageForLoad(e),
          onRetry: () => ref.invalidate(supportCategoriesProvider),
        ),
        data: (options) => ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 28),
          children: [
            if (widget.contextType != null) ...[
              _AttachedContext(
                type: widget.contextType!,
                reference: widget.contextId,
              ),
              const SizedBox(height: 18),
            ],

            Text('What is it about?', style: t.titleMedium),
            const SizedBox(height: 10),
            _CategoryPicker(
              options: options,
              selected: _category,
              onChanged: (id) => setState(() => _category = id),
            ),

            const SizedBox(height: 22),
            Text('Give it a short title', style: t.titleMedium),
            const SizedBox(height: 8),
            _Field(
              controller: _subject,
              hint: 'Help with application submission status',
              maxLength: 160,
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 18),
            Text('Tell us what you need', style: t.titleMedium),
            const SizedBox(height: 8),
            _Field(
              controller: _description,
              hint: 'Describe what happened and what you would like us to do.',
              maxLines: 6,
              maxLength: 4000,
              onChanged: (_) => setState(() {}),
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
              ),
            ],

            const SizedBox(height: 22),
            PrimaryButton(
              label: 'Send request',
              loading: _sending,
              onPressed: _canSend ? _send : null,
            ),
            const SizedBox(height: 12),
            Text(
              // No response time, because nobody has agreed one. What the
              // customer is promised is a record and a reference.
              'We will record your request and give you a reference. You can '
              'add more information to it at any time.',
              style: t.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachedContext extends StatelessWidget {
  const _AttachedContext({required this.type, this.reference});

  final String type;
  final String? reference;

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      'application' => 'This is about an application',
      'document' => 'This is about a document',
      'goal' => 'This is about a goal',
      'fynnscore' => 'This is about your FynnScore',
      'fynnai' => 'This is about FynnAI',
      'vault' => 'This is about FynnVault',
      'privacy' => 'This is about privacy and consent',
      _ => 'We will attach where you came from',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, size: 17, color: AppColors.blue),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<SupportCategoryOption> options;
  final String? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          Semantics(
            button: true,
            selected: option.id == selected,
            child: GestureDetector(
              onTap: () => onChanged(option.id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: option.id == selected
                      ? AppColors.mint.withValues(alpha: 0.14)
                      : AppColors.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(AppTheme.rSm),
                  border: Border.all(
                    color: option.id == selected
                        ? AppColors.mint.withValues(alpha: 0.45)
                        : AppColors.border,
                  ),
                ),
                child: Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: option.id == selected
                        ? AppColors.mint
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.maxLines = 1,
    this.maxLength,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        hintStyle: const TextStyle(
          fontSize: 13,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}
