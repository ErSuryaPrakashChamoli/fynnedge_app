import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/twin.dart';
import '../loans/loan_controller.dart';
import 'twin_controller.dart';

/// Screen 30 — FynnTwin.
///
/// It answers one question: if I make this decision, what happens to my
/// month? Every figure comes from the engine, and the screen says plainly
/// that a projection is not a prediction.
class TwinScreen extends ConsumerStatefulWidget {
  const TwinScreen({super.key, this.productId, this.amount, this.tenureMonths});

  /// Set when FynnTwin was opened from a loan the customer is looking at, so
  /// the screen starts on that loan instead of on its own defaults.
  final String? productId;
  final double? amount;
  final int? tenureMonths;

  @override
  ConsumerState<TwinScreen> createState() => _TwinScreenState();
}

class _TwinScreenState extends ConsumerState<TwinScreen> {
  @override
  void initState() {
    super.initState();

    final productId = widget.productId;
    if (productId == null) return;

    // After the first frame: the controller is read, not watched, and
    // seeding it during build would rebuild mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(twinControllerProvider.notifier)
          .presetLoan(
            productId: productId,
            amount: widget.amount,
            tenureMonths: widget.tenureMonths,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = ref.watch(twinCapabilitiesProvider);
    final state = ref.watch(twinControllerProvider);

    return FynnScaffold(
      title: 'FynnTwin',
      subtitle: 'What a decision would do to your month',
      padHorizontal: false,
      bottomBar: capabilities.value?.hasFinancialProfile == true
          ? PrimaryButton(
              label: state.running ? 'Working it out…' : 'Run the simulation',
              icon: Icons.play_arrow_rounded,
              loading: state.running,
              onPressed: state.canRun
                  ? () => ref.read(twinControllerProvider.notifier).run()
                  : null,
            )
          : null,
      child: capabilities.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: LoadingList(items: 3, itemHeight: 110),
        ),
        error: (e, _) => ErrorState(
          message: messageForLoad(e),
          onRetry: () => ref.invalidate(twinCapabilitiesProvider),
        ),
        data: (capabilities) => capabilities.hasFinancialProfile
            ? _Builder(state: state)
            // Nothing to project against, so nothing is projected.
            : const _NeedsProfile(),
      ),
    );
  }
}

class _NeedsProfile extends StatelessWidget {
  const _NeedsProfile();

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.insights_rounded,
    title: 'Add your figures first',
    message:
        'FynnTwin works from your income, spending and existing EMIs. '
        'Without them there is nothing to project.',
    actionLabel: 'Financial profile',
    onAction: () => context.push(Routes.financialProfile),
  );
}

class _Builder extends ConsumerWidget {
  const _Builder({required this.state});
  final TwinScreenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(twinControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      children: staggered([
        if (state.error != null) ...[
          _Problem(message: state.error!, onDismiss: controller.clearError),
          const SizedBox(height: 18),
        ],

        const SectionHeader(title: 'What would you like to try?'),
        for (final type in ScenarioType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _ScenarioTile(
              type: type,
              selected: state.type == type,
              onTap: () => controller.setType(type),
            ),
          ),
        const SizedBox(height: 22),

        const SectionHeader(
          title: 'Your assumptions',
          subtitle: 'Nothing is assumed on your behalf',
        ),
        _Assumptions(state: state, controller: controller),
        const SizedBox(height: 24),

        if (state.projection != null) ...[
          _Result(projection: state.projection!),
          // A simulation answers "what would this do". The decision itself
          // is FynnMirror's screen, and it opens on the same loan at the
          // same amount and term rather than on a different one.
          if (state.type == ScenarioType.loan && state.productId != null) ...[
            const SizedBox(height: 18),
            SecondaryButton(
              label: 'See the decision impact',
              icon: Icons.compare_arrows_rounded,
              onPressed: () {
                ref
                    .read(simulationInputsProvider.notifier)
                    .setFor(
                      productId: state.productId!,
                      amount: state.amount,
                      tenureMonths: state.tenureMonths,
                    );
                context.push(Routes.mirrorFor(state.productId!));
              },
            ),
          ],
        ] else
          const _NotYetRun(),
      ], step: const Duration(milliseconds: 55)),
    );
  }
}

