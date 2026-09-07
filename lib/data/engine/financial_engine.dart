import 'dart:math' as math;

import '../../core/money/money.dart';
import '../../core/utils/clock.dart';
import '../models/json.dart';

/// Derived figures for one goal.
class GoalMetrics {
  const GoalMetrics({
    required this.target,
    required this.saved,
    required this.remaining,
    required this.progress,
    required this.monthsRemaining,
    required this.monthlyRequired,
    required this.isComplete,
    required this.isOverdue,
  });

  final Money target;
  final Money saved;
  final Money remaining;

  /// 0..1, to four decimal places.
  final double progress;
  final int monthsRemaining;
  final Money monthlyRequired;
  final bool isComplete;
  final bool isOverdue;
}

/// The derived picture of a customer's finances.
class FinancialSnapshot {
  const FinancialSnapshot({
    required this.income,
    required this.expenses,
    required this.existingEmi,
    required this.otherObligations,
    required this.savings,
    required this.totalOutgo,
    required this.surplus,
    required this.emiRatio,
    required this.expenseRatio,
    required this.outgoRatio,
    required this.emergencyMonths,
  });

  final Money income;
  final Money expenses;
  final Money existingEmi;
  final Money otherObligations;
  final Money savings;
  final Money totalOutgo;
  final Money surplus;
  final Ratio emiRatio;
  final Ratio expenseRatio;
  final Ratio outgoRatio;
  final Ratio emergencyMonths;

  bool get hasIncome => income.isPositive;
}

/// The customer's position now, and the same position carrying one more EMI.
///
/// Mirrors App\Domain\Financial\LoanProjection. Loan Detail, FynnMirror and
/// every match card read both halves from here, so no two screens can
/// disagree by a rupee about the same loan.
///
/// This is arithmetic on figures the customer gave us — not a lender
/// decision, not an approval, and not a promise. [isEstimate] is always true
/// and the UI says so.
class LoanProjection {
  const LoanProjection({
    required this.emi,
    required this.currentOutgo,
    required this.projectedOutgo,
    required this.currentSurplus,
    required this.projectedSurplus,
    required this.currentEmiRatio,
    required this.projectedEmiRatio,
    required this.emiCeiling,
    required this.headroomBefore,
    required this.headroomAfter,
    required this.withinCeiling,
    required this.isMeasurable,
  });

  final Money emi;
  final Money currentOutgo;
  final Money projectedOutgo;
  final Money currentSurplus;
  final Money projectedSurplus;
  final Ratio currentEmiRatio;
  final Ratio projectedEmiRatio;

  /// Total EMI the affordability ceiling allows on this income.
  final Money emiCeiling;
  final Money headroomBefore;
  final Money headroomAfter;
  final bool withinCeiling;

  /// False when there is no income to measure any of this against.
  final bool isMeasurable;

  bool get isEstimate => true;

  /// True when this loan would leave nothing over each month.
  bool get exhaustsSurplus => isMeasurable && !projectedSurplus.isPositive;

  double get ceilingPercent => FinancialEngine.affordabilityCeilingPercent;

  factory LoanProjection.fromJson(Map<String, dynamic> json) {
    final current = J.map(json['current']);
    final projected = J.map(json['projected']);

    return LoanProjection(
      emi: Money.of(json['emi']),
      currentOutgo: Money.of(current['monthly_outgo']),
      projectedOutgo: Money.of(projected['monthly_outgo']),
      currentSurplus: Money.of(current['surplus']),
      projectedSurplus: Money.of(projected['surplus']),
      currentEmiRatio: Ratio.ofPercent(J.dbl(current['emi_ratio'])),
      projectedEmiRatio: Ratio.ofPercent(J.dbl(projected['emi_ratio'])),
      emiCeiling: Money.of(json['emi_ceiling']),
      headroomBefore: Money.of(json['headroom_before']),
      headroomAfter: Money.of(json['headroom_after']),
      withinCeiling: J.boolean(json['within_ceiling']),
      isMeasurable: J.boolean(json['is_measurable']),
    );
  }

  Map<String, dynamic> toJson() => {
    'emi': emi.rupees,
    'current': {
      'monthly_outgo': currentOutgo.rupees,
      'surplus': currentSurplus.rupees,
      'emi_ratio': currentEmiRatio.value,
    },
    'projected': {
      'monthly_outgo': projectedOutgo.rupees,
      'surplus': projectedSurplus.rupees,
      'emi_ratio': projectedEmiRatio.value,
    },
    'ceiling_percent': ceilingPercent,
    'emi_ceiling': emiCeiling.rupees,
    'headroom_before': headroomBefore.rupees,
    'headroom_after': headroomAfter.rupees,
    'within_ceiling': withinCeiling,
    'exhausts_surplus': exhaustsSurplus,
    'is_measurable': isMeasurable,
    'is_estimate': isEstimate,
  };
}

/// The Flutter mirror of App\Domain\Financial\FinancialEngine.
///
/// **The backend is authoritative.** Whenever the server has returned derived
/// values, the app shows those. This engine exists for the one thing the
/// server cannot do: tell the customer what a figure *would* be while they
/// are still dragging a slider or typing into the goal editor, before
/// anything has been saved.
///
/// Those results are local estimates, and the UI labels them as such. They are
/// never written back to the server and never presented as confirmed.
///
/// Every definition here matches the backend exactly, and
/// test/financial_parity_test.dart asserts that against a fixture the Laravel
/// engine generated. If the two ever diverge, that test fails.
class FinancialEngine {
  const FinancialEngine();

