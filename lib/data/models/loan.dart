import 'json.dart';
import 'score.dart';

enum LoanCategory {
  personal('personal', 'Personal Loan'),
  business('business', 'Business Loan'),
  home('home', 'Home Loan'),
  lap('lap', 'Loan Against Property');

  const LoanCategory(this.id, this.label);
  final String id;
  final String label;

  static LoanCategory fromId(String? id) =>
      J.enumById(LoanCategory.values, id, (c) => c.id, LoanCategory.personal);
}

/// The five dimensions behind a FynnTrust score (Screen 14).
class TrustBreakdown {
  const TrustBreakdown({
    required this.cost,
    required this.fees,
    required this.flexibility,
    required this.suitability,
    required this.transparency,
  });

  final ScoreFactor cost;
  final ScoreFactor fees;
  final ScoreFactor flexibility;
  final ScoreFactor suitability;
  final ScoreFactor transparency;

  List<ScoreFactor> get all => [
    cost,
    fees,
    flexibility,
    suitability,
    transparency,
  ];

  /// A missing or partial breakdown yields zeroed factors rather than an
  /// exception — the offer still renders, just without its score detail.
  factory TrustBreakdown.fromJson(Map<String, dynamic> json) => TrustBreakdown(
    cost: _factor(json['cost'], 'Cost'),
    fees: _factor(json['fees'], 'Fees'),
    flexibility: _factor(json['flexibility'], 'Flexibility'),
    suitability: _factor(json['suitability'], 'Suitability'),
    transparency: _factor(json['transparency'], 'Transparency'),
  );

  static ScoreFactor _factor(Object? value, String fallbackLabel) {
    final map = J.map(value);
    if (map.isEmpty) {
      return ScoreFactor(label: fallbackLabel, value: 0, explanation: '');
    }
    final parsed = ScoreFactor.fromJson(map);
    return parsed.label.isEmpty
        ? ScoreFactor(
            label: fallbackLabel,
            value: parsed.value,
            explanation: parsed.explanation,
            weight: parsed.weight,
          )
        : parsed;
  }

  Map<String, dynamic> toJson() => {
    'cost': cost.toJson(),
    'fees': fees.toJson(),
    'flexibility': flexibility.toJson(),
    'suitability': suitability.toJson(),
    'transparency': transparency.toJson(),
  };
}

/// A lender offer surfaced on Loan Options / Detail / Compare.
class LoanProduct {
  const LoanProduct({
    required this.id,
    required this.lender,
    required this.name,
    required this.category,
    required this.minAmount,
    required this.maxAmount,
    required this.interestRate,
    required this.minTenureMonths,
    required this.maxTenureMonths,
    required this.processingFeePercent,
    required this.fynnTrust,
    required this.trustBreakdown,
    this.processingFeeCap,
    this.prepaymentCharge = '',
    this.suitedReasons = const [],
    this.considerations = const [],
    this.conditions = const [],
    this.lenderTag = '',
    this.minMonthlyIncome,
    this.maxAgeAtMaturity,
    this.minAge,
    this.isSampleData = true,
  });

  final String id;
  final String lender;
  final String name;
  final LoanCategory category;
  final double minAmount;
  final double maxAmount;
  final double interestRate; // annual %, reducing balance
  final int minTenureMonths;
  final int maxTenureMonths;
  final double processingFeePercent;
  final double? processingFeeCap;
  final int fynnTrust;
  final TrustBreakdown trustBreakdown;
  final String prepaymentCharge;
  final List<String> suitedReasons;
  final List<String> considerations;
  final List<String> conditions;
  final String lenderTag;

  /// The structured requirements FynnMatch can actually evaluate. Null means
  /// this product does not publish the rule — never that it has none, and
  /// never that the customer passes it.
  final double? minMonthlyIncome;
  final int? maxAgeAtMaturity;
  final int? minAge;

  /// Fictional catalogue data, not a live lender offer.
  final bool isSampleData;

  bool supportsAmount(double amount) =>
      amount >= minAmount && amount <= maxAmount;

  bool supportsTenure(int months) =>
      months >= minTenureMonths && months <= maxTenureMonths;

  int clampTenure(int months) => months.clamp(minTenureMonths, maxTenureMonths);

  double processingFeeFor(double amount) {
    final fee = amount * processingFeePercent / 100;
    final cap = processingFeeCap;
    return cap != null && fee > cap ? cap : fee;
  }

  factory LoanProduct.fromJson(Map<String, dynamic> json) => LoanProduct(
    id: J.str(json['id']),
    lender: J.str(json['lender']),
    name: J.str(json['name']),
    category: LoanCategory.fromId(J.strOrNull(json['category'])),
    minAmount: J.dbl(json['min_amount']),
    maxAmount: J.dbl(json['max_amount']),
    interestRate: J.dbl(json['interest_rate']),
    // Zero, not a plausible-looking range. A product that arrives without
    // a tenure would otherwise be shown as offering 12 to 60 months — a
    // rule nobody published. Zero is incoherent, and [isCoherent] catches
    // it before the product reaches a screen.
    minTenureMonths: J.integer(json['min_tenure_months']),
    maxTenureMonths: J.integer(json['max_tenure_months']),
    processingFeePercent: J.dbl(json['processing_fee_percent']),
    processingFeeCap: J.dblOrNull(json['processing_fee_cap']),
    // Absent is not zero. A product arriving without a trust value would
    // otherwise show "FYNNTRUST 0" as though that were the published
    // evaluation; -1 is outside the scale, so [isCoherent] drops it.
    fynnTrust: json.containsKey('fynn_trust')
        ? J.integer(json['fynn_trust'])
        : -1,
    trustBreakdown: TrustBreakdown.fromJson(J.map(json['trust_breakdown'])),
    prepaymentCharge: J.str(json['prepayment_charge']),
    suitedReasons: J.strings(json['suited_reasons']),
    considerations: J.strings(json['considerations']),
    conditions: J.strings(json['conditions']),
    lenderTag: J.str(json['lender_tag']),
    minMonthlyIncome: J.dblOrNull(json['min_monthly_income']),
    maxAgeAtMaturity: J.intOrNull(json['max_age_at_maturity']),
    minAge: J.intOrNull(json['min_age']),
    // Absent means the flag was not sent, not that the data is live.
    isSampleData: json['is_sample_data'] == null
        ? true
        : J.boolean(json['is_sample_data']),
  );

