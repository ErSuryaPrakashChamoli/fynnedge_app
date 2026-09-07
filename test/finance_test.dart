import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/data/services/finance_service.dart';

/// The EMI engine is the one place in FynnEdge where a wrong number is a
/// real-world harm, so it is tested directly rather than through the UI.
void main() {
  const finance = FinanceService();

  _verifyAgainstSimulation();

  group('EMI', () {
    test('matches the standard reducing-balance formula', () {
      // ₹10,00,000 at 13.25% over 60 months.
      final emi = finance.emi(
        principal: 1000000,
        annualRate: 13.25,
        tenureMonths: 60,
      );
      expect(emi, closeTo(22881.26, 0.5));
    });

    test('zero rate splits the principal evenly', () {
      final emi = finance.emi(
        principal: 120000,
        annualRate: 0,
        tenureMonths: 12,
      );
      expect(emi, closeTo(10000, 0.01));
    });

    test('total payable equals emi x tenure and interest is the remainder', () {
      final r = finance.calculate(
        principal: 500000,
        annualRate: 11.5,
        tenureMonths: 60,
      );
      expect(r.totalPayable, closeTo(r.emi * 60, 0.01));
      expect(r.totalInterest, closeTo(r.totalPayable - 500000, 0.01));
      expect(r.emi, closeTo(10996.30, 0.5));
    });

    test('degenerate inputs do not throw', () {
      expect(finance.emi(principal: 0, annualRate: 12, tenureMonths: 60), 0);
      expect(finance.emi(principal: 100, annualRate: 12, tenureMonths: 0), 0);
    });
  });

  group('Amortisation', () {
    test('schedule closes the balance to zero', () {
      final rows = finance.schedule(
        principal: 1000000,
        annualRate: 13.25,
        tenureMonths: 60,
      );
      expect(rows, hasLength(60));
      expect(rows.last.balance, closeTo(0, 1));
    });

    test('interest paid across the schedule matches the summary', () {
      final rows = finance.schedule(
        principal: 800000,
        annualRate: 12.4,
        tenureMonths: 48,
      );
      final summary = finance.calculate(
        principal: 800000,
        annualRate: 12.4,
        tenureMonths: 48,
      );
      final totalInterest = rows.fold<double>(0, (s, r) => s + r.interestPaid);
      expect(totalInterest, closeTo(summary.totalInterest, 5));
    });

    test('yearly aggregation covers every month', () {
      final years = finance.yearlySchedule(
        principal: 1000000,
        annualRate: 13.25,
        tenureMonths: 60,
      );
      expect(years, hasLength(5));
      expect(years.last.balance, closeTo(0, 1));
    });
  });

  group('Affordability', () {
    test('affordable principal round-trips back to the EMI', () {
      final principal = finance.affordablePrincipal(
        comfortableEmi: 25000,
        annualRate: 13.25,
        tenureMonths: 60,
      );
      final emi = finance.emi(
        principal: principal,
        annualRate: 13.25,
        tenureMonths: 60,
      );
      expect(emi, closeTo(25000, 1));
    });

    test('headroom respects the ratio cap and never goes negative', () {
      expect(
        finance.emiHeadroom(monthlyIncome: 100000, existingEmi: 20000),
        closeTo(25000, 0.01),
      );
      expect(finance.emiHeadroom(monthlyIncome: 50000, existingEmi: 40000), 0);
    });
  });

  group('Prepayment', () {
    test('a lump sum shortens the tenure and saves interest', () {
      final r = finance.prepayment(
        principal: 1000000,
        annualRate: 13.25,
        tenureMonths: 60,
        lumpSum: 200000,
        afterMonths: 12,
      );
      expect(r.monthsSaved, greaterThan(0));
      expect(r.interestSaved, greaterThan(0));
      expect(r.newTenureMonths, lessThan(60));
    });

    test('no lump sum changes nothing', () {
      final r = finance.prepayment(
        principal: 1000000,
        annualRate: 13.25,
        tenureMonths: 60,
        lumpSum: 0,
        afterMonths: 12,
      );
      expect(r.interestSaved, 0);
      expect(r.monthsSaved, 0);
    });
  });

  group('Balance transfer', () {
    test('a cheaper rate produces a positive net saving', () {
      final r = finance.balanceTransfer(
        outstanding: 800000,
        currentRate: 14.5,
        newRate: 11.9,
        remainingMonths: 42,
      );
      expect(r.isWorthIt, isTrue);
      expect(r.newEmi, lessThan(r.currentEmi));
      expect(r.breakEvenMonths, greaterThan(0));
    });

    test('a worse rate is flagged as not worth it', () {
      final r = finance.balanceTransfer(
        outstanding: 800000,
        currentRate: 11.0,
        newRate: 13.0,
        remainingMonths: 42,
      );
      expect(r.isWorthIt, isFalse);
      expect(r.breakEvenMonths, -1);
    });
  });

  group('Emergency fund', () {
    test('computes months covered and the shortfall to a 6-month buffer', () {
      final r = finance.emergencyFund(
        monthlyExpenses: 40000,
        existingEmi: 20000,
        savings: 180000,
      );
      expect(r.monthlyOutgo, 60000);
      expect(r.monthsCovered, closeTo(3, 0.01));
      expect(r.target, 360000);
      expect(r.shortfall, 180000);
      expect(r.isHealthy, isFalse);
    });
  });

  group('Goal planning', () {
    test('required monthly saving closes the gap with no returns', () {
      final m = finance.requiredMonthlySaving(
        target: 360000,
        current: 180000,
        months: 12,
      );
      expect(m, closeTo(15000, 0.01));
    });

    test('future value compounds a monthly contribution', () {
      final fv = finance.futureValue(
        monthlyContribution: 15000,
        annualReturnPercent: 12,
        months: 12,
      );
      expect(fv, greaterThan(15000 * 12));
    });
  });
}

