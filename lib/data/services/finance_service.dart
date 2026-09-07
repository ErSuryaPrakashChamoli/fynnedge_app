import 'dart:math' as math;

import '../models/loan.dart';
import '../engine/financial_engine.dart';

/// Pure financial maths. This is deliberately NOT mocked — the numbers the
/// customer sees are calculated locally and identically forever, so a backend
/// swap can never change what an EMI means.
///
/// All rates are annual nominal percentages on a reducing balance.
class FinanceService {
  const FinanceService();

  /// Standard reducing-balance EMI.
  ///
  /// EMI = P·r·(1+r)^n / ((1+r)^n − 1), where r is the monthly rate.
  double emi({
    required double principal,
    required double annualRate,
    required int tenureMonths,
  }) {
    if (principal <= 0 || tenureMonths <= 0) return 0;
    if (annualRate <= 0) return principal / tenureMonths;

    final r = annualRate / 12 / 100;
    final pow = math.pow(1 + r, tenureMonths);
    return principal * r * pow / (pow - 1);
  }

  /// Full result including interest, total outflow and one-time fee.
  EmiResult calculate({
    required double principal,
    required double annualRate,
    required int tenureMonths,
    double processingFee = 0,
  }) {
    final e = emi(
      principal: principal,
      annualRate: annualRate,
      tenureMonths: tenureMonths,
    );
    final totalPayable = e * tenureMonths;
    return EmiResult(
      principal: principal,
      annualRate: annualRate,
      tenureMonths: tenureMonths,
      emi: e,
      totalInterest: math.max(0, totalPayable - principal),
      totalPayable: totalPayable,
      processingFee: processingFee,
    );
  }

  /// Month-by-month split of principal vs interest.
  List<AmortRow> schedule({
    required double principal,
    required double annualRate,
    required int tenureMonths,
  }) {
    final rows = <AmortRow>[];
    if (principal <= 0 || tenureMonths <= 0) return rows;

    final r = annualRate / 12 / 100;
    final e = emi(
      principal: principal,
      annualRate: annualRate,
      tenureMonths: tenureMonths,
    );
    var balance = principal;

    for (var m = 1; m <= tenureMonths; m++) {
      final interest = balance * r;
      var principalPaid = e - interest;
      if (principalPaid > balance) principalPaid = balance;
      balance = math.max(0, balance - principalPaid);
      rows.add(
        AmortRow(
          month: m,
          principalPaid: principalPaid,
          interestPaid: interest,
          balance: balance,
        ),
      );
    }
    return rows;
  }

  /// Yearly aggregation of [schedule] — what the charts actually plot.
  List<AmortRow> yearlySchedule({
    required double principal,
    required double annualRate,
    required int tenureMonths,
  }) {
    final monthly = schedule(
      principal: principal,
      annualRate: annualRate,
      tenureMonths: tenureMonths,
    );
    final years = <AmortRow>[];
    for (var start = 0; start < monthly.length; start += 12) {
      final chunk = monthly.sublist(
        start,
        math.min(start + 12, monthly.length),
      );
      years.add(
        AmortRow(
          month: (start ~/ 12) + 1,
          principalPaid: chunk.fold(0.0, (s, r) => s + r.principalPaid),
          interestPaid: chunk.fold(0.0, (s, r) => s + r.interestPaid),
          balance: chunk.last.balance,
        ),
      );
    }
    return years;
  }

  /// Largest loan whose EMI stays inside the customer's comfortable payment.
  double affordablePrincipal({
    required double comfortableEmi,
    required double annualRate,
    required int tenureMonths,
  }) {
    if (comfortableEmi <= 0 || tenureMonths <= 0) return 0;
    if (annualRate <= 0) return comfortableEmi * tenureMonths;

    final r = annualRate / 12 / 100;
    final pow = math.pow(1 + r, tenureMonths);
    return comfortableEmi * (pow - 1) / (r * pow);
  }

  /// Room left under FynnEdge's affordability reference.
  ///
  /// The reference is FinancialEngine's and only FinancialEngine's. This
  /// used to carry its own `maxRatio = 0.45` default, which meant FynnLab
  /// would have gone on using 45% after the product moved — a second
  /// definition of the one number the whole product is measured against.
  ///
  /// It is FynnEdge's reference for what stays comfortable, not a lender's
  /// rule about what gets declined.
  double emiHeadroom({
    required double monthlyIncome,
    required double existingEmi,
  }) => math.max(
    0,
    monthlyIncome * FinancialEngine.affordabilityCeilingPercent / 100 -
        existingEmi,
  );