  /// Days treated as one month when converting a deadline to months.
  static const int daysPerMonth = 30;

  /// Months of outgoings a healthy emergency fund covers.
  static const int emergencyFundTargetMonths = 6;

  /// The share of income FynnEdge treats as the affordability ceiling for
  /// total EMIs, defined once here and referenced everywhere else.
  ///
  /// FynnEdge's own reference, not a lender's rule and not an eligibility
  /// test: no product in the catalogue documents an EMI-ratio requirement.
  static const double affordabilityCeilingPercent = 45;

  FinancialSnapshot snapshot({
    required Money income,
    required Money expenses,
    required Money existingEmi,
    required Money otherObligations,
    required Money savings,
  }) {
    // totalOutgo = expenses + existingEmi + otherObligations
    final totalOutgo = expenses + existingEmi + otherObligations;

    return FinancialSnapshot(
      income: income,
      expenses: expenses,
      existingEmi: existingEmi,
      otherObligations: otherObligations,
      savings: savings,
      totalOutgo: totalOutgo,
      // surplus = income - totalOutgo. Allowed to be negative: a customer
      // spending more than they earn is a fact worth showing.
      surplus: income - totalOutgo,
      emiRatio: Ratio.percentOf(existingEmi, income),
      expenseRatio: Ratio.percentOf(expenses, income),
      outgoRatio: Ratio.percentOf(totalOutgo, income),
      emergencyMonths: Ratio.timesOver(savings, totalOutgo),
    );
  }

  /// The same customer, carrying one more EMI.
  ///
  /// Both halves of every before/after pair come from here. Nothing is
  /// persisted: the caller decides whether the customer ever acts on it.
  LoanProjection project(FinancialSnapshot current, Money emi) {
    final projectedOutgo = current.totalOutgo + emi;
    final projectedEmi = current.existingEmi + emi;

    // max(0, income x ceiling% - existing EMIs), in integer paise.
    final ceiling = Money.fromPaise(
      Money.divideHalfUp(
        current.income.paise * (affordabilityCeilingPercent * 100).round(),
        10000,
      ),
    );
    final projectedRatio = Ratio.percentOf(projectedEmi, current.income);

    return LoanProjection(
      emi: emi,
      currentOutgo: current.totalOutgo,
      projectedOutgo: projectedOutgo,
      currentSurplus: current.surplus,
      projectedSurplus: current.income - projectedOutgo,
      currentEmiRatio: current.emiRatio,
      projectedEmiRatio: projectedRatio,
      emiCeiling: ceiling,
      headroomBefore: (ceiling - current.existingEmi).clampedToZero,
      headroomAfter: (ceiling - projectedEmi).clampedToZero,
      withinCeiling: current.hasIncome &&
          projectedRatio.hundredths <=
              (affordabilityCeilingPercent * 100).round(),
      isMeasurable: current.hasIncome,
    );
  }

  GoalMetrics goalMetrics({
    required Money target,
    required Money saved,
    required DateTime targetDate,
    DateTime? asOf,
  }) {
    // remaining = max(0, target - saved). Overfunding does not create a
    // negative requirement.
    final remaining = (target - saved).clampedToZero;
    final months = monthsUntil(targetDate, asOf: asOf);

    // monthlyRequired = remaining / monthsRemaining. With no months left the
    // whole remainder is due now, which is what an overdue goal means.
    final monthlyRequired = remaining.isZero
        ? Money.zero
        : (months > 0 ? remaining.dividedBy(months) : remaining);

    return GoalMetrics(
      target: target,
      saved: saved,
      remaining: remaining,
      progress: progressOf(saved, target),
      monthsRemaining: months,
      monthlyRequired: monthlyRequired,
      isComplete: remaining.isZero && target.isPositive,
      isOverdue: months == 0 && !remaining.isZero,
    );
  }

  /// progress = saved / target, clamped to 0..1, to four decimal places.
  /// A zero target has no meaningful progress, so it reads as zero.
  double progressOf(Money saved, Money target) {
    if (target.paise <= 0) return 0;
    final tenThousandths = Money.divideHalfUp(
      saved.paise * 10000,
      target.paise,
    );
    return math.max(0, math.min(10000, tenThousandths)) / 10000;
  }

  /// Whole months until the deadline, rounded up so a part month still has to
  /// be funded. Never negative: a passed deadline is zero months, which the
  /// caller reads as "due now".
  int monthsUntil(DateTime targetDate, {DateTime? asOf}) {
    final from = _startOfDay(asOf ?? AppClock.now());
    final to = _startOfDay(targetDate);
    final days = to.difference(from).inDays;

    return days <= 0 ? 0 : (days / daysPerMonth).ceil();
  }

  /// What a healthy emergency fund would be for these outgoings.
  Money emergencyFundTarget(Money totalOutgo) =>
      totalOutgo.times(emergencyFundTargetMonths);

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// The single shared instance. Stateless, so there is no reason for another.
const FinancialEngine financialEngine = FinancialEngine();
