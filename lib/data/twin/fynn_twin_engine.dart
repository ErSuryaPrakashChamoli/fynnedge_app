import '../../core/money/money.dart';
import '../engine/financial_engine.dart';
import '../models/loan.dart';
import '../models/twin.dart';
import '../score/fynn_score_engine.dart';
import '../services/finance_service.dart';

/// FynnTwin — the Flutter mirror of App\Domain\Twin\FynnTwinEngine.
///
/// **The backend is authoritative.** This exists so mock mode runs the same
/// simulation rather than a second, invented one, and so a preview shown
/// while the customer types matches what the server would return.
///
/// It owns no financial definitions. The projected state is produced by
/// calling FinancialEngine.snapshot with adjusted inputs, so outgo, surplus,
/// every ratio and the emergency buffer are the same definitions the rest of
/// the product uses.
///
/// It does not predict. Nothing here models inflation, a raise, a market or
/// an event; the only things that change are the ones the customer entered.
///
/// test/fynn_twin_parity_test.dart asserts this against a fixture the
/// Laravel engine generated. If the two diverge, that test fails.
class FynnTwinEngine {
  const FynnTwinEngine([this._finance = const FinanceService()]);

  final FinanceService _finance;

  static const String disclaimer =
      'This is a projection based on the assumptions you entered and the '
      'figures on your profile. It is not a prediction, and not a guarantee.';

  TwinProjection simulate({
    required FinancialSnapshot current,
    required TwinScenario scenario,
    LoanProduct? product,
  }) {
    final (projected, loan) = switch (scenario.type) {
      ScenarioType.loan => _loan(current, scenario, product),
      ScenarioType.expenseChange => (_expenses(current, scenario), null),
      ScenarioType.savingChange => (_saving(current, scenario), null),
    };

    final projectedRatio = projected.emiRatio.value;

    return TwinProjection(
      scenario: scenario,
      current: _state(current),
      projected: _state(projected),
      difference: _difference(current, projected),
      loan: loan,
      observations: _observe(current, projected, scenario),
      referencePercent: FinancialEngine.affordabilityCeilingPercent,
      projectedEmiRatio: current.hasIncome ? projectedRatio : null,
      withinReference: current.hasIncome &&
          projectedRatio <= FinancialEngine.affordabilityCeilingPercent,

      // The existing score engine, over the projected snapshot. Its model is
      // untouched and not re-implemented here.
      currentScore: current.hasIncome
          ? fynnScoreEngine.score(current).score
          : null,
      projectedScore: current.hasIncome
          ? fynnScoreEngine.score(projected).score
          : null,

      isMeasurable: current.hasIncome,
      disclaimer: disclaimer,
    );
  }

  /// A loan adds its EMI to what already goes out each month.
  ///
  /// The EMI comes from FinanceService at the product's published rate.
  /// Nothing here prices anything, and no rate is invented.
  (FinancialSnapshot, TwinLoan) _loan(
    FinancialSnapshot current,
    TwinScenario scenario,
    LoanProduct? product,
  ) {
    final amount = scenario.amount ?? 0;
    final tenure = scenario.tenureMonths ?? 0;
    final rate = product?.interestRate ?? 0;

    final pricing = _finance.calculate(
      principal: amount,
      annualRate: rate,
      tenureMonths: tenure,
    );

    final emi = Money.of(_round(pricing.emi));
    final fee = product?.processingFeeFor(amount) ?? 0;

    return (
      _withInputs(current, existingEmi: current.existingEmi + emi),
      TwinLoan(
        productId: product?.id,
        lender: product?.lender ?? '',
        productName: product?.name ?? '',
        amount: amount,
        tenureMonths: tenure,
        interestRate: rate,
        emi: emi.rupees,
        totalInterest: _round(pricing.totalInterest),
        totalPayable: _round(pricing.totalPayable),
        processingFee: _round(fee),
      ),
    );
  }

  FinancialSnapshot _expenses(
    FinancialSnapshot current,
    TwinScenario scenario,
  ) => _withInputs(
    current,
    expenses:
        (current.expenses + Money.of(scenario.monthlyChange ?? 0))
            .clampedToZero,
  );

  /// Money set aside each month, for a stated number of months.
  ///
  /// The assumption is the customer's and is stated back to them: that the
  /// amount is set aside every month and nothing is taken out again.
  FinancialSnapshot _saving(FinancialSnapshot current, TwinScenario scenario) {
    final monthly = Money.of(scenario.monthlyAmount ?? 0);
    // Five years at most, matching the API. Beyond that a projection stops
    // being a simulation of a decision and starts being a forecast.
    final months = (scenario.months ?? 0).clamp(0, 60);

    return _withInputs(current, savings: current.savings + monthly.times(months));
  }

  /// The same customer with one input changed, recalculated by the engine.
  FinancialSnapshot _withInputs(
    FinancialSnapshot current, {
    Money? expenses,
    Money? existingEmi,
    Money? savings,
  }) => financialEngine.snapshot(
    income: current.income,
    expenses: expenses ?? current.expenses,
    existingEmi: existingEmi ?? current.existingEmi,
    otherObligations: current.otherObligations,
    savings: savings ?? current.savings,
  );

