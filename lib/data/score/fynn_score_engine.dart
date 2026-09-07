import '../../core/money/money.dart';
import '../engine/financial_engine.dart';
import '../models/score.dart';

/// FynnScore v1 — the Flutter mirror of App\Domain\Score\FynnScoreEngine.
///
/// **The backend is authoritative.** This exists so mock mode runs the same
/// scoring model rather than a second, invented one, and so an edited profile
/// changes the score consistently in both modes.
///
/// THE MODEL (v1, approved):
///
///   Three equally weighted dimensions, each a piecewise-linear curve:
///
///     EMI Burden        emi_ratio          100 at <=20%   0 at >=45%
///     Spending Control  expense_ratio      100 at <=40%   0 at >=80%
///     Emergency Buffer  emergency_months   100 at >=6     0 at 0
///
///   overall = round((d1 + d2 + d3) / 3), clamped 0..100
///
/// Goals are deliberately excluded: a deadline moving one day closer must
/// never change a customer's score.
///
/// test/fynn_score_parity_test.dart asserts this against a fixture the Laravel
/// engine generated. If the two diverge, that test fails.
class FynnScoreEngine {
  const FynnScoreEngine();

  static const String modelVersion = 'fynnscore-v1';

  static const String disclaimer =
      "FynnScore is FynnEdge's own view of your financial health. It is not a "
      "credit bureau score, not a lender's approval score, and no lender sees "
      'it.';

  // Anchors, in hundredths, so the whole model is integer arithmetic.
  static const int emiFullMarksAt = 2000;
  static const int emiZeroAt = 4500;
  static const int expenseFullMarksAt = 4000;
  static const int expenseZeroAt = 8000;
  static const int emergencyFullMarksAt = 600;
  static const int emergencyZeroAt = 0;

  static const int dimensionCount = 3;

  FynnScore score(FinancialSnapshot snapshot, {DateTime? inputsUpdatedAt}) {
    // v1 requires exactly one thing: an income to measure against.
    if (!snapshot.income.isPositive) {
      return FynnScore(
        hasScore: false,
        modelVersion: modelVersion,
        summary:
            'Add your monthly income and we can work out your FynnScore. '
            'Everything else follows from it.',
        missingRequirements: const ['monthly_income'],
        metrics: _metrics(snapshot),
        disclaimer: disclaimer,
      );
    }

    final scores = <String, int>{
      'emi_burden': _lowerIsBetter(
        snapshot.emiRatio.hundredths,
        emiFullMarksAt,
        emiZeroAt,
      ),
      'spending_control': _lowerIsBetter(
        snapshot.expenseRatio.hundredths,
        expenseFullMarksAt,
        expenseZeroAt,
      ),
      'emergency_buffer': _higherIsBetter(
        snapshot.emergencyMonths.hundredths,
        emergencyFullMarksAt,
        emergencyZeroAt,
      ),
    };

    final overall = _overallFrom(scores);

    final dimensions = [
      _emiDimension(snapshot, scores['emi_burden']!, overall),
      _spendingDimension(snapshot, scores['spending_control']!, overall),
      _emergencyDimension(snapshot, scores['emergency_buffer']!, overall),
    ];

    return FynnScore(
      hasScore: true,
      score: overall,
      band: ScoreBand.forScore(overall),
      summary: _summaryFor(ScoreBand.forScore(overall)),
      modelVersion: modelVersion,
      dimensions: dimensions,
      recommendations: _recommendations(snapshot, scores, overall),
      helping: [
        for (final d in dimensions)
          if (d.isHelping) d.name,
      ],
      needsAttention: [
        for (final d in dimensions)
          if (!d.isHelping) d.name,
      ],
      metrics: _metrics(snapshot),
      inputsUpdatedAt: inputsUpdatedAt,
      disclaimer: disclaimer,
    );
  }

  int _overallFrom(Map<String, int> hundredths) {
    final sum = hundredths.values.fold(0, (a, b) => a + b);
    final overall = Money.divideHalfUp(sum, 100 * dimensionCount);
    return overall.clamp(0, 100);
  }