  /// Whether this record can be reasoned about at all.
  ///
  /// Mirrors the check App\Domain\Catalog\LoanProduct makes when it is
  /// constructed. The server refuses to build an incoherent product; the app
  /// cannot refuse what it is sent, so it drops it instead of rendering
  /// invented ranges as though a lender had published them.
  ///
  /// This is coherence, not quality: a range that runs backwards, a negative
  /// rate, a score outside its own scale. It says nothing about whether the
  /// product is any good.
  bool get isCoherent =>
      id.isNotEmpty &&
      lender.isNotEmpty &&
      name.isNotEmpty &&
      minAmount >= 0 &&
      maxAmount >= minAmount &&
      minTenureMonths >= 1 &&
      maxTenureMonths >= minTenureMonths &&
      interestRate >= 0 &&
      processingFeePercent >= 0 &&
      (processingFeeCap == null || processingFeeCap! >= 0) &&
      fynnTrust >= 0 &&
      fynnTrust <= 100 &&
      (minMonthlyIncome == null || minMonthlyIncome! >= 0) &&
      (minAge == null || (minAge! >= 18 && minAge! <= 100)) &&
      (maxAgeAtMaturity == null ||
          (maxAgeAtMaturity! >= 18 && maxAgeAtMaturity! <= 100)) &&
      (minAge == null ||
          maxAgeAtMaturity == null ||
          minAge! <= maxAgeAtMaturity!);

  Map<String, dynamic> toJson() => {
    'id': id,
    'lender': lender,
    'name': name,
    'category': category.id,
    'min_amount': minAmount,
    'max_amount': maxAmount,
    'interest_rate': interestRate,
    'min_tenure_months': minTenureMonths,
    'max_tenure_months': maxTenureMonths,
    'processing_fee_percent': processingFeePercent,
    'processing_fee_cap': processingFeeCap,
    'fynn_trust': fynnTrust,
    'trust_breakdown': trustBreakdown.toJson(),
    'prepayment_charge': prepaymentCharge,
    'suited_reasons': suitedReasons,
    'considerations': considerations,
    'conditions': conditions,
    'lender_tag': lenderTag,
    'min_monthly_income': minMonthlyIncome,
    'max_age_at_maturity': maxAgeAtMaturity,
    'min_age': minAge,
    'is_sample_data': isSampleData,
  };
}

/// What the customer told us on Loan Discovery (Screen 10).
class LoanRequest {
  const LoanRequest({
    this.amount = 1000000,
    this.purpose = 'business',
    this.preferredEmi = 25000,
    this.tenureMonths = 60,
  });

  final double amount;
  final String purpose;

  /// What the customer said they are comfortable paying. Context for the
  /// screens; it is not a matching rule, and no product documents one.
  final double preferredEmi;
  final int tenureMonths;

  LoanRequest copyWith({
    double? amount,
    String? purpose,
    double? preferredEmi,
    int? tenureMonths,
  }) => LoanRequest(
    amount: amount ?? this.amount,
    purpose: purpose ?? this.purpose,
    preferredEmi: preferredEmi ?? this.preferredEmi,
    tenureMonths: tenureMonths ?? this.tenureMonths,
  );

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'purpose': purpose,
    'preferred_emi': preferredEmi,
    'tenure_months': tenureMonths,
  };
}

/// Output of the EMI engine — see FinanceService.
class EmiResult {
  const EmiResult({
    required this.principal,
    required this.annualRate,
    required this.tenureMonths,
    required this.emi,
    required this.totalInterest,
    required this.totalPayable,
    this.processingFee = 0,
  });

  final double principal;
  final double annualRate;
  final int tenureMonths;
  final double emi;
  final double totalInterest;
  final double totalPayable;
  final double processingFee;

  /// Total cost of credit including one-time fees.
  double get totalCost => totalInterest + processingFee;

  /// Interest as a share of what was borrowed.
  double get interestShare =>
      principal <= 0 ? 0 : (totalInterest / principal) * 100;
}

/// One row of a repayment schedule, used by charts.
class AmortRow {
  const AmortRow({
    required this.month,
    required this.principalPaid,
    required this.interestPaid,
    required this.balance,
  });

  final int month;
  final double principalPaid;
  final double interestPaid;
  final double balance;
}

/// A resolved offer = product + the customer's amount/tenure applied.
/// This is what Loan Options, Compare and FynnMirror actually render.
class LoanOffer {
  const LoanOffer({
    required this.product,
    required this.amount,
    required this.tenureMonths,
    required this.emi,
  });

  final LoanProduct product;
  final double amount;
  final int tenureMonths;
  final EmiResult emi;

  double get processingFee => product.processingFeeFor(amount);
}
