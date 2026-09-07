import '../../core/money/money.dart';
import '../engine/financial_engine.dart';
import '../models/loan.dart';
import '../models/match.dart';
import '../services/finance_service.dart';

/// FynnMatch — the Flutter mirror of App\Domain\Match\FynnMatchEngine.
///
/// **The backend is authoritative.** This exists so mock mode runs the same
/// matching rules rather than a second, invented set, and so an edited
/// financial profile changes the result the same way in both modes.
///
/// WHAT THIS IS NOT: underwriting, an approval engine, an eligibility ruling,
/// or a probability of approval. It answers one question — which products
/// appear to fit this customer's stated need and financial situation — and
/// every result says the lender decides.
///
/// RULES IMPLEMENTED, each from an attribute the catalogue actually carries:
/// purpose, amount, tenure, minimum income, age at maturity, and affordability
/// against the 45% ceiling the product already defines.
///
/// RULES DELIBERATELY NOT IMPLEMENTED, because neither the catalogue nor the
/// customer record holds the data: business vintage, GST returns, audited
/// financials, minimum turnover, property valuation and title, and credit
/// history of any kind. Those report themselves unavailable rather than
/// quietly passing.
///
/// There is no numeric match score — FynnEdge defines no weights, so a ranking
/// number would be a guess wearing arithmetic.
///
/// test/fynn_match_parity_test.dart asserts this against a fixture the Laravel
/// engine generated. If the two diverge, that test fails.
class FynnMatchEngine {
  const FynnMatchEngine([this._finance = const FinanceService()]);

  final FinanceService _finance;

  /// Defined by the Financial Engine and referenced here, so there is
  /// exactly one of it in the product.
  static const double affordabilityCeilingPercent =
      FinancialEngine.affordabilityCeilingPercent;

  static const String disclaimer =
      'This is how these products line up against the information FynnEdge '
      'holds. It is not an approval, and not a lender decision. Final terms '
      'and eligibility are assessed by the provider.';

  MatchResult match({
    required List<LoanProduct> products,
    required MatchRequest request,
    required FinancialSnapshot financials,
    int? customerAge,
  }) {
    final matches = products
        .map(
          (p) => evaluate(
            product: p,
            request: request,
            financials: financials,
            customerAge: customerAge,
          ),
        )
        .toList();

    // Best category first, then the product's own FynnTrust, then id.
    // Fully deterministic: no tie is left to list order.
    matches.sort((a, b) {
      final byCategory = a.category.rank.compareTo(b.category.rank);
      if (byCategory != 0) return byCategory;
      final byTrust = b.product.fynnTrust.compareTo(a.product.fynnTrust);
      if (byTrust != 0) return byTrust;
      return a.product.id.compareTo(b.product.id);
    });

    return MatchResult(
      request: request,
      matches: matches,
      disclaimer: disclaimer,
      // The same engine call with no new EMI: current position, ceiling and
      // the headroom under it.
      affordability: const FinancialEngine().project(financials, Money.zero),
      hasFinancialProfile: financials.income.isPositive,
      isSampleCatalogue: products.every((p) => p.isSampleData),
      affordabilityCeilingPercent: affordabilityCeilingPercent,
    );
  }

  ProductMatch evaluate({
    required LoanProduct product,
    required MatchRequest request,
    required FinancialSnapshot financials,
    int? customerAge,
  }) {
    final criteria = <MatchCriterion>[
      _purpose(product, request),
      _amount(product, request),
      _tenure(product, request),
      _income(product, financials),
      _age(product, request, customerAge),
    ];

    // Price the product at what it can actually offer. The amount is never
    // changed — an out-of-range amount is a failed criterion, not a quiet
    // substitution — but the tenure is clamped so the EMI shown is one the
    // product could really give.
    final tenure = product.clampTenure(request.tenureMonths);
    final result = _finance.calculate(
      principal: request.amount,
      annualRate: product.interestRate,
      tenureMonths: tenure,
      processingFee: product.processingFeeFor(request.amount),
    );
    final emi = _round(result.emi);

    // One projection, used by the affordability criterion, by the match and
    // by every screen downstream.
    final projection = const FinancialEngine().project(
      financials,
      Money.of(emi),
    );

    criteria.add(_affordabilityCriterion(projection));

    return ProductMatch(
      product: product,
      category: _categorise(criteria),
      criteria: criteria,
      projection: projection,
      pricing: MatchPricing(
        amount: request.amount,
        tenureMonths: tenure,
        tenureWasAdjusted: tenure != request.tenureMonths,
        interestRate: product.interestRate,
        emi: emi,
        totalInterest: _round(result.totalInterest),
        totalPayable: _round(result.totalPayable),
        processingFee: _round(result.processingFee),
        projectedEmiRatio: projection.isMeasurable
            ? projection.projectedEmiRatio.value
            : null,
      ),
    );
  }

