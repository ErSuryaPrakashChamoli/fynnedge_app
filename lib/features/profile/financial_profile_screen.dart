import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/utils/error_text.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/user.dart';
import '../fynnlab/widgets/calc_inputs.dart';
import 'financial_profile_controller.dart';

/// Screen 25 — the numbers everything else is calculated from, editable.
///
/// The screen holds no business state: it renders FinancialProfileState and
/// sends edits back to the controller. It never touches a repository or HTTP.
class FinancialProfileScreen extends ConsumerWidget {
  const FinancialProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(financialProfileControllerProvider);
    final controller = ref.read(financialProfileControllerProvider.notifier);

    ref.listen(financialProfileControllerProvider, (previous, next) {
      if (next.savedAt != null && next.savedAt != previous?.savedAt) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 17,
                    color: AppColors.mint,
                  ),
                  SizedBox(width: 10),
                  Text('Financial profile saved.'),
                ],
              ),
              duration: const Duration(seconds: 2),
            ),
          );
      }
    });

    return FynnScaffold(
      title: 'Financial Profile',
      subtitle: 'Everything else is calculated from this',
      padHorizontal: false,
      bottomBar: state.canSave || state.saving
          ? PrimaryButton(
              label: 'Save changes',
              loading: state.saving,
              // Null while saving, so a second tap cannot start a second
              // request.
              onPressed: state.saving ? null : controller.save,
            )
          : null,
      child: _Body(state: state, controller: controller),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.controller});

  final FinancialProfileState state;
  final FinancialProfileController controller;

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.saved == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: LoadingList(items: 4, itemHeight: 90),
      );
    }

    if (state.loadError != null && state.saved == null) {
      return ErrorState(
        message: messageForLoad(state.loadError!),
        onRetry: controller.load,
      );
    }

    final profile = state.current;
    if (profile == null) {
      return EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Nothing here yet',
        message:
            'Tell us what you earn and spend, and every calculation in '
            'FynnEdge starts working from your real position.',
        actionLabel: 'Get started',
        onAction: () =>
            controller.edit(const FinancialProfile(monthlyIncome: 50000)),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: staggered([
        if (state.saveError != null) ...[
          _SaveFailed(
            message: state.saveError!,
            onRetry: state.saving ? null : controller.save,
          ),
          const SizedBox(height: 18),
        ],

        _SummaryStrip(profile: profile, stale: state.hasUnsavedChanges),
        const SizedBox(height: 24),

        const SectionHeader(title: 'Income'),
        _Field(
          error: state.fieldErrors['monthly_income'],
          child: SliderInput(
            label: 'Monthly income',
            helper: 'Take-home, after tax',
            value: profile.monthlyIncome,
            min: 0,
            max: 1000000,
            step: 5000,
            onChanged: (v) =>
                controller.edit(profile.copyWith(monthlyIncome: v)),
          ),
        ),
        const SizedBox(height: 20),

        const SectionHeader(title: 'Expenses'),
        _Field(
          error: state.fieldErrors['monthly_expenses'],
          child: SliderInput(
            label: 'Monthly expenses',
            helper: 'Rent, bills, food, everything recurring',
            value: profile.monthlyExpenses,
            min: 0,
            max: 500000,
            step: 2500,
            accent: AppColors.blue,
            onChanged: (v) =>
                controller.edit(profile.copyWith(monthlyExpenses: v)),
          ),
        ),
        const SizedBox(height: 20),

        const SectionHeader(title: 'Existing loans'),
        _Field(
          error: state.fieldErrors['existing_emi'],
          child: SliderInput(
            label: 'Current EMI',
            helper: 'Total across every running loan',
            value: profile.existingEmi,
            min: 0,
            max: 300000,
            step: 1000,
            accent: AppColors.warning,
            onChanged: (v) => controller.edit(profile.copyWith(existingEmi: v)),
          ),
        ),
        const SizedBox(height: 20),

        const SectionHeader(title: 'Other obligations'),
        _Field(
          error: state.fieldErrors['other_obligations'],
          child: SliderInput(
            label: 'Other monthly commitments',
            helper:
                'Rent, fees, family support — anything committed that is '
                'not an EMI',
            value: profile.otherObligations,
            min: 0,
            max: 300000,
            step: 1000,
            accent: AppColors.violet,
            onChanged: (v) =>
                controller.edit(profile.copyWith(otherObligations: v)),
          ),
        ),
        const SizedBox(height: 20),

        const SectionHeader(title: 'Savings'),
        _Field(
          error: state.fieldErrors['savings'],
          child: SliderInput(
            label: 'Approximate savings',
            helper: 'Cash you could reach within a week',
            value: profile.savings,
            min: 0,
            max: 5000000,
            step: 10000,
            onChanged: (v) => controller.edit(profile.copyWith(savings: v)),
          ),
        ),
        const SizedBox(height: 20),

        const SectionHeader(title: 'Employment'),
        _Field(
          error: state.fieldErrors['employment_type'],
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in EmploymentType.values)
                _EmploymentChip(
                  type: type,
                  selected: profile.employment == type,
                  onTap: () =>
                      controller.edit(profile.copyWith(employment: type)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        if (state.hasUnsavedChanges)
          Center(
            child: GhostButton(
              label: 'Discard changes',
              color: AppColors.textTertiary,
              onPressed: controller.discardChanges,
            ),
          ),
        const SizedBox(height: 6),
        const Text(
          'These figures stay on your profile. They are shared with a lender '
          'only when you submit a specific application.',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.55,
            color: AppColors.textTertiary,
          ),
        ),
      ], step: const Duration(milliseconds: 50)),
    );
  }
}

