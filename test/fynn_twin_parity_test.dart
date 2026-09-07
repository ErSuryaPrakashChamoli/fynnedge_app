import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/core/money/money.dart';
import 'package:fynnedge/data/engine/financial_engine.dart';
import 'package:fynnedge/data/mock/mock_data.dart';
import 'package:fynnedge/data/models/loan.dart';
import 'package:fynnedge/data/models/twin.dart';
import 'package:fynnedge/data/twin/fynn_twin_engine.dart';

/// Proves the Flutter Twin engine agrees with the Laravel one, case for case,
/// against the fixture the backend generated.
///
/// If either engine changes a projection, a rounding step or an observation,
/// this fails — which is the point: a simulation shown before a request and
/// the answer that comes back must be the same simulation.
void main() {
  final file = File('test/fixtures/fynntwin_parity.json');
  if (!file.existsSync()) {
    test('the Twin parity fixture is present', () {
      fail(
        'test/fixtures/fynntwin_parity.json is missing. Regenerate with:\n'
        '  cd ../fynnedge-api && php artisan fynn:parity-fixture',
      );
    });
    return;
  }

  final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  LoanProduct? productFor(String? id) {
    if (id == null) return null;
    return MockData.products.firstWhere((p) => p.id == id);
  }

  TwinProjection run(Map<String, dynamic> input) {
    final profile = input['profile'] as Map<String, dynamic>;
    final scenario = input['scenario'] as Map<String, dynamic>;

    return fynnTwinEngine.simulate(
      current: financialEngine.snapshot(
        income: Money.of(profile['monthly_income']),
        expenses: Money.of(profile['monthly_expenses']),
        existingEmi: Money.of(profile['existing_emi']),
        otherObligations: Money.of(profile['other_obligations']),
        savings: Money.of(profile['savings']),
      ),
      scenario: TwinScenario(
        type: ScenarioType.fromId(scenario['type'] as String),
        amount: scenario['amount'] == null
            ? null
            : Money.of(scenario['amount']).rupees,
        tenureMonths: scenario['tenure_months'] as int?,
        productId: scenario['product_id'] as String?,
        monthlyChange: scenario['monthly_change'] == null
            ? null
            : Money.of(scenario['monthly_change']).rupees,
        monthlyAmount: scenario['monthly_amount'] == null
            ? null
            : Money.of(scenario['monthly_amount']).rupees,
        months: scenario['months'] as int?,
      ),
      product: productFor(scenario['product_id'] as String?),
    );
  }

  test('the affordability reference is the backend\'s, not a second copy', () {
    expect(
      fixture['affordability_reference_percent'],
      FinancialEngine.affordabilityCeilingPercent,
    );
  });

  test('the matrix covers every situation that matters', () {
    final names = cases.map((c) => c['name'] as String).toList();

    for (final required in const [
      'loan_within_reference',
      'loan_past_reference',
      'loan_into_negative_surplus',
      'spending_more',
      'spending_less',
      'saving_monthly',
      'paise_precision',
      'no_income',
    ]) {
      expect(names, contains(required), reason: 'fixture case missing');
    }
  });

  for (final testCase in cases) {
    final name = testCase['name'] as String;
    final expected = testCase['expected'] as Map<String, dynamic>;

    test('$name — ${testCase['note']}', () {
      final actual = run(testCase['input'] as Map<String, dynamic>);

      // Both sides of the comparison, field for field.
      for (final side in const ['current', 'projected']) {
        final want = expected[side] as Map<String, dynamic>;
        final got = side == 'current' ? actual.current : actual.projected;

        expect(
          got.monthlyIncome,
          _num(want['monthly_income']),
          reason: '$name/$side income',
        );
        expect(
          got.monthlyExpenses,
          _num(want['monthly_expenses']),
          reason: '$name/$side expenses',
        );
        expect(
          got.existingEmi,
          _num(want['existing_emi']),
          reason: '$name/$side emi',
        );
        expect(
          got.savings,
          _num(want['savings']),
          reason: '$name/$side savings',
        );
        expect(
          got.monthlyOutgo,
          _num(want['monthly_outgo']),
          reason: '$name/$side outgo',
        );
        expect(
          got.surplus,
          _num(want['surplus']),
          reason: '$name/$side surplus',
        );
        expect(
          got.emiRatio,
          _num(want['emi_ratio']),
          reason: '$name/$side emi ratio',
        );
        expect(
          got.expenseRatio,
          _num(want['expense_ratio']),
          reason: '$name/$side expense ratio',
        );
        expect(
          got.emergencyMonths,
          _num(want['emergency_months']),
          reason: '$name/$side buffer',
        );
      }

      final difference = expected['difference'] as Map<String, dynamic>;
      expect(
        actual.difference.monthlyOutgo,
        _num(difference['monthly_outgo']),
        reason: name,
      );
      expect(
        actual.difference.surplus,
        _num(difference['surplus']),
        reason: name,
      );
      expect(
        actual.difference.savings,
        _num(difference['savings']),
        reason: name,
      );
      expect(
        actual.difference.emiRatio,
        _num(difference['emi_ratio']),
        reason: name,
      );
      expect(
        actual.difference.emergencyMonths,
        _num(difference['emergency_months']),
        reason: name,
      );

      final affordability = expected['affordability'] as Map<String, dynamic>;
      expect(
        actual.referencePercent,
        _num(affordability['reference_percent']),
        reason: name,
      );
      expect(
        actual.projectedEmiRatio,
        _numOrNull(affordability['projected_emi_ratio']),
        reason: name,
      );
      expect(
        actual.withinReference,
        affordability['within_reference'],
        reason: name,
      );

      // The loan, priced by the product on both sides.
      final loan = expected['loan'] as Map<String, dynamic>?;
      if (loan == null) {
        expect(actual.loan, isNull, reason: name);
      } else {
        expect(actual.loan!.emi, _num(loan['emi']), reason: '$name emi');
        expect(
          actual.loan!.interestRate,
          _num(loan['interest_rate']),
          reason: name,
        );
        expect(
          actual.loan!.totalInterest,
          _num(loan['total_interest']),
          reason: name,
        );
        expect(
          actual.loan!.totalPayable,
          _num(loan['total_payable']),
          reason: name,
        );
        expect(
          actual.loan!.processingFee,
          _num(loan['processing_fee']),
          reason: name,
        );
        expect(actual.loan!.lender, loan['lender'], reason: name);
      }

      // The score, simulated by the same engine on both sides.
      final score = expected['fynn_score'] as Map<String, dynamic>;
      expect(actual.currentScore, score['current'], reason: '$name score');
      expect(actual.projectedScore, score['projected'], reason: '$name score');

      // The observations, in order, with their exact wording — the words are
      // what tell the customer whether a figure was checked or assumed.
      final observations = (expected['observations'] as List)
          .cast<Map<String, dynamic>>();
      expect(actual.observations.length, observations.length, reason: name);

      for (var i = 0; i < observations.length; i++) {
        expect(
          actual.observations[i].key,
          observations[i]['key'],
          reason: name,
        );
        expect(
          actual.observations[i].severity,
          observations[i]['severity'],
          reason: name,
        );
        expect(
          actual.observations[i].detail,
          observations[i]['detail'],
          reason: name,
        );
      }

      expect(actual.isMeasurable, expected['is_measurable'], reason: name);
      expect(expected['is_projection'], isTrue, reason: name);
      expect(actual.disclaimer, expected['disclaimer'], reason: name);
    });
  }

  test('a negative surplus is never clamped away', () {
    final under = cases.firstWhere(
      (c) => c['name'] == 'loan_into_negative_surplus',
    );
    final actual = run(under['input'] as Map<String, dynamic>);

    expect(actual.projected.surplus, lessThan(0));
    expect(actual.observations.map((o) => o.key), contains('negative_surplus'));
  });

  test('the same inputs produce the same projection every run', () {
    final input = cases.first['input'] as Map<String, dynamic>;

    expect(jsonEncode(run(input).toJson()), jsonEncode(run(input).toJson()));
  });

  test('no projection carries an invented composite score', () {
    for (final testCase in cases) {
      final json = jsonEncode(
        run(testCase['input'] as Map<String, dynamic>).toJson(),
      );

      for (final invented in const [
        'impact_score',
        'risk_score',
        'probability',
        'approval',
      ]) {
        expect(
          json,
          isNot(contains(invented)),
          reason: testCase['name'] as String,
        );
      }
    }
  });
}

double _num(Object? value) => (value as num).toDouble();

double? _numOrNull(Object? value) => value == null ? null : _num(value);
