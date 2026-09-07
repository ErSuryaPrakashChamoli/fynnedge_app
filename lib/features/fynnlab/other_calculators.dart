import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/surfaces.dart';
import '../profile/profile_controller.dart';
import 'widgets/calc_inputs.dart';

/// Screen 16b — how much can I safely borrow?
class AffordabilityScreen extends ConsumerStatefulWidget {
  const AffordabilityScreen({super.key});

  @override
  ConsumerState<AffordabilityScreen> createState() => _AffordabilityState();
}

class _AffordabilityState extends ConsumerState<AffordabilityScreen> {
  double? _income;
  double? _existing;
  double _rate = 13.25;
  double _tenure = 60;

  @override
  Widget build(BuildContext context) {
    final finance = ref.watch(financeServiceProvider);
    final profile = ref.watch(financialProfileProvider).value;

    final income = _income ?? profile?.monthlyIncome ?? 100000;
    final existing = _existing ?? profile?.existingEmi ?? 0;

    final headroom = finance.emiHeadroom(
      monthlyIncome: income,
      existingEmi: existing,
    );
    final principal = finance.affordablePrincipal(
      comfortableEmi: headroom,
      annualRate: _rate,
      tenureMonths: _tenure.round(),
    );

    return FynnScaffold(
      title: 'Loan Affordability',
      padHorizontal: false,
      glowPrimary: AppColors.blue,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: staggered([
          FynnCard(
            gradient: AppColors.surfaceGradient,
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ResultFigure(
                  label: 'You could borrow up to',
                  value: Fmt.compactMoney(principal),
                  large: true,
                  color: AppColors.blue,
                  caption:
                      'at ${Fmt.percent(_rate)} over '
                      '${Fmt.months(_tenure.round())}',
                ),
                const SizedBox(height: 18),
                const HairLine(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ResultFigure(
                        label: 'Headroom / month',
                        value: Fmt.money(headroom),
                      ),
                    ),
                    Expanded(
                      child: ResultFigure(
                        label: 'Ceiling used',
                        value: '45% of income',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          FynnCard(
            child: Column(
              children: [
                SliderInput(
                  label: 'Monthly income',
                  value: income,
                  min: 20000,
                  max: 1000000,
                  step: 5000,
                  accent: AppColors.blue,
                  onChanged: (v) => setState(() => _income = v),
                ),
                SliderInput(
                  label: 'Existing EMIs',
                  value: existing,
                  min: 0,
                  max: 200000,
                  step: 1000,
                  accent: AppColors.warning,
                  onChanged: (v) => setState(() => _existing = v),
                ),
                SliderInput(
                  label: 'Expected rate',
                  value: _rate,
                  min: 6,
                  max: 24,
                  step: 0.05,
                  format: (v) => Fmt.percent(v),
                  onChanged: (v) => setState(() => _rate = v),
                ),
                SliderInput(
                  label: 'Tenure',
                  value: _tenure,
                  min: 12,
                  max: 360,
                  step: 6,
                  format: (v) => Fmt.months(v.round()),
                  onChanged: (v) => setState(() => _tenure = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const VerdictBar(
            tone: AppColors.warning,
            icon: Icons.info_outline_rounded,
            text:
                'This is a ceiling, not a recommendation. Borrowing to the '
                'limit leaves nothing for the months that go wrong — most '
                'people are better served well below it.',
          ),
        ], step: const Duration(milliseconds: 55)),
      ),
    );
  }
}

/// Screen 16c — what a lump sum saves.
class PrepaymentScreen extends ConsumerStatefulWidget {
  const PrepaymentScreen({super.key});

  @override
  ConsumerState<PrepaymentScreen> createState() => _PrepaymentState();
}

class _PrepaymentState extends ConsumerState<PrepaymentScreen> {
  double _principal = 1000000;
  double _rate = 13.25;
  double _tenure = 60;
  double _lumpSum = 200000;
  double _after = 12;

  @override
  Widget build(BuildContext context) {
    final finance = ref.watch(financeServiceProvider);
    final r = finance.prepayment(
      principal: _principal,
      annualRate: _rate,
      tenureMonths: _tenure.round(),
      lumpSum: _lumpSum,
      afterMonths: _after.round(),
    );

    return FynnScaffold(
      title: 'Prepayment',
      padHorizontal: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: staggered([
          FynnCard(
            gradient: AppColors.surfaceGradient,
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ResultFigure(
                  label: 'Interest you would save',
                  value: Fmt.money(r.interestSaved),
                  large: true,
                  color: AppColors.mint,
                ),
                const SizedBox(height: 18),
                const HairLine(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ResultFigure(
                        label: 'Loan ends earlier by',
                        value: Fmt.months(r.monthsSaved),
                      ),
                    ),
                    Expanded(
                      child: ResultFigure(
                        label: 'New tenure',
                        value: Fmt.months(r.newTenureMonths),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          FynnCard(
            child: Column(
              children: [
                SliderInput(
                  label: 'Original loan',
                  value: _principal,
                  min: 100000,
                  max: 10000000,
                  step: 50000,
                  onChanged: (v) => setState(() => _principal = v),
                ),
                SliderInput(
                  label: 'Interest rate',
                  value: _rate,
                  min: 6,
                  max: 24,
                  step: 0.05,
                  accent: AppColors.warning,
                  format: (v) => Fmt.percent(v),
                  onChanged: (v) => setState(() => _rate = v),
                ),
                SliderInput(
                  label: 'Original tenure',
                  value: _tenure,
                  min: 12,
                  max: 360,
                  step: 6,
                  accent: AppColors.blue,
                  format: (v) => Fmt.months(v.round()),
                  onChanged: (v) => setState(() => _tenure = v),
                ),
                SliderInput(
                  label: 'Lump sum',
                  value: _lumpSum,
                  min: 10000,
                  max: 2000000,
                  step: 10000,
                  onChanged: (v) => setState(() => _lumpSum = v),
                ),
                SliderInput(
                  label: 'Paid after',
                  value: _after,
                  min: 1,
                  max: _tenure - 1,
                  step: 1,
                  accent: AppColors.violet,
                  format: (v) => Fmt.months(v.round()),
                  onChanged: (v) => setState(() => _after = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const VerdictBar(
            tone: AppColors.mint,
            icon: Icons.tips_and_updates_outlined,
            text:
                'This keeps your EMI the same and shortens the loan, which '
                'saves the most interest. Check your lender allows '
                'prepayment without a charge first.',
          ),
        ], step: const Duration(milliseconds: 55)),
      ),
    );
  }
}

/// Screen 16d — is moving the loan worth it?
class BalanceTransferScreen extends ConsumerStatefulWidget {
  const BalanceTransferScreen({super.key});

  @override
  ConsumerState<BalanceTransferScreen> createState() => _BalanceTransferState();
}

class _BalanceTransferState extends ConsumerState<BalanceTransferScreen> {
  double _outstanding = 800000;
  double _currentRate = 14.5;
  double _newRate = 11.9;
  double _remaining = 42;
  double _fee = 1.0;

  @override
  Widget build(BuildContext context) {
    final finance = ref.watch(financeServiceProvider);
    final r = finance.balanceTransfer(
      outstanding: _outstanding,
      currentRate: _currentRate,
      newRate: _newRate,
      remainingMonths: _remaining.round(),
      transferFeePercent: _fee,
    );

    return FynnScaffold(
      title: 'Balance Transfer',
      padHorizontal: false,
      glowPrimary: AppColors.violet,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: staggered([
          FynnCard(
            gradient: AppColors.surfaceGradient,
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ResultFigure(
                  label: r.isWorthIt ? 'You would save' : 'You would lose',
                  value: Fmt.money(r.netSaving.abs()),
                  large: true,
                  color: r.isWorthIt ? AppColors.mint : AppColors.danger,
                  caption: 'net of the transfer fee, over the remaining term',
                ),
                const SizedBox(height: 18),
                const HairLine(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ResultFigure(
                        label: 'EMI now',
                        value: Fmt.money(r.currentEmi),
                      ),
                    ),
                    Expanded(
                      child: ResultFigure(
                        label: 'EMI after',
                        value: Fmt.money(r.newEmi),
                        color: AppColors.violet,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ResultFigure(
                        label: 'Transfer fee',
                        value: Fmt.money(r.transferFee),
                      ),
                    ),
                    Expanded(
                      child: ResultFigure(
                        label: 'Breaks even in',
                        value: r.breakEvenMonths < 0
                            ? 'Never'
                            : Fmt.months(r.breakEvenMonths),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          FynnCard(
            child: Column(
              children: [
                SliderInput(
                  label: 'Outstanding balance',
                  value: _outstanding,
                  min: 50000,
                  max: 10000000,
                  step: 50000,
                  accent: AppColors.violet,
                  onChanged: (v) => setState(() => _outstanding = v),
                ),
                SliderInput(
                  label: 'Your current rate',
                  value: _currentRate,
                  min: 6,
                  max: 30,
                  step: 0.05,
                  accent: AppColors.warning,
                  format: (v) => Fmt.percent(v),
                  onChanged: (v) => setState(() => _currentRate = v),
                ),
                SliderInput(
                  label: 'New rate offered',
                  value: _newRate,
                  min: 6,
                  max: 30,
                  step: 0.05,
                  format: (v) => Fmt.percent(v),
                  onChanged: (v) => setState(() => _newRate = v),
                ),
                SliderInput(
                  label: 'Months remaining',
                  value: _remaining,
                  min: 6,
                  max: 300,
                  step: 1,
                  accent: AppColors.blue,
                  format: (v) => Fmt.months(v.round()),
                  onChanged: (v) => setState(() => _remaining = v),
                ),
                SliderInput(
                  label: 'Transfer fee',
                  value: _fee,
                  min: 0,
                  max: 4,
                  step: 0.1,
                  format: (v) => Fmt.percent(v, decimals: 1),
                  onChanged: (v) => setState(() => _fee = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          VerdictBar(
            tone: r.isWorthIt ? AppColors.mint : AppColors.danger,
            icon: r.isWorthIt
                ? Icons.check_circle_outline_rounded
                : Icons.do_not_disturb_on_outlined,
            text: r.isWorthIt
                ? 'Worth doing on these numbers. Confirm your existing '
                      'lender has no foreclosure charge before you move.'
                : 'Not worth it as entered. The fee and the rate difference '
                      'do not pay for themselves over the time remaining.',
          ),
        ], step: const Duration(milliseconds: 55)),
      ),
    );
  }
}

/// Screen 16e — how long would savings last?
class EmergencyFundScreen extends ConsumerStatefulWidget {
  const EmergencyFundScreen({super.key});

  @override
  ConsumerState<EmergencyFundScreen> createState() => _EmergencyFundState();
}

class _EmergencyFundState extends ConsumerState<EmergencyFundScreen> {
  double? _expenses;
  double? _emi;
  double? _savings;
  double _target = 6;

  @override
  Widget build(BuildContext context) {
    final finance = ref.watch(financeServiceProvider);
    final p = ref.watch(financialProfileProvider).value;

    final expenses = _expenses ?? p?.monthlyExpenses ?? 40000;
    final emi = _emi ?? p?.existingEmi ?? 20000;
    final savings = _savings ?? p?.savings ?? 180000;

    final r = finance.emergencyFund(
      monthlyExpenses: expenses,
      existingEmi: emi,
      savings: savings,
      targetMonths: _target.round(),
    );
    final healthy = r.monthsCovered >= _target;

    return FynnScaffold(
      title: 'Emergency Fund',
      padHorizontal: false,
      glowPrimary: AppColors.warning,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: staggered([
          FynnCard(
            gradient: AppColors.surfaceGradient,
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ResultFigure(
                  label: 'Your savings would last',
                  value: Fmt.monthsCovered(r.monthsCovered),
                  large: true,
                  color: healthy ? AppColors.mint : AppColors.warning,
                  caption: 'if income stopped tomorrow',
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (r.monthsCovered / _target).clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: AppColors.surfaceHigh,
                    valueColor: AlwaysStoppedAnimation(
                      healthy ? AppColors.mint : AppColors.warning,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: ResultFigure(
                        label: 'Target',
                        value: Fmt.compactMoney(r.target),
                      ),
                    ),
                    Expanded(
                      child: ResultFigure(
                        label: 'Still needed',
                        value: Fmt.compactMoney(r.shortfall),
                        color: r.shortfall > 0 ? AppColors.warning : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          FynnCard(
            child: Column(
              children: [
                SliderInput(
                  label: 'Monthly expenses',
                  value: expenses,
                  min: 5000,
                  max: 500000,
                  step: 1000,
                  accent: AppColors.blue,
                  onChanged: (v) => setState(() => _expenses = v),
                ),
                SliderInput(
                  label: 'Existing EMIs',
                  value: emi,
                  min: 0,
                  max: 300000,
                  step: 1000,
                  accent: AppColors.warning,
                  onChanged: (v) => setState(() => _emi = v),
                ),
                SliderInput(
                  label: 'Current savings',
                  value: savings,
                  min: 0,
                  max: 5000000,
                  step: 10000,
                  onChanged: (v) => setState(() => _savings = v),
                ),
                SliderInput(
                  label: 'Months of cover wanted',
                  value: _target,
                  min: 3,
                  max: 12,
                  step: 1,
                  accent: AppColors.violet,
                  format: (v) => '${v.round()} months',
                  onChanged: (v) => setState(() => _target = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          VerdictBar(
            tone: healthy ? AppColors.mint : AppColors.warning,
            icon: healthy
                ? Icons.check_circle_outline_rounded
                : Icons.shield_outlined,
            text: healthy
                ? 'You are covered. This is the single biggest protection '
                      'against having to borrow at a bad rate in a hurry.'
                : 'Closing the ${Fmt.money(r.shortfall)} gap should usually '
                      'come before taking on new debt — it is what stops a bad '
                      'month turning into an expensive loan.',
          ),
        ], step: const Duration(milliseconds: 55)),
      ),
    );
  }
}