  /// Tenure and interest saved by paying a lump sum after [afterMonths].
  PrepaymentResult prepayment({
    required double principal,
    required double annualRate,
    required int tenureMonths,
    required double lumpSum,
    required int afterMonths,
  }) {
    final base = calculate(
      principal: principal,
      annualRate: annualRate,
      tenureMonths: tenureMonths,
    );
    final rows = schedule(
      principal: principal,
      annualRate: annualRate,
      tenureMonths: tenureMonths,
    );

    if (afterMonths >= rows.length || lumpSum <= 0) {
      return PrepaymentResult(
        interestSaved: 0,
        monthsSaved: 0,
        newTenureMonths: tenureMonths,
        originalInterest: base.totalInterest,
        newInterest: base.totalInterest,
      );
    }

    final paidInterest = rows
        .take(afterMonths)
        .fold(0.0, (s, r) => s + r.interestPaid);
    final outstanding = rows[afterMonths - 1].balance - lumpSum;

    if (outstanding <= 0) {
      return PrepaymentResult(
        interestSaved: base.totalInterest - paidInterest,
        monthsSaved: tenureMonths - afterMonths,
        newTenureMonths: afterMonths,
        originalInterest: base.totalInterest,
        newInterest: paidInterest,
      );
    }

    // Keep the EMI the same and let the tenure shorten — the option that
    // saves the most interest, and the one FynnEdge recommends by default.
    final e = base.emi;
    final r = annualRate / 12 / 100;
    final remaining = (math.log(e / (e - outstanding * r)) / math.log(1 + r))
        .ceil();

    final newInterest = paidInterest + (e * remaining - outstanding);
    return PrepaymentResult(
      interestSaved: math.max(0, base.totalInterest - newInterest),
      monthsSaved: tenureMonths - (afterMonths + remaining),
      newTenureMonths: afterMonths + remaining,
      originalInterest: base.totalInterest,
      newInterest: newInterest,
    );
  }

  /// Compare staying put against moving the outstanding balance elsewhere.
  BalanceTransferResult balanceTransfer({
    required double outstanding,
    required double currentRate,
    required double newRate,
    required int remainingMonths,
    double transferFeePercent = 1.0,
  }) {
    final current = calculate(
      principal: outstanding,
      annualRate: currentRate,
      tenureMonths: remainingMonths,
    );
    final fee = outstanding * transferFeePercent / 100;
    final moved = calculate(
      principal: outstanding,
      annualRate: newRate,
      tenureMonths: remainingMonths,
      processingFee: fee,
    );

    final netSaving = current.totalInterest - moved.totalInterest - fee;
    final monthlySaving = current.emi - moved.emi;
    return BalanceTransferResult(
      currentEmi: current.emi,
      newEmi: moved.emi,
      monthlySaving: monthlySaving,
      transferFee: fee,
      netSaving: netSaving,
      breakEvenMonths: monthlySaving <= 0 ? -1 : (fee / monthlySaving).ceil(),
    );
  }

  /// Months of outgoings covered, and the gap to a [targetMonths] buffer.
  ///
  /// Pass [monthlySurplus] to also get how long that surplus would take to
  /// close the gap — the arithmetic belongs here, not in a screen.
  EmergencyFundResult emergencyFund({
    required double monthlyExpenses,
    required double existingEmi,
    required double savings,
    int targetMonths = 6,
    double monthlySurplus = 0,
  }) {
    final outgo = monthlyExpenses + existingEmi;
    final target = outgo * targetMonths;
    final covered = outgo <= 0 ? 0.0 : savings / outgo;
    final shortfall = math.max(0.0, target - savings);

    return EmergencyFundResult(
      monthlyOutgo: outgo,
      target: target,
      current: savings,
      monthsCovered: covered,
      shortfall: shortfall,
      // -1 where there is no surplus to do it with: "0 months" would read as
      // "already there".
      monthsToClose: shortfall <= 0
          ? 0
          : monthlySurplus <= 0
          ? -1
          : (shortfall / monthlySurplus).ceil(),
    );
  }

  /// Future value of a monthly contribution at an annual return.
  double futureValue({
    required double monthlyContribution,
    required double annualReturnPercent,
    required int months,
    double initial = 0,
  }) {
    final r = annualReturnPercent / 12 / 100;
    if (r == 0) return initial + monthlyContribution * months;
    final growth = math.pow(1 + r, months);
    return initial * growth + monthlyContribution * (growth - 1) / r;
  }

  /// Monthly saving needed to reach [target] in [months].
  double requiredMonthlySaving({
    required double target,
    required double current,
    required int months,
    double annualReturnPercent = 0,
  }) {
    final gap = target - current;
    if (gap <= 0 || months <= 0) return 0;
    if (annualReturnPercent == 0) return gap / months;

    final r = annualReturnPercent / 12 / 100;
    final growth = math.pow(1 + r, months);
    return (target - current * growth) * r / (growth - 1);
  }
}

class PrepaymentResult {
  const PrepaymentResult({
    required this.interestSaved,
    required this.monthsSaved,
    required this.newTenureMonths,
    required this.originalInterest,
    required this.newInterest,
  });

  final double interestSaved;
  final int monthsSaved;
  final int newTenureMonths;
  final double originalInterest;
  final double newInterest;
}

class BalanceTransferResult {
  const BalanceTransferResult({
    required this.currentEmi,
    required this.newEmi,
    required this.monthlySaving,
    required this.transferFee,
    required this.netSaving,
    required this.breakEvenMonths,
  });

  final double currentEmi;
  final double newEmi;
  final double monthlySaving;
  final double transferFee;
  final double netSaving;

  /// -1 when the transfer never pays for itself.
  final int breakEvenMonths;

  bool get isWorthIt => netSaving > 0;
}

class EmergencyFundResult {
  const EmergencyFundResult({
    required this.monthlyOutgo,
    required this.target,
    required this.current,
    required this.monthsCovered,
    required this.shortfall,
    this.monthsToClose = 0,
  });

  final double monthlyOutgo;
  final double target;
  final double current;
  final double monthsCovered;
  final double shortfall;

  /// Months for the given surplus to close [shortfall]; -1 when there is no
  /// surplus to do it with, 0 when there is no gap left.
  final int monthsToClose;

  bool get canCloseFromSurplus => monthsToClose > 0;

  bool get isHealthy => monthsCovered >= 6;
}