/// Wraps an input so a server-reported error appears against the field the
/// server actually named.
class _Field extends StatelessWidget {
  const _Field({required this.child, this.error});

  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      borderColor: error == null
          ? null
          : AppColors.danger.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          if (error != null) ...[
            const SizedBox(height: 4),
            Row(
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
                    error!,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SaveFailed extends StatelessWidget {
  const _SaveFailed({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 13, 13),
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
            size: 17,
            color: AppColors.danger,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Not saved',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Your changes are still here.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (onRetry != null) GhostButton(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

class _EmploymentChip extends StatelessWidget {
  const _EmploymentChip({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final EmploymentType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.mint.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          border: Border.all(
            color: selected
                ? AppColors.mint.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        child: Text(
          type.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.mint : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Live derived figures — the point of editing is to watch these move.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.profile, required this.stale});

  final FinancialProfile profile;

  /// True while the figures reflect unsaved edits rather than the server.
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final healthy = profile.emiRatio < 40;

    return FynnCard(
      gradient: AppColors.surfaceGradient,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ResultFigure(
                  label: 'Surplus',
                  value: Fmt.money(profile.surplus),
                  color: profile.surplus > 0
                      ? AppColors.mint
                      : AppColors.danger,
                ),
              ),
              Container(width: 1, height: 40, color: AppColors.border),
              const SizedBox(width: 16),
              Expanded(
                child: ResultFigure(
                  label: 'EMI ratio',
                  value: '${profile.emiRatio.round()}%',
                  color: healthy ? AppColors.textPrimary : AppColors.warning,
                  caption: healthy ? 'Healthy' : 'Getting tight',
                ),
              ),
              Container(width: 1, height: 40, color: AppColors.border),
              const SizedBox(width: 16),
              Expanded(
                child: ResultFigure(
                  label: 'Cover',
                  value: Fmt.monthsCovered(profile.emergencyMonths),
                  caption: 'of outgoings',
                ),
              ),
            ],
          ),
          if (stale) ...[
            const SizedBox(height: 14),
            const HairLine(),
            const SizedBox(height: 11),
            Row(
              children: [
                const Icon(
                  Icons.edit_note_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Unsaved — save to confirm these figures',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
