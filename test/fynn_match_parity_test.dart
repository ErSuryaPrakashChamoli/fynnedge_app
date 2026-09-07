import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/core/money/money.dart';
import 'package:fynnedge/data/engine/financial_engine.dart';
import 'package:fynnedge/data/match/fynn_match_engine.dart';
import 'package:fynnedge/data/mock/mock_data.dart';
import 'package:fynnedge/data/models/match.dart';

/// Proves the Flutter matching engine agrees with the Laravel one, case for
/// case, against the fixture the backend generated.
///
/// If either engine changes a rule, a category boundary, the ordering or a
/// rounding step, this fails — which is the point: mock mode and the real API
/// must never tell a customer two different things about the same product.
void main() {
  const engine = FynnMatchEngine();
  const financial = FinancialEngine();

  final file = File('test/fixtures/fynnmatch_parity.json');
  if (!file.existsSync()) {
    test('the match parity fixture is present', () {
      fail(
        'test/fixtures/fynnmatch_parity.json is missing. Regenerate with:\n'
        '  cd ../fynnedge-api && php artisan fynn:parity-fixture',
      );
    });
    return;
  }

  final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  MatchResult run(Map<String, dynamic> input) {
    final profile = input['profile'] as Map<String, dynamic>;
    final request = input['request'] as Map<String, dynamic>;

    return engine.match(
      products: MockData.products,
      request: MatchRequest(
        amount: Money.of(request['amount']).rupees,
        tenureMonths: request['tenure_months'] as int,
        purpose: request['purpose'] as String?,
      ),
      financials: financial.snapshot(
        income: Money.of(profile['monthly_income']),
        expenses: Money.of(profile['monthly_expenses']),
        existingEmi: Money.of(profile['existing_emi']),
        otherObligations: Money.of(profile['other_obligations']),
        savings: Money.of(profile['savings']),
      ),
      customerAge: input['age'] as int?,
    );
  }

  test('the ceiling and disclaimer are the backend\'s, not a second copy', () {
    expect(
      fixture['affordability_ceiling_percent'],
      FynnMatchEngine.affordabilityCeilingPercent,
    );
    expect(fixture['disclaimer'], FynnMatchEngine.disclaimer);
  });

  test('the matrix covers every required situation', () {
    final names = cases.map((c) => c['name'] as String).toList();
    for (final required in const [
      'strong_fit_personal',
      'amount_outside_product_range',
      'income_below_requirement',
      'emi_beyond_affordability_ceiling',
      'multiple_business_matches',
      'no_matching_products',
      'incomplete_financial_profile',
      'determinism_repeat',
    ]) {
      expect(names, contains(required), reason: 'fixture case missing');
    }
  });

  test('the mock catalogue is the one the backend evaluated', () {
    // Every product in an expected result must exist here with the same
    // limits and the same documented requirements. A catalogue that drifted
    // would make every case below pass for the wrong reason.
    final expected = <String, Map<String, dynamic>>{};
    for (final c in cases) {
      for (final m in (c['expected']['matches'] as List)) {
        final p =
            (m as Map<String, dynamic>)['product'] as Map<String, dynamic>;
        expected[p['id'] as String] = p;
      }
    }

    expect(expected.length, MockData.products.length);

    for (final product in MockData.products) {
      final backend = expected[product.id];
      expect(backend, isNotNull, reason: '${product.id} is not in the fixture');

      expect(product.lender, backend!['lender']);
      expect(product.category.id, backend['category']);
      expect(product.minAmount, Money.of(backend['min_amount']).rupees);
      expect(product.maxAmount, Money.of(backend['max_amount']).rupees);
      expect(product.interestRate, backend['interest_rate']);
      expect(product.minTenureMonths, backend['min_tenure_months']);
      expect(product.maxTenureMonths, backend['max_tenure_months']);
      expect(product.fynnTrust, backend['fynn_trust']);
      expect(product.isSampleData, backend['is_sample_data']);

      expect(
        product.minMonthlyIncome,
        backend['min_monthly_income'] == null
            ? isNull
            : Money.of(backend['min_monthly_income']).rupees,
        reason: '${product.id}: a documented minimum income diverged',
      );
      expect(product.minAge, backend['min_age']);
      expect(product.maxAgeAtMaturity, backend['max_age_at_maturity']);
    }
  });

  for (final testCase in cases) {
    final name = testCase['name'] as String;
    final expected = testCase['expected'] as Map<String, dynamic>;
    final expectedMatches = (expected['matches'] as List)
        .cast<Map<String, dynamic>>();

    test('$name — ${testCase['note']}', () {
      final result = run(testCase['input'] as Map<String, dynamic>);

      expect(result.evaluatedCount, expected['evaluated_count']);
      expect(result.matchCount, expected['match_count']);

      // Ordering is part of the contract, so compare position by position.
      expect(
        result.matches.map((m) => m.product.id).toList(),
        expectedMatches.map((m) => m['product']['id']).toList(),
        reason: '$name: the two engines ordered the products differently',
      );

      for (var i = 0; i < expectedMatches.length; i++) {
        final actual = result.matches[i];
        final want = expectedMatches[i];
        final wantMatch = want['match'] as Map<String, dynamic>;
        final wantPricing = want['pricing'] as Map<String, dynamic>;
        final where = '$name / ${actual.product.id}';

        expect(actual.category.id, wantMatch['category'], reason: where);
        expect(actual.category.label, wantMatch['label'], reason: where);
        expect(actual.isViable, wantMatch['is_viable'], reason: where);

        final wantCriteria = (wantMatch['criteria'] as List)
            .cast<Map<String, dynamic>>();
        expect(actual.criteria.length, wantCriteria.length, reason: where);

        for (var c = 0; c < wantCriteria.length; c++) {
          final got = actual.criteria[c];
          expect(got.key, wantCriteria[c]['key'], reason: where);
          expect(got.label, wantCriteria[c]['label'], reason: where);
          expect(got.status.id, wantCriteria[c]['status'], reason: where);
          // The sentence itself, because the wording is what says whether a
          // rule was checked or merely skipped.
          expect(got.detail, wantCriteria[c]['detail'], reason: where);
          expect(got.source, wantCriteria[c]['source'], reason: where);
        }

        expect(actual.fits, wantMatch['fits'], reason: where);
        expect(actual.check, wantMatch['check'], reason: where);
        expect(actual.blockers, wantMatch['blockers'], reason: where);
        expect(actual.notAssessed, wantMatch['not_assessed'], reason: where);

        expect(
          actual.pricing.tenureMonths,
          wantPricing['tenure_months'],
          reason: where,
        );
        expect(
          actual.pricing.tenureWasAdjusted,
          wantPricing['tenure_was_adjusted'],
          reason: where,
        );
        expect(actual.pricing.emi, _num(wantPricing['emi']), reason: where);
        expect(
          actual.pricing.totalInterest,
          _num(wantPricing['total_interest']),
          reason: where,
        );
        expect(
          actual.pricing.totalPayable,
          _num(wantPricing['total_payable']),
          reason: where,
        );
        expect(
          actual.pricing.processingFee,
          _num(wantPricing['processing_fee']),
          reason: where,
        );
        expect(
          actual.pricing.projectedEmiRatio,
          _numOrNull(wantPricing['projected_emi_ratio']),
          reason: where,
        );

        // The before/after projection both screens render.
        final wantProjection = want['projection'] as Map<String, dynamic>;
        final p = actual.projection;
        expect(p.emi.rupees, _num(wantProjection['emi']), reason: where);
        expect(
          p.currentOutgo.rupees,
          _num(wantProjection['current']['monthly_outgo']),
          reason: where,
        );
        expect(
          p.currentSurplus.rupees,
          _num(wantProjection['current']['surplus']),
          reason: where,
        );
        expect(
          p.currentEmiRatio.value,
          _num(wantProjection['current']['emi_ratio']),
          reason: where,
        );
        expect(
          p.projectedOutgo.rupees,
          _num(wantProjection['projected']['monthly_outgo']),
          reason: where,
        );
        expect(
          p.projectedSurplus.rupees,
          _num(wantProjection['projected']['surplus']),
          reason: where,
        );
        expect(
          p.projectedEmiRatio.value,
          _num(wantProjection['projected']['emi_ratio']),
          reason: where,
        );
        expect(
          p.emiCeiling.rupees,
          _num(wantProjection['emi_ceiling']),
          reason: where,
        );
        expect(
          p.headroomBefore.rupees,
          _num(wantProjection['headroom_before']),
          reason: where,
        );
        expect(
          p.headroomAfter.rupees,
          _num(wantProjection['headroom_after']),
          reason: where,
        );
        expect(
          p.withinCeiling,
          wantProjection['within_ceiling'],
          reason: where,
        );
        expect(
          p.exhaustsSurplus,
          wantProjection['exhausts_surplus'],
          reason: where,
        );
        expect(p.isMeasurable, wantProjection['is_measurable'], reason: where);
        expect(
          wantProjection['is_estimate'],
          isTrue,
          reason:
              '$where: a projection must always declare itself an '
              'estimate',
        );
        expect(
          wantProjection['ceiling_percent'],
          FynnMatchEngine.affordabilityCeilingPercent,
          reason: where,
        );
      }
    });
  }

  test('the same inputs produce the same result every run', () {
    final input = cases.firstWhere(
      (c) => c['name'] == 'multiple_business_matches',
    )['input'];

    final first = run(input as Map<String, dynamic>);
    final second = run(input);

    expect(jsonEncode(second.toJson()), jsonEncode(first.toJson()));
  });

  test('a match never claims an approval', () {
    for (final testCase in cases) {
      final result = run(testCase['input'] as Map<String, dynamic>);

      // FynnMatch's own words only — a product description may legitimately
      // describe a lender's process.
      final ours = <String>[
        result.disclaimer,
        for (final m in result.matches) ...[
          m.category.label,
          for (final c in m.criteria) '${c.label} ${c.detail}',
        ],
      ].join(' ').toLowerCase();

      for (final forbidden in const [
        'approved',
        'guaranteed',
        'pre-approved',
        'eligible for',
        'you qualify',
        'credit score',
        'cibil',
      ]) {
        expect(
          ours,
          isNot(contains(forbidden)),
          reason: '${testCase['name']}: FynnMatch implied "$forbidden"',
        );
      }
    }
  });
}

double _num(Object? value) => (value as num).toDouble();

double? _numOrNull(Object? value) => value == null ? null : _num(value);
