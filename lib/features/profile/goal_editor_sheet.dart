import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/labeled_field.dart';
import '../../core/widgets/money_field.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/goal.dart';
import '../../data/models/intent.dart';
import 'goals_controller.dart';

/// Creates or edits one goal.
///
/// A sheet rather than a screen: the customer is mid-task on Goals, and a
/// full-page form would turn a financial product into an admin console.
class GoalEditorSheet extends ConsumerStatefulWidget {
  const GoalEditorSheet({super.key, this.existing});

  /// Null when creating.
  final Goal? existing;

  static Future<void> show(BuildContext context, {Goal? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgElevated,
      builder: (_) => GoalEditorSheet(existing: existing),
    );
  }

  @override
  ConsumerState<GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends ConsumerState<GoalEditorSheet> {
  late Goal _draft = widget.existing ?? _blankGoal();
  late final _title = TextEditingController(text: _draft.title);

  bool get _isEdit => widget.existing != null;

  static Goal _blankGoal() => Goal(
    id: '',
    title: '',
    category: GoalCategory.business,
    targetAmount: 0,
    targetDate: DateTime.now().add(const Duration(days: 365)),
  );

  @override
  void initState() {
    super.initState();
    // A previous attempt's errors must not greet the next one.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(goalsControllerProvider.notifier).clearErrors(),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _edit(Goal next) {
    setState(() => _draft = next);
    ref.read(goalsControllerProvider.notifier).clearErrors();
  }

  /// Local checks only, for immediate feedback. The backend remains the
  /// authority and its errors are shown against the same fields.
  bool get _looksComplete =>
      _title.text.trim().length >= 2 && _draft.targetAmount >= 1;

  Future<void> _submit() async {
    final controller = ref.read(goalsControllerProvider.notifier);
    final goal = _draft.copyWith(title: _title.text.trim());

    final result = _isEdit
        ? await controller.update(goal)
        : await controller.create(goal);

    if (!mounted) return;

    if (result == GoalActionResult.success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_isEdit ? 'Goal updated.' : 'Goal created.'),
            duration: const Duration(seconds: 2),
          ),
        );
    }
    // On failure the sheet stays open; the state carries the errors.
  }

  Future<void> _confirmDelete() async {
    final goal = widget.existing;
    if (goal == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
        ),
        title: const Text(
          'Delete this goal?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '"${goal.title}" and its progress will be removed. This cannot be '
          'undone.',
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await ref
        .read(goalsControllerProvider.notifier)
        .delete(goal.id);

    if (!mounted) return;
    if (result == GoalActionResult.success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Goal deleted.')));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.targetDate.isAfter(now) ? _draft.targetDate : now,
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 30)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          datePickerTheme: const DatePickerThemeData(
            backgroundColor: AppColors.surfaceAlt,
            surfaceTintColor: Colors.transparent,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) _edit(_draft.copyWith(targetDate: picked));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(goalsControllerProvider);
    final t = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEdit ? 'Edit goal' : 'New goal', style: t.headlineSmall),
            const SizedBox(height: 6),
            Text(
              _isEdit
                  ? 'Change the target and we will recalculate what it takes.'
                  : 'Name it, set a target and a date. We will tell you the '
                        'monthly number.',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 22),

            if (state.actionError != null) ...[
              _ActionError(message: state.actionError!, onRetry: _submit),
              const SizedBox(height: 16),
            ],

            LabeledField(
              label: 'What are you saving for',
              controller: _title,
              icon: Icons.flag_outlined,
              hint: 'Business Expansion',
              capitalization: TextCapitalization.words,
              onChanged: (_) => setState(
                () => ref.read(goalsControllerProvider.notifier).clearErrors(),
              ),
              bottomSpacing: state.fieldErrors['title'] == null ? 18 : 4,
            ),
            if (state.fieldErrors['title'] != null)
              _FieldError(state.fieldErrors['title']!),

            const _Caption('CATEGORY'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in GoalCategory.values)
                  _CategoryChip(
                    category: category,
                    selected: _draft.category == category,
                    onTap: () => _edit(_draft.copyWith(category: category)),
                  ),
              ],
            ),
            if (state.fieldErrors['category'] != null)
              _FieldError(state.fieldErrors['category']!),
            const SizedBox(height: 20),

            MoneyField(
              label: 'Target amount',
              value: _draft.targetAmount,
              error: state.fieldErrors['target_amount'],
              onChanged: (v) => _edit(_draft.copyWith(targetAmount: v)),
            ),
            const SizedBox(height: 20),

            MoneyField(
              label: 'Already saved',
              value: _draft.savedAmount,
              helper: 'Leave at zero if you are starting from scratch',
              error: state.fieldErrors['saved_amount'],
              onChanged: (v) => _edit(_draft.copyWith(savedAmount: v)),
            ),
            const SizedBox(height: 20),

            const _Caption('TARGET DATE'),
            const SizedBox(height: 8),
            _DateRow(
              date: _draft.targetDate,
              error: state.fieldErrors['target_date'],
              onTap: _pickDate,
            ),
            const SizedBox(height: 20),

            // The point of the screen: what this goal asks of them monthly.
            _MonthlyPreview(draft: _draft),
            const SizedBox(height: 22),

            PrimaryButton(
              label: _isEdit ? 'Save changes' : 'Create goal',
              loading: state.busy,
              onPressed: (!_looksComplete || state.busy) ? null : _submit,
            ),
            if (_isEdit) ...[
              const SizedBox(height: 4),
              Center(
                child: GhostButton(
                  label: 'Delete goal',
                  color: AppColors.danger,
                  onPressed: state.busy ? null : _confirmDelete,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
      color: AppColors.textTertiary,
    ),
  );
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 14,
          color: AppColors.danger,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.danger,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ActionError extends StatelessWidget {
  const _ActionError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.26)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 16,
            color: AppColors.danger,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Nothing was lost — try again.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          GhostButton(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final GoalCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.violet.withValues(alpha: 0.13)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          border: Border.all(
            color: selected
                ? AppColors.violet.withValues(alpha: 0.55)
                : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              category.icon,
              size: 14,
              color: selected ? AppColors.violet : AppColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Text(
              category.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.date, required this.onTap, this.error});

  final DateTime date;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.rMd),
              border: Border.all(
                color: error == null ? AppColors.border : AppColors.danger,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.event_rounded,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    Fmt.date(date),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (error != null) _FieldError(error!),
      ],
    );
  }
}

/// The monthly number, computed locally while editing and clearly labelled as
/// an estimate until the server confirms it.
class _MonthlyPreview extends StatelessWidget {
  const _MonthlyPreview({required this.draft});

  final Goal draft;

  @override
  Widget build(BuildContext context) {
    if (draft.targetAmount < 1) return const SizedBox.shrink();

    // Derived locally: these figures describe values the server has not seen.
    final preview = draft.copyWith().withLocalDerived();

    return FynnCard(
      gradient: AppColors.surfaceGradient,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.mint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.trending_up_rounded,
              size: 17,
              color: AppColors.mint,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview.monthsRemaining <= 0
                      ? 'Pick a date in the future'
                      : '${Fmt.money(preview.monthlyRequired)} a month for '
                            '${preview.monthsRemaining} months',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Estimate — confirmed when you save',
                  style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