  /// A documented rule failing is decisive. Otherwise a caution asks the
  /// customer to look, and an unchecked criterion means we claim less.
  MatchCategory _categorise(List<MatchCriterion> criteria) {
    bool any(CriterionStatus s) => criteria.any((c) => c.status == s);

    if (any(CriterionStatus.failed)) return MatchCategory.notAMatch;
    if (any(CriterionStatus.caution)) return MatchCategory.review;
    if (any(CriterionStatus.unavailable)) return MatchCategory.goodMatch;
    return MatchCategory.strongMatch;
  }

  MatchCriterion _purpose(LoanProduct p, MatchRequest r) {
    final purpose = r.purpose;
    if (purpose == null) {
      return const MatchCriterion(
        key: 'purpose',
        label: 'Purpose',
        status: CriterionStatus.unavailable,
        detail: 'You have not told us what the money is for.',
      );
    }

    final wanted = categoryForPurpose(purpose);
    if (wanted == null) {
      return const MatchCriterion(
        key: 'purpose',
        label: 'Purpose',
        status: CriterionStatus.unavailable,
        detail: 'No product category maps to that purpose yet.',
      );
    }

    final matches = wanted == p.category;
    return MatchCriterion(
      key: 'purpose',
      label: 'Purpose',
      status: matches ? CriterionStatus.passed : CriterionStatus.failed,
      detail: matches
          ? 'This is a ${_categoryLabel(p.category)}, which is what you asked for.'
          : 'This is a ${_categoryLabel(p.category)}, not what you asked for.',
      source: 'category',
    );
  }

  MatchCriterion _amount(LoanProduct p, MatchRequest r) {
    if (p.supportsAmount(r.amount)) {
      return MatchCriterion(
        key: 'amount',
        label: 'Amount',
        status: CriterionStatus.passed,
        detail:
            'Your ${_money(r.amount)} sits inside this product\'s '
            '${_money(p.minAmount)} to ${_money(p.maxAmount)} range.',
        source: 'requested_amount',
      );
    }

    final tooSmall = r.amount < p.minAmount;
    return MatchCriterion(
      key: 'amount',
      label: 'Amount',
      status: CriterionStatus.failed,
      detail: tooSmall
          ? 'This product starts at ${_money(p.minAmount)}, above your '
                '${_money(r.amount)} request.'
          : 'This product stops at ${_money(p.maxAmount)}, below your '
                '${_money(r.amount)} request.',
      source: 'requested_amount',
    );
  }

  MatchCriterion _tenure(LoanProduct p, MatchRequest r) {
    if (p.supportsTenure(r.tenureMonths)) {
      return MatchCriterion(
        key: 'tenure',
        label: 'Tenure',
        status: CriterionStatus.passed,
        detail:
            'Your ${_months(r.tenureMonths)} term is available on this product.',
        source: 'requested_tenure',
      );
    }

    return MatchCriterion(
      key: 'tenure',
      label: 'Tenure',
      status: CriterionStatus.caution,
      detail:
          'This product runs ${_months(p.minTenureMonths)} to '
          '${_months(p.maxTenureMonths)}, so the figures below use '
          '${_months(p.clampTenure(r.tenureMonths))} rather than the '
          '${_months(r.tenureMonths)} you asked for.',
      source: 'requested_tenure',
    );
  }

  MatchCriterion _income(LoanProduct p, FinancialSnapshot f) {
    final minimum = p.minMonthlyIncome;
    if (minimum == null) {
      return const MatchCriterion(
        key: 'minimum_income',
        label: 'Minimum income',
        status: CriterionStatus.unavailable,
        detail: 'This product does not publish a minimum income.',
      );
    }

    if (!f.income.isPositive) {
      return const MatchCriterion(
        key: 'minimum_income',
        label: 'Minimum income',
        status: CriterionStatus.unavailable,
        detail: 'Add your monthly income and we can check this.',
      );
    }

    final meets = f.income.paise >= Money.of(minimum).paise;
    return MatchCriterion(
      key: 'minimum_income',
      label: 'Minimum income',
      status: meets ? CriterionStatus.passed : CriterionStatus.failed,
      detail: meets
          ? 'Your income meets this product\'s ${_money(minimum)} minimum.'
          : 'This product requires ${_money(minimum)} a month; yours is '
                '${_moneyOf(f.income)}.',
      source: 'monthly_income',
    );
  }

