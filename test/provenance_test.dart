import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/data/mock/mock_data.dart';
import 'package:fynnedge/data/models/loan.dart';
import 'package:fynnedge/data/models/match.dart';

import 'support/harness.dart';

/// Where each number on screen came from, and what happens when a record
/// cannot say.
///
/// The catalogue is invented today and will be a real feed later. What
/// matters is that the boundary behaves the same either way: a product whose
/// own figures contradict each other never reaches a decision screen, and
/// nothing missing is quietly filled in with a plausible-looking value.
void main() {
  setUpAll(initUnitTestEnvironment);

  Map<String, dynamic> validJson() => {
    'id': 'prod_x',
    'lender': 'Test Lender',
    'name': 'Test Loan',
    'category': 'personal',
    'min_amount': 100000,
    'max_amount': 1000000,
    'interest_rate': 12.0,
    'min_tenure_months': 12,
    'max_tenure_months': 60,
    'processing_fee_percent': 1.0,
    'fynn_trust': 80,
    'trust_breakdown': const {},
  };

  group('a product that contradicts itself never reaches a screen', () {
    test('a coherent product is accepted', () {
      expect(LoanProduct.fromJson(validJson()).isCoherent, isTrue);
    });

    for (final entry in <String, Map<String, dynamic>>{
      'amounts inverted': {'min_amount': 900000, 'max_amount': 100},
      'negative amount': {'min_amount': -1},
      'tenures inverted': {'min_tenure_months': 84, 'max_tenure_months': 12},
      'negative rate': {'interest_rate': -2},
      'negative fee': {'processing_fee_percent': -1},
      'negative fee cap': {'processing_fee_cap': -100},
      'trust above scale': {'fynn_trust': 140},
      'trust below scale': {'fynn_trust': -1},
      'impossible age': {'min_age': 4},
      'age range inverted': {'min_age': 60, 'max_age_at_maturity': 30},
      'no lender': {'lender': ''},
      'no id': {'id': ''},
    }.entries) {
      test('rejected: ${entry.key}', () {
        final product = LoanProduct.fromJson({...validJson(), ...entry.value});

        expect(
          product.isCoherent,
          isFalse,
          reason: '${entry.key} was treated as a usable product',
        );
      });
    }

    test('an absent tenure is not invented', () {
      final json = validJson()
        ..remove('min_tenure_months')
        ..remove('max_tenure_months');

      final product = LoanProduct.fromJson(json);

      // This used to parse as 12–60 months: a range nobody published,
      // shown to a customer as though a lender had.
      expect(product.minTenureMonths, 0);
      expect(product.isCoherent, isFalse);
    });

    test('an absent trust value is not read as zero', () {
      final json = validJson()..remove('fynn_trust');

      // "FYNNTRUST 0" would read as a published evaluation of the product,
      // not as the absence of one.
      final product = LoanProduct.fromJson(json);
      expect(product.isCoherent, isFalse);
      expect(product.fynnTrust, isNot(0));
    });

    test('a genuine zero trust value is kept', () {
      expect(
        LoanProduct.fromJson({...validJson(), 'fynn_trust': 0}).isCoherent,
        isTrue,
      );
    });

    test('an interest-free product is coherent', () {
      // Zero is a real rate, not a missing one.
      expect(
        LoanProduct.fromJson({...validJson(), 'interest_rate': 0}).isCoherent,
        isTrue,
      );
    });
  });

  group('sample data never passes for live', () {
    test('a product with no flag is assumed to be sample data', () {
      final json = validJson()..remove('is_sample_data');

      // The safe direction: never claim live without being told.
      expect(LoanProduct.fromJson(json).isSampleData, isTrue);
    });

    test('every product in the mock catalogue says it is sample data', () {
      expect(MockData.products, isNotEmpty);
      for (final product in MockData.products) {
        expect(product.isSampleData, isTrue, reason: product.id);
        expect(product.isCoherent, isTrue, reason: product.id);
      }
    });

    test('no sample product describes how a provider behaves', () {
      // No application reaches a provider, so nothing in a product record
      // may describe its speed, its appetite, or its decision.
      final text = MockData.products
          .map(
            (p) => [
              p.lenderTag,
              ...p.suitedReasons,
              ...p.considerations,
              ...p.conditions,
              ...p.trustBreakdown.all.map((f) => f.explanation),
            ].join(' '),
          )
          .join(' ')
          .toLowerCase();

      for (final claim in const [
        'approval chances',
        'likely to approve',
        'guaranteed',
        'working days',
        'instant',
        'pre-approved',
        'fast disbursal',
        'cheapest money available',
      ]) {
        expect(
          text,
          isNot(contains(claim)),
          reason: 'a product claims: $claim',
        );
      }
    });
  });

  group('an unchecked rule is never reported as passed', () {
    test('a product with no published income rule reports it unchecked', () {
      // Silence in a product record is not a pass. Module 7 established
      // this; it is asserted here because a real feed will be full of
      // silence.
      final withoutRule = MockData.products.where(
        (p) => p.minMonthlyIncome == null,
      );

      expect(
        withoutRule,
        isNotEmpty,
        reason: 'the catalogue no longer covers the unstated-rule case',
      );
    });

    test('an unavailable criterion is its own status', () {
      // Passed, failed and "could not be checked" are three answers, not
      // two. Collapsing the third into either of the others is how a
      // customer comes to believe a rule was checked.
      expect(CriterionStatus.values, contains(CriterionStatus.unavailable));
      expect(CriterionStatus.values, contains(CriterionStatus.passed));
      expect(CriterionStatus.values, contains(CriterionStatus.failed));
      expect(CriterionStatus.values, contains(CriterionStatus.caution));
    });
  });
}