class _ScenarioTile extends StatelessWidget {
  const _ScenarioTile({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final ScenarioType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.mint.withValues(alpha: 0.10)
              : AppColors.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border: Border.all(
            color: selected
                ? AppColors.mint.withValues(alpha: 0.45)
                : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              type.label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.mint : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              type.description,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The inputs for whichever scenario is selected.
class _Assumptions extends StatelessWidget {
  const _Assumptions({required this.state, required this.controller});

  final TwinScreenState state;
  final TwinController controller;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: switch (state.type) {
        ScenarioType.loan => Column(
          children: [
            _ProductPicker(
              selected: state.productId,
              onSelect: controller.setProduct,
            ),
            const SizedBox(height: 6),
            _Slider(
              label: 'Amount',
              value: Fmt.money(state.amount),
              current: state.amount,
              min: 100000,
              max: 5000000,
              step: 50000,
              onChanged: controller.setAmount,
            ),
            _Slider(
              label: 'Term',
              value: Fmt.months(state.tenureMonths),
              current: state.tenureMonths.toDouble(),
              min: 12,
              max: 84,
              step: 6,
              onChanged: (v) => controller.setTenure(v.round()),
            ),
          ],
        ),
        ScenarioType.expenseChange => _Slider(
          label: 'Change each month',
          value: Fmt.money(state.monthlyChange),
          current: state.monthlyChange,
          min: -20000,
          max: 40000,
          step: 1000,
          onChanged: controller.setMonthlyChange,
        ),
        ScenarioType.savingChange => Column(
          children: [
            _Slider(
              label: 'Set aside each month',
              value: Fmt.money(state.monthlyAmount),
              current: state.monthlyAmount,
              min: 1000,
              max: 50000,
              step: 1000,
              onChanged: controller.setMonthlyAmount,
            ),
            _Slider(
              label: 'For how long',
              value: Fmt.months(state.months),
              current: state.months.toDouble(),
              min: 1,
              max: 60,
              step: 1,
              onChanged: (v) => controller.setMonths(v.round()),
            ),
          ],
        ),
      },
    );
  }
}

class _ProductPicker extends StatelessWidget {
  const _ProductPicker({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Which product?',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Real catalogue products, at their published rates. No invented
            // lender, and no invented rate.
            for (final product in MockData.products)
              GestureDetector(
                onTap: () => onSelect(product.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: product.id == selected
                        ? AppColors.mint.withValues(alpha: 0.13)
                        : AppColors.surfaceHigh.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                    border: Border.all(
                      color: product.id == selected
                          ? AppColors.mint.withValues(alpha: 0.5)
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    '${product.lender} · '
                    '${Fmt.percent(product.interestRate)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: product.id == selected
                          ? AppColors.mint
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.current,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final String value;
  final double current;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Slider(
          value: current.clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) / step).round(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _NotYetRun extends StatelessWidget {
  const _NotYetRun();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      border: Border.all(color: AppColors.borderSoft),
    ),
    child: const Text(
      'Run the simulation and FynnTwin will show your month today beside '
      'your month under this scenario. Nothing is saved, and nothing is '
      'applied for.',
      style: TextStyle(
        fontSize: 12.5,
        height: 1.55,
        color: AppColors.textTertiary,
      ),
    ),
  );
}

/// Today beside the scenario, and what changes.
class _Result extends StatelessWidget {
  const _Result({required this.projection});
  final TwinProjection projection;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Today and under this scenario',
          subtitle: 'A projection, not a prediction',
        ),
        FynnCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            children: [
              const Row(
                children: [
                  SizedBox(width: 104),
                  Expanded(child: _Head('TODAY')),
                  Expanded(child: _Head('SCENARIO')),
                ],
              ),
              const SizedBox(height: 6),
              _Row(
                label: 'Monthly outgo',
                today: Fmt.money(projection.current.monthlyOutgo),
                after: Fmt.money(projection.projected.monthlyOutgo),
              ),
              _Row(
                label: 'Left over',
                today: Fmt.money(projection.current.surplus),
                after: Fmt.money(projection.projected.surplus),
                // A negative surplus is shown as what it is.
                afterColor: projection.projected.surplus < 0
                    ? AppColors.danger
                    : null,
              ),
              _Row(
                label: 'EMI share',
                today: Fmt.ratio(projection.current.emiRatio),
                after: Fmt.ratio(projection.projected.emiRatio),
                afterColor: projection.withinReference
                    ? null
                    : AppColors.warning,
              ),
              _Row(
                label: 'Savings cover',
                // Trimmed to two decimals, the same shape the observation
                // below uses: one figure must not appear at two precisions
                // on one screen.
                today: Fmt.monthsCovered(projection.current.emergencyMonths),
                after: Fmt.monthsCovered(projection.projected.emergencyMonths),
              ),
              if (projection.currentScore != null) ...[
                const SizedBox(height: 4),
                const HairLine(),
                const SizedBox(height: 4),
                _Row(
                  label: 'FynnScore',
                  hint: 'Simulated',
                  today: '${projection.currentScore}',
                  after: '${projection.projectedScore}',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        if (projection.loan != null) ...[
          const SectionHeader(title: 'The loan being modelled'),
          FynnCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Column(
              children: [
                DetailRow(label: 'Provider', value: projection.loan!.lender),
                const HairLine(),
                DetailRow(
                  label: 'Monthly EMI',
                  hint: 'At ${Fmt.percent(projection.loan!.interestRate)}',
                  value: Fmt.money(projection.loan!.emi),
                  emphasise: true,
                ),
                const HairLine(),
                DetailRow(
                  label: 'Total repayment',
                  value: Fmt.money(
                    projection.loan!.totalPayable +
                        projection.loan!.processingFee,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        const SectionHeader(title: 'What to think about'),
        for (final observation in projection.observations)
          _Observation(observation: observation),

        const SizedBox(height: 16),
        Text(
          projection.disclaimer,
          style: const TextStyle(
            fontSize: 11.5,
            height: 1.5,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.right,
    style: const TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.9,
      color: AppColors.textTertiary,
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.today,
    required this.after,
    this.hint,
    this.afterColor,
  });

  final String label;
  final String today;
  final String after;
  final String? hint;
  final Color? afterColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              today,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              after,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: afterColor ?? AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Observation extends StatelessWidget {
  const _Observation({required this.observation});
  final TwinObservation observation;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = switch (observation.severity) {
      TwinObservation.serious => (
        Icons.error_outline_rounded,
        AppColors.danger,
      ),
      TwinObservation.caution => (
        Icons.warning_amber_rounded,
        AppColors.warning,
      ),
      _ => (Icons.info_outline_rounded, AppColors.textTertiary),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: colour),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              observation.detail,
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
}

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
