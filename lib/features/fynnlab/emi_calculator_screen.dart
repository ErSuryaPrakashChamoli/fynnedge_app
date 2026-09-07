import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/money/money.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/engine/financial_engine.dart';
import '../../data/models/loan.dart';
import '../profile/profile_controller.dart';
import 'widgets/calc_inputs.dart';

/// Screen 16a — the EMI calculator, fully functional.
/// All arithmetic is delegated to FinanceService; this screen only renders.
class EmiCalculatorScreen extends ConsumerStatefulWidget {
  const EmiCalculatorScreen({super.key});

  @override
  ConsumerState<EmiCalculatorScreen> createState() =>
      _EmiCalculatorScreenState();
}

class _EmiCalculatorScreenState extends ConsumerState<EmiCalculatorScreen> {
  double _amount = 1000000;
  double _rate = 13.25;
  double _tenure = 60;

  @override
  Widget build(BuildContext context) {
    final finance = ref.watch(financeServiceProvider);
    final financials = ref.watch(financialProfileProvider).value;

    final result = finance.calculate(
      principal: _amount,
      annualRate: _rate,
      tenureMonths: _tenure.round(),
    );
    final yearly = finance.yearlySchedule(
      principal: _amount,
      annualRate: _rate,
      tenureMonths: _tenure.round(),
    );

    // What this EMI would do to the customer's EMI share of income, from
    // the engine that owns that definition. Working it out here would be a
    // second definition of the figure FynnScore, Home and FynnMirror all
    // quote — and the one most likely to drift.
    final projection = financials == null
        ? null
        : financialEngine.project(
            financialEngine.snapshot(
              income: Money.of(financials.monthlyIncome),
              expenses: Money.of(financials.monthlyExpenses),
              existingEmi: Money.of(financials.existingEmi),
              otherObligations: Money.of(financials.otherObligations),
              savings: Money.of(financials.savings),
            ),
            Money.of(result.emi),
          );
    final ratio = projection == null || !projection.isMeasurable
        ? null
        : projection.projectedEmiRatio.value;

    return FynnScaffold(
      title: 'EMI Calculator',
      padHorizontal: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: staggered([
          _EmiHeadline(emi: result.emi),
          const SizedBox(height: 22),
          FynnCard(
            child: Column(
              children: [
                SliderInput(
                  label: 'Loan amount',
                  value: _amount,
                  min: 50000,
                  max: 10000000,
                  step: 50000,
                  onChanged: (v) => setState(() => _amount = v),
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
                  label: 'Tenure',
                  value: _tenure,
                  min: 6,
                  max: 360,
                  step: 6,
                  accent: AppColors.blue,
                  format: (v) => Fmt.months(v.round()),
                  onChanged: (v) => setState(() => _tenure = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeader(title: 'What it costs'),
          FynnCard(
            child: Row(
              children: [
                SizedBox(
                  width: 116,
                  height: 116,
                  child: _SplitChart(
                    principal: _amount,
                    interest: result.totalInterest,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Legend(
                        color: AppColors.blue,
                        label: 'Principal',
                        value: Fmt.compactMoney(_amount),
                      ),
                      const SizedBox(height: 14),
                      _Legend(
                        color: AppColors.warning,
                        label: 'Interest',
                        value: Fmt.compactMoney(result.totalInterest),
                        note: '${result.interestShare.round()}% of principal',
                      ),
                      const SizedBox(height: 14),
                      _Legend(
                        color: AppColors.textTertiary,
                        label: 'Total repayment',
                        value: Fmt.compactMoney(result.totalPayable),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeader(
            title: 'How it unwinds',
            subtitle: 'Interest dominates the early years',
          ),
          FynnCard(
            padding: const EdgeInsets.fromLTRB(8, 20, 16, 12),
            child: SizedBox(height: 160, child: _AmortChart(rows: yearly)),
          ),
          const SizedBox(height: 22),
          // Measured against the one affordability reference FynnEdge uses,
          // and described as FynnEdge's reference. No lender has seen these
          // figures, so nothing here may speak for one.
          if (ratio != null && projection != null)
            VerdictBar(
              tone: projection.withinCeiling
                  ? AppColors.mint
                  : AppColors.warning,
              icon: projection.withinCeiling
                  ? Icons.check_circle_outline_rounded
                  : Icons.warning_amber_rounded,
              text: projection.withinCeiling
                  ? 'Added to your existing EMIs this is '
                        '${Fmt.ratio(ratio)} of your income, inside the '
                        '${Fmt.ratio(FinancialEngine.affordabilityCeilingPercent)} '
                        'FynnEdge uses as its affordability reference.'
                  : 'Added to your existing EMIs this would take '
                        '${Fmt.ratio(ratio)} of your income, past the '
                        '${Fmt.ratio(FinancialEngine.affordabilityCeilingPercent)} '
                        "FynnEdge uses as its affordability reference. That is "
                        "FynnEdge's reference, not a lender rule.",
            ),
        ], step: const Duration(milliseconds: 55)),
      ),
    );
  }
}

class _EmiHeadline extends StatelessWidget {
  const _EmiHeadline({required this.emi});
  final double emi;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        gradient: AppColors.surfaceGradient,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Text(
            'YOUR MONTHLY EMI',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: emi, end: emi),
            duration: const Duration(milliseconds: 220),
            builder: (context, v, _) => ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (b) => AppColors.brandGradient.createShader(b),
              child: Text(
                Fmt.money(v),
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2,
                  height: 1,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplitChart extends StatelessWidget {
  const _SplitChart({required this.principal, required this.interest});

  final double principal;
  final double interest;

  @override
  Widget build(BuildContext context) {
    return PieChart(
      PieChartData(
        startDegreeOffset: -90,
        sectionsSpace: 3,
        centerSpaceRadius: 34,
        sections: [
          PieChartSectionData(
            value: principal,
            color: AppColors.blue,
            radius: 20,
            showTitle: false,
          ),
          PieChartSectionData(
            value: interest,
            color: AppColors.warning,
            radius: 20,
            showTitle: false,
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.value,
    this.note,
  });

  final Color color;
  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (note != null)
                Text(
                  note!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Stacked bars: principal vs interest paid in each year of the loan.
class _AmortChart extends StatelessWidget {
  const _AmortChart({required this.rows});
  final List<AmortRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final peak = rows
        .map((r) => r.principalPaid + r.interestPaid)
        .reduce((a, b) => a > b ? a : b);

    // Derive the tick interval from the chart's own ceiling, so the top
    // gridline lands exactly on a label instead of beside one.
    final maxY = peak * 1.1;
    final interval = maxY / 2;

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(enabled: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.borderSoft, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: interval,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  Fmt.compactMoney(value),
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Y${value.toInt()}',
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ),
          ),
        ),
        barGroups: [
          for (final r in rows)
            BarChartGroupData(
              x: r.month,
              barRods: [
                BarChartRodData(
                  toY: r.principalPaid + r.interestPaid,
                  width: rows.length > 12 ? 6 : 14,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                  rodStackItems: [
                    BarChartRodStackItem(0, r.interestPaid, AppColors.warning),
                    BarChartRodStackItem(
                      r.interestPaid,
                      r.principalPaid + r.interestPaid,
                      AppColors.blue,
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}