  MatchCriterion _age(LoanProduct p, MatchRequest r, int? age) {
    if (p.minAge == null && p.maxAgeAtMaturity == null) {
      return const MatchCriterion(
        key: 'age',
        label: 'Age',
        status: CriterionStatus.unavailable,
        detail: 'This product does not publish an age requirement.',
      );
    }

    if (age == null) {
      return const MatchCriterion(
        key: 'age',
        label: 'Age',
        status: CriterionStatus.unavailable,
        detail: 'Add your age and we can check this.',
      );
    }

    final minAge = p.minAge;
    if (minAge != null && age < minAge) {
      return MatchCriterion(
        key: 'age',
        label: 'Age',
        status: CriterionStatus.failed,
        detail: 'This product starts at $minAge.',
        source: 'age',
      );
    }

    final tenure = p.clampTenure(r.tenureMonths);
    final ageAtMaturity = age + (tenure / 12).ceil();
    final maxAtMaturity = p.maxAgeAtMaturity;

    if (maxAtMaturity != null && ageAtMaturity > maxAtMaturity) {
      return MatchCriterion(
        key: 'age',
        label: 'Age',
        status: CriterionStatus.failed,
        detail:
            'You would be $ageAtMaturity when this loan ends; the product\'s '
            'limit is $maxAtMaturity.',
        source: 'age',
      );
    }

    return const MatchCriterion(
      key: 'age',
      label: 'Age',
      status: CriterionStatus.passed,
      detail: 'You are inside this product\'s age requirement.',
      source: 'age',
    );
  }

  /// Beyond the ceiling is a warning, not a rejection: no product in the
  /// catalogue documents an EMI-ratio rule, so treating it as a blocker would
  /// be FynnEdge inventing a lender's policy.
  MatchCriterion _affordabilityCriterion(LoanProjection projection) {
    if (!projection.isMeasurable) {
      return const MatchCriterion(
        key: 'affordability',
        label: 'Affordability',
        status: CriterionStatus.unavailable,
        detail:
            'Add your monthly income and we can work out what this would '
            'cost you each month.',
      );
    }

    final projected = projection.projectedEmiRatio.value;

    if (!projection.withinCeiling) {
      return MatchCriterion(
        key: 'affordability',
        label: 'Affordability',
        status: CriterionStatus.caution,
        detail:
            'With your existing EMIs this would take ${_percent(projected)}% '
            'of your income, past the '
            '${_percent(affordabilityCeilingPercent)}% FynnEdge uses as its '
            "affordability reference. That is FynnEdge's reference, not a "
            'lender rule.',
        source: 'emi_ratio',
      );
    }

    return MatchCriterion(
      key: 'affordability',
      label: 'Affordability',
      status: CriterionStatus.passed,
      detail:
          'With your existing EMIs this would take ${_percent(projected)}% of '
          'your income, inside the ${_percent(affordabilityCeilingPercent)}% '
          'FynnEdge uses as its affordability reference.',
      source: 'emi_ratio',
    );
  }

  /// A purpose the given category serves.
  ///
  /// The inverse of [categoryForPurpose], for the case where the customer has
  /// already picked the product: evaluating it against a purpose it cannot
  /// serve would report a mismatch they did not make.
  static String? purposeForCategory(LoanCategory category) =>
      switch (category) {
        LoanCategory.business => 'business',
        LoanCategory.home => 'home',
        LoanCategory.lap => 'property',
        LoanCategory.personal => 'personal',
      };

  /// Which product category serves a stated purpose.
  static LoanCategory? categoryForPurpose(String purpose) => switch (purpose) {
    'business' => LoanCategory.business,
    'home' => LoanCategory.home,
    'property' => LoanCategory.lap,
    'personal' ||
    'education' ||
    'medical' ||
    'car' ||
    'debt' ||
    'other' => LoanCategory.personal,
    _ => null,
  };

  static String _categoryLabel(LoanCategory category) => switch (category) {
    LoanCategory.personal => 'personal loan',
    LoanCategory.business => 'business loan',
    LoanCategory.home => 'home loan',
    LoanCategory.lap => 'loan against property',
  };

  static String _months(int months) {
    if (months < 12) return '$months month${months == 1 ? '' : 's'}';
    final years = months ~/ 12;
    final rest = months % 12;
    return rest == 0
        ? '$years year${years == 1 ? '' : 's'}'
        : '${years}y ${rest}m';
  }

  static String _percent(double value) {
    var text = value.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }

  static double _round(double value) => double.parse(value.toStringAsFixed(2));

  static String _money(double rupees) => _moneyOf(Money.of(rupees));

  /// Indian digit grouping, matching the rest of the product.
  static String _moneyOf(Money money) {
    final whole = Money.divideHalfUp(money.paise, 100).abs().toString();
    if (whole.length <= 3) return '₹$whole';

    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);

    return '₹${parts.join(',')},$last3';
  }
}

/// The single instance. Const, stateless, and safe to share.
const FynnMatchEngine fynnMatchEngine = FynnMatchEngine();
