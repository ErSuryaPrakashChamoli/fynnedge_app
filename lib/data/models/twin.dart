import 'json.dart';

/// The decisions FynnTwin can simulate.
///
/// Three, because three can be calculated from what FynnEdge already knows
/// without assuming anything about the customer's future.
enum ScenarioType {
  loan('loan', 'Take a loan'),
  expenseChange('expense_change', 'Change my monthly spending'),
  savingChange('saving_change', 'Set money aside each month');

  const ScenarioType(this.id, this.label);
  final String id;
  final String label;

  static ScenarioType fromId(String? id) =>
      J.enumById(ScenarioType.values, id, (t) => t.id, ScenarioType.loan);

  String get description => switch (this) {
    ScenarioType.loan =>
      'See what a loan from the catalogue would do to your month before you '
          'apply for one.',
    ScenarioType.expenseChange =>
      'See what spending more — or less — each month would do to what you '
          'have left over.',
    ScenarioType.savingChange =>
      'See how far a monthly amount set aside would take your savings, and '
          'what that covers.',
  };
}

/// What the customer chose to simulate.
///
/// Assumptions only. Where they are starting from comes from their profile,
/// never from here.
class TwinScenario {
  const TwinScenario({
    required this.type,
    this.amount,
    this.tenureMonths,
    this.productId,
    this.monthlyChange,
    this.monthlyAmount,
    this.months,
  });

  final ScenarioType type;

  final double? amount;
  final int? tenureMonths;
  final String? productId;

  /// Expense change: the monthly difference, positive or negative.
  final double? monthlyChange;

  /// Saving: the monthly amount, and how many months of it.
  final double? monthlyAmount;
  final int? months;

  Map<String, dynamic> toJson() => {
    'type': type.id,
    'amount': ?amount,
    'tenure_months': ?tenureMonths,
    'product_id': ?productId,
    'monthly_change': ?monthlyChange,
    'monthly_amount': ?monthlyAmount,
    'months': ?months,
  };
}

/// One thing worth noticing about a projection, and the figure behind it.
class TwinObservation {
  const TwinObservation({
    required this.key,
    required this.severity,
    required this.detail,
  });

  static const String info = 'info';
  static const String caution = 'caution';
  static const String serious = 'serious';

  final String key;
  final String severity;
  final String detail;

  bool get isSerious => severity == serious;
  bool get isCaution => severity == caution;

  factory TwinObservation.fromJson(Map<String, dynamic> json) =>
      TwinObservation(
        key: J.str(json['key']),
        severity: J.str(json['severity'], info),
        detail: J.str(json['detail']),
      );

  Map<String, dynamic> toJson() => {
    'key': key,
    'severity': severity,
    'detail': detail,
  };
}

/// One side of the comparison — today, or under the scenario.
class TwinState {
  const TwinState({
    this.monthlyIncome = 0,
    this.monthlyExpenses = 0,
    this.existingEmi = 0,
    this.otherObligations = 0,
    this.savings = 0,
    this.monthlyOutgo = 0,
    this.surplus = 0,
    this.emiRatio = 0,
    this.expenseRatio = 0,
    this.emergencyMonths = 0,
  });

  final double monthlyIncome;
  final double monthlyExpenses;
  final double existingEmi;
  final double otherObligations;
  final double savings;
  final double monthlyOutgo;

  /// Kept as it comes. A negative surplus is a fact, not something to clamp.
  final double surplus;

  final double emiRatio;
  final double expenseRatio;
  final double emergencyMonths;

  factory TwinState.fromJson(Map<String, dynamic> json) => TwinState(
    monthlyIncome: J.dbl(json['monthly_income']),
    monthlyExpenses: J.dbl(json['monthly_expenses']),
    existingEmi: J.dbl(json['existing_emi']),
    otherObligations: J.dbl(json['other_obligations']),
    savings: J.dbl(json['savings']),
    monthlyOutgo: J.dbl(json['monthly_outgo']),
    surplus: J.dbl(json['surplus']),
    emiRatio: J.dbl(json['emi_ratio']),
    expenseRatio: J.dbl(json['expense_ratio']),
    emergencyMonths: J.dbl(json['emergency_months']),
  );

  Map<String, dynamic> toJson() => {
    'monthly_income': monthlyIncome,
    'monthly_expenses': monthlyExpenses,
    'existing_emi': existingEmi,
    'other_obligations': otherObligations,
    'savings': savings,
    'monthly_outgo': monthlyOutgo,
    'surplus': surplus,
    'emi_ratio': emiRatio,
    'expense_ratio': expenseRatio,
    'emergency_months': emergencyMonths,
  };
}

/// What the loan being modelled would cost, priced by the product.
class TwinLoan {
  const TwinLoan({
    this.productId,
    this.lender = '',
    this.productName = '',
    this.amount = 0,
    this.tenureMonths = 0,
    this.interestRate = 0,
    this.emi = 0,
    this.totalInterest = 0,
    this.totalPayable = 0,
    this.processingFee = 0,
  });

  final String? productId;
  final String lender;
  final String productName;
  final double amount;
  final int tenureMonths;
  final double interestRate;
  final double emi;
  final double totalInterest;
  final double totalPayable;
  final double processingFee;