/// Independent verification of the closed-form EMI against a month-by-month
/// simulation. If the formula were wrong, the simulated balance would not
/// land on zero.
void _verifyAgainstSimulation() {
  const finance = FinanceService();

  /// Runs the loan forward one month at a time, charging interest on the
  /// outstanding balance and deducting the EMI. Nothing here uses the
  /// closed-form formula, so it is a genuine cross-check.
  double simulateClosingBalance({
    required double principal,
    required double annualRate,
    required int months,
    required double emi,
  }) {
    final monthlyRate = annualRate / 12 / 100;
    var balance = principal;
    for (var m = 0; m < months; m++) {
      balance = balance + (balance * monthlyRate) - emi;
    }
    return balance;
  }

  group('Reducing-balance verification', () {
    const cases = [
      (1000000.0, 13.25, 60),
      (500000.0, 11.5, 60),
      (800000.0, 12.4, 48),
      (2500000.0, 8.6, 240),
      (300000.0, 18.0, 24),
    ];

    for (final (principal, rate, months) in cases) {
      test(
        '${principal.toInt()} at $rate% over $months months closes to zero',
        () {
          final emi = finance.emi(
            principal: principal,
            annualRate: rate,
            tenureMonths: months,
          );
          final closing = simulateClosingBalance(
            principal: principal,
            annualRate: rate,
            months: months,
            emi: emi,
          );
          // Within a rupee across the whole term.
          expect(closing.abs(), lessThan(1.0));
        },
      );
    }

    test('the documented reference case holds: 10L @ 13.25% / 60mo', () {
      final result = finance.calculate(
        principal: 1000000,
        annualRate: 13.25,
        tenureMonths: 60,
      );
      expect(result.emi, closeTo(22881.26, 0.5));
      expect(result.totalPayable, closeTo(result.emi * 60, 0.01));
      expect(
        result.totalInterest,
        closeTo(result.totalPayable - 1000000, 0.01),
      );
    });

    test('interest accrues only on the outstanding balance', () {
      // A reducing-balance loan must cost less than flat interest.
      final reducing = finance.calculate(
        principal: 1000000,
        annualRate: 13.25,
        tenureMonths: 60,
      );
      const flatInterest = 1000000 * 0.1325 * 5;
      expect(reducing.totalInterest, lessThan(flatInterest));
    });

    test('a longer tenure lowers the EMI but raises the total interest', () {
      final short = finance.calculate(
        principal: 1000000,
        annualRate: 13.25,
        tenureMonths: 36,
      );
      final long = finance.calculate(
        principal: 1000000,
        annualRate: 13.25,
        tenureMonths: 84,
      );
      expect(long.emi, lessThan(short.emi));
      expect(long.totalInterest, greaterThan(short.totalInterest));
    });

    test('a higher rate raises both EMI and interest', () {
      final cheap = finance.calculate(
        principal: 1000000,
        annualRate: 11.5,
        tenureMonths: 60,
      );
      final dear = finance.calculate(
        principal: 1000000,
        annualRate: 14.5,
        tenureMonths: 60,
      );
      expect(dear.emi, greaterThan(cheap.emi));
      expect(dear.totalInterest, greaterThan(cheap.totalInterest));
    });
  });

  group('Comparison ordering', () {
    test('the cheaper offer wins on every cost dimension', () {
      // Mirrors what the Compare screen marks as the better number.
      final better = finance.calculate(
        principal: 1000000,
        annualRate: 12.4,
        tenureMonths: 60,
        processingFee: 10000,
      );
      final worse = finance.calculate(
        principal: 1000000,
        annualRate: 13.25,
        tenureMonths: 60,
        processingFee: 17500,
      );

      expect(better.emi, lessThan(worse.emi));
      expect(better.totalInterest, lessThan(worse.totalInterest));
      expect(better.totalCost, lessThan(worse.totalCost));
      expect(
        better.totalPayable + better.processingFee,
        lessThan(worse.totalPayable + worse.processingFee),
      );
    });
  });
}
