import '../engine/financial_engine.dart';
import 'json.dart';
import 'loan.dart';

/// The outcome of one documented rule.
///
/// [unavailable] exists so the engine can say "not checked" out loud.
/// Claiming a criterion is met when it was never checked is how a matching
/// layer starts implying approval it has no basis for.
enum CriterionStatus {
  passed('passed'),
  failed('failed'),
  caution('caution'),
  unavailable('unavailable');

  const CriterionStatus(this.id);
  final String id;

  static CriterionStatus fromId(String? id) => J.enumById(
    CriterionStatus.values,
    id,
    (s) => s.id,
    CriterionStatus.unavailable,
  );
}

/// One rule, its outcome, and the sentence shown to the customer.
class MatchCriterion {
  const MatchCriterion({
    required this.key,
    required this.label,
    required this.status,
    required this.detail,
    this.source,
  });

  final String key;
  final String label;
  final CriterionStatus status;
  final String detail;

  /// Which customer field or product attribute decided this, so the UI can
  /// send someone to the right screen to fix it.
  final String? source;

  bool get isPassed => status == CriterionStatus.passed;
  bool get isFailed => status == CriterionStatus.failed;
  bool get isUnavailable => status == CriterionStatus.unavailable;

  factory MatchCriterion.fromJson(Map<String, dynamic> json) => MatchCriterion(
    key: J.str(json['key']),
    label: J.str(json['label']),
    status: CriterionStatus.fromId(J.strOrNull(json['status'])),
    detail: J.str(json['detail']),
    source: J.strOrNull(json['source']),
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'status': status.id,
    'detail': detail,
    'source': source,
  };
}

/// How well a product lines up — never how likely a lender is to approve.
enum MatchCategory {
  strongMatch('strong_match', 'Strong Match', 0, true),
  goodMatch('good_match', 'Good Match', 1, true),
  review('review', 'Worth a Look', 2, true),
  notAMatch('not_a_match', 'Not a Match', 3, false);

  const MatchCategory(this.id, this.label, this.rank, this.isViable);
  final String id;
  final String label;
  final int rank;
  final bool isViable;

  static MatchCategory fromId(String? id) => J.enumById(
    MatchCategory.values,
    id,
    (c) => c.id,
    MatchCategory.notAMatch,
  );
}

/// What the customer asked for. Held verbatim; FynnMatch never rewrites the
/// request to make a product fit.
class MatchRequest {
  const MatchRequest({
    required this.amount,
    required this.tenureMonths,
    this.purpose,
    this.preferredEmi,
  });

  final double amount;
  final int tenureMonths;
  final String? purpose;
  final double? preferredEmi;

  MatchRequest copyWith({
    double? amount,
    int? tenureMonths,
    String? purpose,
    double? preferredEmi,
  }) => MatchRequest(
    amount: amount ?? this.amount,
    tenureMonths: tenureMonths ?? this.tenureMonths,
    purpose: purpose ?? this.purpose,
    preferredEmi: preferredEmi ?? this.preferredEmi,
  );

  factory MatchRequest.fromJson(Map<String, dynamic> json) => MatchRequest(
    amount: J.dbl(json['amount']),
    tenureMonths: J.integer(json['tenure_months'], 60),
    purpose: J.strOrNull(json['purpose']),
    preferredEmi: J.dblOrNull(json['preferred_emi']),
  );

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'tenure_months': tenureMonths,
    'purpose': purpose,
    'preferred_emi': preferredEmi,
  };

  /// Query parameters for GET /fynn-match. There is deliberately no customer
  /// identifier here: whose finances are evaluated comes from the token.
  Map<String, Object> toQuery() => {
    'amount': amount,
    'tenure_months': tenureMonths,
    'purpose': ?purpose,
    'preferred_emi': ?preferredEmi,
  };
}

/// The figures for one product priced at what it can actually offer.
class MatchPricing {
  const MatchPricing({
    required this.amount,
    required this.tenureMonths,
    required this.tenureWasAdjusted,
    required this.interestRate,
    required this.emi,
    required this.totalInterest,
    required this.totalPayable,
    required this.processingFee,
    this.projectedEmiRatio,
  });

  final double amount;
  final int tenureMonths;
  final bool tenureWasAdjusted;
  final double interestRate;
  final double emi;
  final double totalInterest;
  final double totalPayable;
  final double processingFee;

  /// Null when there is no income on file to measure against.
  final double? projectedEmiRatio;

  factory MatchPricing.fromJson(Map<String, dynamic> json) => MatchPricing(
    amount: J.dbl(json['amount']),
    tenureMonths: J.integer(json['tenure_months'], 0),
    tenureWasAdjusted: J.boolean(json['tenure_was_adjusted']),
    interestRate: J.dbl(json['interest_rate']),
    emi: J.dbl(json['emi']),
    totalInterest: J.dbl(json['total_interest']),
    totalPayable: J.dbl(json['total_payable']),
    processingFee: J.dbl(json['processing_fee']),
    projectedEmiRatio: J.dblOrNull(json['projected_emi_ratio']),
  );

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'tenure_months': tenureMonths,
    'tenure_was_adjusted': tenureWasAdjusted,
    'interest_rate': interestRate,
    'emi': emi,
    'total_interest': totalInterest,
    'total_payable': totalPayable,
    'processing_fee': processingFee,
    'projected_emi_ratio': projectedEmiRatio,
  };
}