  /// Full marks at or below [fullMarksAt], zero at or above [zeroAt].
  int _lowerIsBetter(int value, int fullMarksAt, int zeroAt) {
    if (value <= fullMarksAt) return 10000;
    if (value >= zeroAt) return 0;
    return Money.divideHalfUp(10000 * (zeroAt - value), zeroAt - fullMarksAt);
  }

  /// Full marks at or above [fullMarksAt], zero at or below [zeroAt].
  int _higherIsBetter(int value, int fullMarksAt, int zeroAt) {
    if (value >= fullMarksAt) return 10000;
    if (value <= zeroAt) return 0;
    return Money.divideHalfUp(10000 * (value - zeroAt), fullMarksAt - zeroAt);
  }

  /// A dimension helps when it sits at or above the overall score, because
  /// that is precisely what pulls the average up.
  bool _isHelping(int hundredths, int overall) =>
      Money.divideHalfUp(hundredths, 100) >= overall;

  ScoreDimension _emiDimension(
    FinancialSnapshot s,
    int hundredths,
    int overall,
  ) {
    final ratio = _trim(s.emiRatio.value);
    return ScoreDimension(
      key: 'emi_burden',
      name: 'EMI Burden',
      score: Money.divideHalfUp(hundredths, 100),
      weight: _weight,
      metric: 'emi_ratio',
      metricValue: s.emiRatio.value,
      metricUnit: 'percent_of_income',
      fullMarksAt: 20,
      zeroAt: 45,
      explanation: hundredths >= 10000
          ? 'Existing EMIs take $ratio% of your income, at or under the 20% '
                'mark. That leaves real room to borrow.'
          // No lender has seen these figures, so nothing here may say what
          // one would do. 45% is FynnEdge's own reference for what stays
          // comfortable to service.
          : hundredths <= 0
          ? 'Existing EMIs take $ratio% of your income, at or past the 45% '
                'FynnEdge uses as its affordability reference. Little of your '
                'income is left to service anything more.'
          : 'Existing EMIs take $ratio% of your income. Under 20% scores full '
                "marks; 45% is FynnEdge's affordability reference.",
      isHelping: _isHelping(hundredths, overall),
    );
  }

  ScoreDimension _spendingDimension(
    FinancialSnapshot s,
    int hundredths,
    int overall,
  ) {
    final ratio = _trim(s.expenseRatio.value);
    return ScoreDimension(
      key: 'spending_control',
      name: 'Spending Control',
      score: Money.divideHalfUp(hundredths, 100),
      weight: _weight,
      metric: 'expense_ratio',
      metricValue: s.expenseRatio.value,
      metricUnit: 'percent_of_income',
      fullMarksAt: 40,
      zeroAt: 80,
      explanation: hundredths >= 10000
          ? 'You spend $ratio% of your income, at or under the 40% mark. That '
                'is a strong ratio.'
          : hundredths <= 0
          ? 'You spend $ratio% of your income, at or beyond 80%. Very little '
                'is left over each month.'
          : 'You spend $ratio% of your income. Under 40% scores full marks; '
                '80% scores nothing.',
      isHelping: _isHelping(hundredths, overall),
    );
  }

  ScoreDimension _emergencyDimension(
    FinancialSnapshot s,
    int hundredths,
    int overall,
  ) {
    final months = _trim(s.emergencyMonths.value);
    return ScoreDimension(
      key: 'emergency_buffer',
      name: 'Emergency Buffer',
      score: Money.divideHalfUp(hundredths, 100),
      weight: _weight,
      metric: 'emergency_months',
      metricValue: s.emergencyMonths.value,
      metricUnit: 'months_of_outgoings',
      fullMarksAt: 6,
      zeroAt: 0,
      explanation: hundredths >= 10000
          ? 'Your savings cover $months months of outgoings, at or beyond the '
                '6-month target.'
          : hundredths <= 0
          ? 'You have no savings buffer. One unexpected month would have to be '
                'borrowed for.'
          : 'Your savings cover $months months of outgoings. The target is 6 '
                'months.',
      isHelping: _isHelping(hundredths, overall),
    );
  }