  TwinState _state(FinancialSnapshot state) => TwinState(
    monthlyIncome: state.income.rupees,
    monthlyExpenses: state.expenses.rupees,
    existingEmi: state.existingEmi.rupees,
    otherObligations: state.otherObligations.rupees,
    savings: state.savings.rupees,
    monthlyOutgo: state.totalOutgo.rupees,
    // Kept as it comes: a negative surplus is the one number the customer
    // most needs to see.
    surplus: state.surplus.rupees,
    emiRatio: state.emiRatio.value,
    expenseRatio: state.expenseRatio.value,
    emergencyMonths: state.emergencyMonths.value,
  );

  TwinDifference _difference(
    FinancialSnapshot current,
    FinancialSnapshot projected,
  ) => TwinDifference(
    monthlyOutgo: Money.fromPaise(
      projected.totalOutgo.paise - current.totalOutgo.paise,
    ).rupees,
    surplus: Money.fromPaise(
      projected.surplus.paise - current.surplus.paise,
    ).rupees,
    savings: Money.fromPaise(
      projected.savings.paise - current.savings.paise,
    ).rupees,
    emiRatio: _round(projected.emiRatio.value - current.emiRatio.value),
    emergencyMonths: _round(
      projected.emergencyMonths.value - current.emergencyMonths.value,
    ),
  );

  /// What is worth saying about the result.
  ///
  /// Each observation is triggered by a figure the engine produced and quotes
  /// it. Where nothing meaningful changed, nothing is said: a manufactured
  /// warning teaches customers to ignore real ones.
  List<TwinObservation> _observe(
    FinancialSnapshot current,
    FinancialSnapshot projected,
    TwinScenario scenario,
  ) {
    if (!current.hasIncome) {
      return const [
        TwinObservation(
          key: 'no_income',
          severity: TwinObservation.info,
          detail:
              'Add your monthly income and FynnTwin can show what this would '
              'mean for your month.',
        ),
      ];
    }

    final observations = <TwinObservation>[];

    if (projected.surplus.isNegative) {
      observations.add(
        TwinObservation(
          key: 'negative_surplus',
          severity: TwinObservation.serious,
          detail:
              'Under this scenario you would be spending '
              '${_money(projected.surplus)} more than you earn each month — '
              'your outgo would exceed your income.',
        ),
      );
    } else if (projected.surplus.isZero) {
      observations.add(
        const TwinObservation(
          key: 'no_surplus',
          severity: TwinObservation.serious,
          detail:
              'Under this scenario you would have nothing left over at the '
              'end of the month.',
        ),
      );
    }

    final projectedRatio = projected.emiRatio.value;

    if (projectedRatio > FinancialEngine.affordabilityCeilingPercent) {
      observations.add(
        TwinObservation(
          key: 'above_affordability_reference',
          severity: TwinObservation.caution,
          detail:
              'Your EMIs would take ${_percent(projectedRatio)}% of your '
              'income, past the '
              '${_percent(FinancialEngine.affordabilityCeilingPercent)}% '
              'FynnEdge uses as its affordability reference. That is '
              "FynnEdge's reference, not a lender rule.",
        ),
      );
    }

    // Emergency cover is about what today's savings would stretch to under
    // the projected outgo — not a claim about future savings.
    final currentMonths = current.emergencyMonths.value;
    final projectedMonths = projected.emergencyMonths.value;

    if (projectedMonths < currentMonths) {
      observations.add(
        TwinObservation(
          key: 'emergency_cover_falls',
          severity: TwinObservation.caution,
          detail:
              'Your savings would cover about ${_percent(projectedMonths)} '
              'months of the projected outgo, down from '
              '${_percent(currentMonths)} months today.',
        ),
      );
    } else if (projectedMonths > currentMonths) {
      observations.add(
        TwinObservation(
          key: 'emergency_cover_rises',
          severity: TwinObservation.info,
          detail:
              'Your savings would cover about ${_percent(projectedMonths)} '
              'months of outgo, up from ${_percent(currentMonths)} months '
              'today.',
        ),
      );
    }

    if (scenario.type == ScenarioType.savingChange) {
      observations.add(
        const TwinObservation(
          key: 'saving_assumption',
          severity: TwinObservation.info,
          detail:
              'This assumes the amount is set aside every month and nothing '
              'is taken back out.',
        ),
      );
    }

    if (observations.isEmpty) {
      observations.add(
        const TwinObservation(
          key: 'little_change',
          severity: TwinObservation.info,
          detail:
              'This scenario would not move your monthly position much.',
        ),
      );
    }

    return observations;
  }

  static double _round(double value) => double.parse(value.toStringAsFixed(2));

  static String _money(Money money) => money.toIndianString();

  static String _percent(double value) {
    var text = value.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }
}

/// The single instance. Const, stateless, and safe to share.
const FynnTwinEngine fynnTwinEngine = FynnTwinEngine();