/// One product evaluated against one customer's request and finances.
class ProductMatch {
  const ProductMatch({
    required this.product,
    required this.category,
    required this.criteria,
    required this.pricing,
    required this.projection,
  });

  final LoanProduct product;
  final MatchCategory category;
  final List<MatchCriterion> criteria;
  final MatchPricing pricing;

  /// The customer's position now and with this loan on it, from the
  /// Financial Engine. Every before/after figure on any screen reads this.
  final LoanProjection projection;

  bool get isViable => category.isViable;

  List<MatchCriterion> _with(CriterionStatus status) =>
      criteria.where((c) => c.status == status).toList();

  /// What lined up, what to look at, what stops this outright, and what we
  /// could not check at all.
  List<String> get fits =>
      _with(CriterionStatus.passed).map((c) => c.detail).toList();
  List<String> get check =>
      _with(CriterionStatus.caution).map((c) => c.detail).toList();
  List<String> get blockers =>
      _with(CriterionStatus.failed).map((c) => c.detail).toList();
  List<String> get notAssessed =>
      _with(CriterionStatus.unavailable).map((c) => c.label).toList();

  /// The offer shape the existing Loan Detail and Compare screens render.
  LoanOffer get offer => LoanOffer(
    product: product,
    amount: pricing.amount,
    tenureMonths: pricing.tenureMonths,
    emi: EmiResult(
      principal: pricing.amount,
      annualRate: pricing.interestRate,
      tenureMonths: pricing.tenureMonths,
      emi: pricing.emi,
      totalInterest: pricing.totalInterest,
      totalPayable: pricing.totalPayable,
      processingFee: pricing.processingFee,
    ),
  );

  factory ProductMatch.fromJson(Map<String, dynamic> json) {
    final match = J.map(json['match']);
    return ProductMatch(
      product: LoanProduct.fromJson(J.map(json['product'])),
      category: MatchCategory.fromId(J.strOrNull(match['category'])),
      criteria: J
          .list(match['criteria'])
          .map((e) => MatchCriterion.fromJson(J.map(e)))
          .toList(),
      pricing: MatchPricing.fromJson(J.map(json['pricing'])),
      projection: LoanProjection.fromJson(J.map(json['projection'])),
    );
  }

  Map<String, dynamic> toJson() => {
    'product': product.toJson(),
    'match': {
      'category': category.id,
      'label': category.label,
      'is_viable': category.isViable,
      'criteria': criteria.map((c) => c.toJson()).toList(),
      'fits': fits,
      'check': check,
      'blockers': blockers,
      'not_assessed': notAssessed,
    },
    'pricing': pricing.toJson(),
    'projection': projection.toJson(),
  };
}

/// Everything FynnMatch found for one request.
class MatchResult {
  const MatchResult({
    required this.request,
    required this.matches,
    required this.disclaimer,
    required this.affordability,
    this.hasFinancialProfile = false,
    this.isSampleCatalogue = true,
    this.affordabilityCeilingPercent =
        FinancialEngine.affordabilityCeilingPercent,
  });

  final MatchRequest request;

  /// Every product evaluated, best fit first — including the ones that do not
  /// fit, so the app can say why rather than showing an unexplained gap.
  final List<ProductMatch> matches;
  final String disclaimer;
  final bool hasFinancialProfile;
  final bool isSampleCatalogue;
  final double affordabilityCeilingPercent;

  /// Where the customer stands with no new loan on them: current EMI share,
  /// the ceiling, and what is still under it.
  final LoanProjection affordability;

  List<ProductMatch> get viable =>
      matches.where((m) => m.isViable).toList(growable: false);

  List<ProductMatch> get rejected =>
      matches.where((m) => !m.isViable).toList(growable: false);

  int get matchCount => viable.length;
  int get evaluatedCount => matches.length;
  bool get isEmpty => viable.isEmpty;

  ProductMatch? byId(String id) {
    for (final m in matches) {
      if (m.product.id == id) return m;
    }
    return null;
  }

  factory MatchResult.fromJson(Map<String, dynamic> json) => MatchResult(
    request: MatchRequest.fromJson(J.map(json['request'])),
    matches: J
        .list(json['matches'])
        .map((e) => ProductMatch.fromJson(J.map(e)))
        .toList(),
    disclaimer: J.str(json['disclaimer']),
    affordability: LoanProjection.fromJson(J.map(json['affordability'])),
    hasFinancialProfile: J.boolean(json['has_financial_profile']),
    isSampleCatalogue: json['is_sample_catalogue'] == null
        ? true
        : J.boolean(json['is_sample_catalogue']),
    affordabilityCeilingPercent: J.dbl(json['affordability_ceiling_percent']),
  );

  Map<String, dynamic> toJson() => {
    'request': request.toJson(),
    'matches': matches.map((m) => m.toJson()).toList(),
    'match_count': matchCount,
    'evaluated_count': evaluatedCount,
    'has_financial_profile': hasFinancialProfile,
    'is_sample_catalogue': isSampleCatalogue,
    'affordability_ceiling_percent': affordabilityCeilingPercent,
    'affordability': affordability.toJson(),
    'disclaimer': disclaimer,
  };
}