  factory TwinLoan.fromJson(Map<String, dynamic> json) => TwinLoan(
    productId: J.strOrNull(json['product_id']),
    lender: J.str(json['lender']),
    productName: J.str(json['product_name']),
    amount: J.dbl(json['amount']),
    tenureMonths: J.integer(json['tenure_months']),
    interestRate: J.dbl(json['interest_rate']),
    emi: J.dbl(json['emi']),
    totalInterest: J.dbl(json['total_interest']),
    totalPayable: J.dbl(json['total_payable']),
    processingFee: J.dbl(json['processing_fee']),
  );

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'lender': lender,
    'product_name': productName,
    'amount': amount,
    'tenure_months': tenureMonths,
    'interest_rate': interestRate,
    'emi': emi,
    'total_interest': totalInterest,
    'total_payable': totalPayable,
    'processing_fee': processingFee,
  };
}

/// The difference the scenario would make.
class TwinDifference {
  const TwinDifference({
    this.monthlyOutgo = 0,
    this.surplus = 0,
    this.savings = 0,
    this.emiRatio = 0,
    this.emergencyMonths = 0,
  });

  final double monthlyOutgo;
  final double surplus;
  final double savings;
  final double emiRatio;
  final double emergencyMonths;

  factory TwinDifference.fromJson(Map<String, dynamic> json) => TwinDifference(
    monthlyOutgo: J.dbl(json['monthly_outgo']),
    surplus: J.dbl(json['surplus']),
    savings: J.dbl(json['savings']),
    emiRatio: J.dbl(json['emi_ratio']),
    emergencyMonths: J.dbl(json['emergency_months']),
  );

  Map<String, dynamic> toJson() => {
    'monthly_outgo': monthlyOutgo,
    'surplus': surplus,
    'savings': savings,
    'emi_ratio': emiRatio,
    'emergency_months': emergencyMonths,
  };
}

/// Where the customer is, and where this scenario would put them.
///
/// A projection of one decision, not a forecast: nothing here assumes a
/// raise, an inflation rate, a market, or an event the customer did not
/// enter.
class TwinProjection {
  const TwinProjection({
    required this.scenario,
    required this.current,
    required this.projected,
    required this.difference,
    this.loan,
    this.observations = const [],
    this.referencePercent = 45,
    this.projectedEmiRatio,
    this.withinReference = false,
    this.currentScore,
    this.projectedScore,
    this.isMeasurable = false,
    this.disclaimer = '',
  });

  final TwinScenario scenario;
  final TwinState current;
  final TwinState projected;
  final TwinDifference difference;
  final TwinLoan? loan;
  final List<TwinObservation> observations;

  /// FynnEdge's own affordability reference, not a lender's rule.
  final double referencePercent;
  final double? projectedEmiRatio;
  final bool withinReference;

  /// The existing score engine over the projected snapshot. A simulation.
  final int? currentScore;
  final int? projectedScore;

  final bool isMeasurable;
  final String disclaimer;

  /// Always true. This is a projection, and says so wherever it goes.
  bool get isProjection => true;

  bool get exhaustsSurplus => isMeasurable && projected.surplus <= 0;

  List<TwinObservation> get warnings =>
      observations.where((o) => o.isSerious || o.isCaution).toList();

  factory TwinProjection.fromJson(Map<String, dynamic> json) {
    final affordability = J.map(json['affordability']);
    final score = J.map(json['fynn_score']);
    final scenario = J.map(json['scenario']);

    return TwinProjection(
      scenario: TwinScenario(
        type: ScenarioType.fromId(J.strOrNull(scenario['type'])),
        amount: J.dblOrNull(scenario['amount']),
        tenureMonths: J.intOrNull(scenario['tenure_months']),
        productId: J.strOrNull(scenario['product_id']),
        monthlyChange: J.dblOrNull(scenario['monthly_change']),
        monthlyAmount: J.dblOrNull(scenario['monthly_amount']),
        months: J.intOrNull(scenario['months']),
      ),
      current: TwinState.fromJson(J.map(json['current'])),
      projected: TwinState.fromJson(J.map(json['projected'])),
      difference: TwinDifference.fromJson(J.map(json['difference'])),
      loan: json['loan'] == null
          ? null
          : TwinLoan.fromJson(J.map(json['loan'])),
      observations: J.objects(json['observations'], TwinObservation.fromJson),
      referencePercent: J.dbl(affordability['reference_percent'], 45),
      projectedEmiRatio: J.dblOrNull(affordability['projected_emi_ratio']),
      withinReference: J.boolean(affordability['within_reference']),
      currentScore: J.intOrNull(score['current']),
      projectedScore: J.intOrNull(score['projected']),
      isMeasurable: J.boolean(json['is_measurable']),
      disclaimer: J.str(json['disclaimer']),
    );
  }

  Map<String, dynamic> toJson() => {
    'scenario': scenario.toJson(),
    'current': current.toJson(),
    'projected': projected.toJson(),
    'difference': difference.toJson(),
    'affordability': {
      'reference_percent': referencePercent,
      'projected_emi_ratio': projectedEmiRatio,
      'within_reference': withinReference,
    },
    'loan': loan?.toJson(),
    'fynn_score': {
      'current': currentScore,
      'projected': projectedScore,
      'is_simulated': true,
    },
    'observations': observations.map((o) => o.toJson()).toList(),
    'is_measurable': isMeasurable,
    'is_projection': isProjection,
    'disclaimer': disclaimer,
  };
}