  /// One recommendation per dimension short of full marks, biggest gain first.
  /// The delta is the model re-run with that dimension at full marks.
  List<ScoreRecommendation> _recommendations(
    FinancialSnapshot s,
    Map<String, int> scores,
    int overall,
  ) {
    final out = <ScoreRecommendation>[];

    for (final entry in scores.entries) {
      if (entry.value >= 10000) continue;

      final projected = _overallFrom({...scores, entry.key: 10000});
      out.add(_recommendationFor(entry.key, s, overall, projected));
    }

    out.sort((a, b) {
      final byDelta = b.delta.compareTo(a.delta);
      return byDelta != 0 ? byDelta : a.dimension.compareTo(b.dimension);
    });

    return out;
  }

  ScoreRecommendation _recommendationFor(
    String key,
    FinancialSnapshot s,
    int current,
    int projected,
  ) => switch (key) {
    'emi_burden' => ScoreRecommendation(
      dimension: key,
      title: 'Bring your EMIs under 20% of income',
      detail:
          'Existing EMIs are ${_trim(s.emiRatio.value)}% of your income. '
          'Getting them to ${_moneyAt(s.income, 20)} a month or less would '
          'score full marks on this dimension — by prepaying, refinancing or '
          'letting a shorter loan finish.',
      metric: 'emi_ratio',
      currentValue: s.emiRatio.value,
      targetValue: 20,
      currentScore: current,
      projectedScore: projected,
      delta: projected - current,
    ),
    'spending_control' => ScoreRecommendation(
      dimension: key,
      title: 'Bring monthly spending under 40% of income',
      detail:
          'You spend ${_trim(s.expenseRatio.value)}% of your income. Holding '
          'regular expenses to ${_moneyAt(s.income, 40)} a month or less '
          'would score full marks on this dimension.',
      metric: 'expense_ratio',
      currentValue: s.expenseRatio.value,
      targetValue: 40,
      currentScore: current,
      projectedScore: projected,
      delta: projected - current,
    ),
    _ => ScoreRecommendation(
      dimension: key,
      title: 'Build your emergency fund to 6 months',
      detail:
          'Your savings cover ${_trim(s.emergencyMonths.value)} months of the '
          '${_format(s.totalOutgo)} you spend each month. Reaching '
          '${_format(s.totalOutgo.times(6))} would score full marks on this '
          'dimension.',
      metric: 'emergency_months',
      currentValue: s.emergencyMonths.value,
      targetValue: 6,
      currentScore: current,
      projectedScore: projected,
      delta: projected - current,
    ),
  };

  Map<String, double> _metrics(FinancialSnapshot s) => {
    'monthly_income': s.income.rupees,
    'monthly_outgo': s.totalOutgo.rupees,
    'surplus': s.surplus.rupees,
    'emi_ratio': s.emiRatio.value,
    'expense_ratio': s.expenseRatio.value,
    'emergency_months': s.emergencyMonths.value,
    'savings': s.savings.rupees,
  };

  static String _summaryFor(ScoreBand band) => switch (band) {
    ScoreBand.strong => 'Your financial health looks strong.',
    ScoreBand.good => 'Your financial health looks good, with room to improve.',
    ScoreBand.needsAttention =>
      'A few things need attention before you borrow.',
    ScoreBand.atRisk =>
      'Your finances are stretched. Steady them before taking on new debt.',
  };

  static double get _weight =>
      (Money.divideHalfUp(10000, dimensionCount)) / 10000;

  /// Matches PHP's json serialisation: whole values print without a decimal.
  static String _trim(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  static String _moneyAt(Money income, int percent) =>
      _format(Money.fromPaise(Money.divideHalfUp(income.paise * percent, 100)));

  /// Indian grouping, matching PHP's number_format output.
  static String _format(Money money) {
    final whole = (money.paise / 100).round().abs();
    final digits = whole.toString();
    if (digits.length <= 3) return '₹$digits';

    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);

    return '₹${parts.join(',')},$last3';
  }
}

/// The single shared instance. Stateless, so there is no reason for another.
const FynnScoreEngine fynnScoreEngine = FynnScoreEngine();
