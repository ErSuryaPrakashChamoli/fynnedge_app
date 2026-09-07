import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/app/session.dart';
import 'package:fynnedge/core/money/money.dart';
import 'package:fynnedge/data/engine/financial_engine.dart';
import 'package:fynnedge/data/match/fynn_match_engine.dart';
import 'package:fynnedge/data/mock/mock_data.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/loan.dart';
import 'package:fynnedge/data/models/match.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/match_service.dart';
import 'package:fynnedge/features/loans/compare_screen.dart';
import 'package:fynnedge/features/loans/loan_detail_screen.dart';
import 'package:fynnedge/features/loans/loan_options_screen.dart';

import 'support/harness.dart';

/// A match service each test drives directly.
class FakeMatchService implements MatchService {
  FakeMatchService(this.result);

  MatchResult? result;
  Object? error;
  Duration delay = Duration.zero;
  int calls = 0;
  int simulateCalls = 0;
  MatchRequest? lastRequest;
  MatchRequest? lastSimulation;
  String? lastSimulatedProduct;

  @override
  Future<MatchResult> findMatches(MatchRequest request) async {
    calls++;
    lastRequest = request;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return result!;
  }

  @override
  Future<ProductMatch> simulate(String productId, MatchRequest request) async {
    simulateCalls++;
    lastSimulatedProduct = productId;
    lastSimulation = request;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (error != null) throw error!;

    final match = result!.byId(productId);
    if (match == null) {
      throw ApiException('That product is no longer in our set.');
    }
    // The real services re-evaluate; the fake re-runs the same engine so the
    // figures a test asserts are the engine's, not invented ones.
    return const FynnMatchEngine().evaluate(
      product: match.product,
      request: request,
      financials: _simulationFinancials,
      customerAge: 34,
    );
  }

  /// The customer the fake simulates against — matches the suite's default.
  static final _simulationFinancials = const FinancialEngine().snapshot(
    income: Money.of(100000),
    expenses: Money.of(40000),
    existingEmi: Money.of(20000),
    otherObligations: Money.zero,
    savings: Money.of(180000),
  );
}

void main() {
  const engine = FynnMatchEngine();
  const financial = FinancialEngine();

  FinancialSnapshot snapshotOf({
    double income = 100000,
    double expenses = 40000,
    double emi = 20000,
    double savings = 180000,
  }) => financial.snapshot(
    income: Money.of(income),
    expenses: Money.of(expenses),
    existingEmi: Money.of(emi),
    otherObligations: Money.zero,
    savings: Money.of(savings),
  );

  MatchResult matchFor({
    double amount = 1000000,
    int tenure = 60,
    String? purpose = 'business',
    FinancialSnapshot? financials,
    int? age = 34,
    List<LoanProduct>? products,
  }) => engine.match(
    products: products ?? MockData.products,
    request: MatchRequest(
      amount: amount,
      tenureMonths: tenure,
      purpose: purpose,
    ),
    financials: financials ?? snapshotOf(),
    customerAge: age,
  );

  setUpAll(initTestEnvironment);
  setUp(MockStore.instance.reset);

  // --- The engine --------------------------------------------------------

  group('matching rules', () {
    test('a product for another purpose is not a match', () {
      final result = matchFor(purpose: 'business');

      for (final match in result.matches) {
        if (match.product.category != LoanCategory.business) {
          expect(match.isViable, isFalse);
          expect(match.blockers, isNotEmpty);
        }
      }
    });

    test('an amount outside the range is a blocker, never a silent clamp', () {
      final match = matchFor(
        amount: 200000,
        purpose: 'personal',
      ).byId('prod_pl_a')!;

      expect(match.category, MatchCategory.notAMatch);
      expect(match.pricing.amount, 200000, reason: 'the ask must be kept');
      expect(match.blockers.first, contains('starts at ₹5,00,000'));
    });

    test('income below a published minimum blocks that product', () {
      final result = matchFor(
        amount: 600000,
        purpose: 'personal',
        financials: snapshotOf(income: 25000, expenses: 15000, emi: 0),
      );

      expect(result.byId('prod_pl_a')!.category, MatchCategory.notAMatch);
      expect(result.byId('prod_pl_b')!.category, MatchCategory.notAMatch);
    });

    test('a product publishing no minimum income does not claim one', () {
      final match = matchFor().byId('prod_bl_a')!;
      final income = match.criteria.firstWhere(
        (c) => c.key == 'minimum_income',
      );

      expect(income.status, CriterionStatus.unavailable);
      expect(match.notAssessed, contains('Minimum income'));
      // Never counted as something that passed.
      expect(match.fits.join(), isNot(contains('minimum')));
    });

    test('age past the published limit at maturity blocks that product', () {
      final result = matchFor(amount: 800000, purpose: 'personal', age: 56);

      // Meridian publishes 58 at maturity; 56 + 5 years is 61.
      expect(result.byId('prod_pl_a')!.category, MatchCategory.notAMatch);
      // Northline publishes no age rule, so it must not inherit one.
      expect(result.byId('prod_pl_b')!.isViable, isTrue);
    });

    test('a tenure outside the range is priced honestly and flagged', () {
      final match = matchFor(
        amount: 800000,
        tenure: 6,
        purpose: 'personal',
      ).byId('prod_pl_a')!;

      expect(match.pricing.tenureMonths, 12);
      expect(match.pricing.tenureWasAdjusted, isTrue);
      expect(match.category, MatchCategory.review);
      expect(match.check.first, contains('rather than the 6 months'));
    });

    test('past the affordability ceiling is a caution, not a rejection', () {
      final match = matchFor(
        amount: 600000,
        tenure: 24,
        purpose: 'personal',
        financials: snapshotOf(income: 60000, expenses: 20000, emi: 15000),
      ).byId('prod_pl_a')!;

      expect(match.pricing.projectedEmiRatio, greaterThan(45));
      expect(match.category, MatchCategory.review);
      expect(match.isViable, isTrue, reason: 'we do not underwrite');
    });

    test('the projected ratio counts existing EMIs plus this one', () {
      final match = matchFor().byId('prod_bl_b')!;
      final expected = (20000 + match.pricing.emi) / 100000 * 100;

      expect(match.pricing.projectedEmiRatio, closeTo(expected, 0.01));
    });

    test('with no income on file, nothing is assessed against it', () {
      final result = matchFor(
        purpose: 'personal',
        amount: 800000,
        financials: snapshotOf(income: 0, expenses: 0, emi: 0, savings: 0),
      );
      final match = result.byId('prod_pl_a')!;

      expect(result.hasFinancialProfile, isFalse);
      expect(match.notAssessed, contains('Affordability'));
      expect(match.notAssessed, contains('Minimum income'));
      expect(match.pricing.projectedEmiRatio, isNull);
      expect(match.category, isNot(MatchCategory.strongMatch));
    });

    test('nothing fitting is an empty result, with every reason kept', () {
      final result = matchFor(amount: 500000, tenure: 120, purpose: 'home');

      expect(result.isEmpty, isTrue);
      expect(result.matchCount, 0);
      expect(result.evaluatedCount, MockData.products.length);
      for (final match in result.rejected) {
        expect(match.blockers, isNotEmpty);
      }
    });

    test('the order is stable across runs', () {
      final first = matchFor().matches.map((m) => m.product.id).toList();
      final second = matchFor().matches.map((m) => m.product.id).toList();
      final shuffled = matchFor(products: MockData.products.reversed.toList())
          .matches
          .map((m) => m.product.id)
          .toList();

      expect(second, first);
      expect(shuffled, first, reason: 'catalogue order must not leak through');
    });

    test('viable products sort ahead of the rest', () {
      final ranks = matchFor().matches.map((m) => m.category.rank).toList();
      final sorted = [...ranks]..sort();

      expect(ranks, sorted);
    });

    test('every product is evaluated, fitting or not', () {
      expect(matchFor().evaluatedCount, MockData.products.length);
    });

    test('the catalogue is flagged as sample data', () {
      final result = matchFor();

      expect(result.isSampleCatalogue, isTrue);
      expect(result.matches.every((m) => m.product.isSampleData), isTrue);
    });
  });

  // --- What it must never say --------------------------------------------

  group('what a match is not', () {
    test('it never says approved, eligible or guaranteed', () {
      final ours = [
        FynnMatchEngine.disclaimer,
        for (final m in matchFor().matches) ...[
          m.category.label,
          for (final c in m.criteria) '${c.label} ${c.detail}',
        ],
      ].join(' ').toLowerCase();

      for (final word in const [
        'approved',
        'guaranteed',
        'eligible for',
        'you qualify',
        'pre-approved',
        'likelihood',
        'chances',
        'credit score',
        'cibil',
        'bureau',
      ]) {
        expect(ours, isNot(contains(word)));
      }
    });

    test('there is no numeric match score anywhere in the payload', () {
      final json = jsonEncode(matchFor().toJson());

      for (final key in const [
        'match_score',
        'score',
        'probability',
        'approval',
        'eligibility',
      ]) {
        expect(json, isNot(contains('"$key"')));
      }
    });

    test('the disclaimer names the lender as the decision maker', () {
      expect(FynnMatchEngine.disclaimer, contains('not an approval'));
      expect(FynnMatchEngine.disclaimer, contains('provider'));
      expect(matchFor().disclaimer, FynnMatchEngine.disclaimer);
    });
  });

  // --- Serialization ------------------------------------------------------

  group('serialization', () {
    test('a result survives a JSON round trip', () {
      final original = matchFor();
      final restored = MatchResult.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored.matchCount, original.matchCount);
      expect(restored.evaluatedCount, original.evaluatedCount);
      expect(restored.disclaimer, original.disclaimer);
      expect(restored.hasFinancialProfile, original.hasFinancialProfile);
      expect(restored.isSampleCatalogue, original.isSampleCatalogue);
      expect(
        restored.matches.map((m) => m.product.id),
        original.matches.map((m) => m.product.id),
      );

      for (var i = 0; i < original.matches.length; i++) {
        final a = original.matches[i];
        final b = restored.matches[i];
        expect(b.category, a.category);
        expect(b.pricing.emi, a.pricing.emi);
        expect(b.pricing.projectedEmiRatio, a.pricing.projectedEmiRatio);
        expect(
          b.criteria.map((c) => '${c.key}:${c.status.id}:${c.detail}'),
          a.criteria.map((c) => '${c.key}:${c.status.id}:${c.detail}'),
        );
      }
    });

    test('a criterion status survives, unknown values falling back safely', () {
      expect(CriterionStatus.fromId('passed'), CriterionStatus.passed);
      // An unrecognised status must never read as a pass.
      expect(CriterionStatus.fromId('approved'), CriterionStatus.unavailable);
      expect(CriterionStatus.fromId(null), CriterionStatus.unavailable);
      expect(MatchCategory.fromId('nonsense'), MatchCategory.notAMatch);
    });

    test('a product without the documented fields claims none of them', () {
      final product = LoanProduct.fromJson(const {
        'id': 'p',
        'lender': 'L',
        'name': 'N',
        'category': 'personal',
        'min_amount': 100000,
        'max_amount': 500000,
        'interest_rate': 12.0,
        'min_tenure_months': 12,
        'max_tenure_months': 60,
        'processing_fee_percent': 1.0,
        'fynn_trust': 70,
      });

      expect(product.minMonthlyIncome, isNull);
      expect(product.minAge, isNull);
      expect(product.maxAgeAtMaturity, isNull);
      // Absent flag means unproven, so it is treated as sample data.
      expect(product.isSampleData, isTrue);
    });

    test('the request never carries a customer identifier', () {
      final query = const MatchRequest(
        amount: 1000000,
        tenureMonths: 60,
        purpose: 'business',
      ).toQuery();

      expect(query.keys, ['amount', 'tenure_months', 'purpose']);
      for (final key in query.keys) {
        expect(key, isNot(contains('user')));
        expect(key, isNot(contains('customer')));
      }
    });
  });

  // --- Mock mode ----------------------------------------------------------

  group('mock mode', () {
    test('it runs the same engine over the stored customer', () async {
      final result = await MockMatchService().findMatches(
        const MatchRequest(
          amount: 1000000,
          tenureMonths: 60,
          purpose: 'business',
        ),
      );
      final f = MockStore.instance.financials;

      expect(
        result.matches.map((m) => m.product.id),
        matchFor(
          financials: snapshotOf(
            income: f.monthlyIncome,
            expenses: f.monthlyExpenses,
            emi: f.existingEmi,
            savings: f.savings,
          ),
          age: MockStore.instance.profile.age,
        ).matches.map((m) => m.product.id),
      );
    });

    test('editing the profile changes what mock mode returns', () async {
      const request = MatchRequest(
        amount: 1000000,
        tenureMonths: 60,
        purpose: 'business',
      );
      final service = MockMatchService();

      final before = await service.findMatches(request);
      MockStore.instance.financials = MockStore.instance.financials.copyWith(
        existingEmi: 55000,
      );
      final after = await service.findMatches(request);

      expect(
        after.matches.first.pricing.projectedEmiRatio,
        greaterThan(before.matches.first.pricing.projectedEmiRatio!),
      );
      expect(after.matches.first.category, MatchCategory.review);
    });
  });

  // --- Screens ------------------------------------------------------------

  group('screens', () {
    Future<FakeMatchService> pumpOptions(
      WidgetTester tester,
      MatchResult? result, {
      Object? error,
      Duration delay = Duration.zero,
    }) async {
      final service = FakeMatchService(result)
        ..error = error
        ..delay = delay;

      await pumpScreen(
        tester,
        const LoanOptionsScreen(),
        overrides: [matchServiceProvider.overrideWithValue(service)],
      );
      return service;
    }

    testWidgets('it shows a loading state before the result lands', (
      tester,
    ) async {
      await pumpOptions(
        tester,
        matchFor(),
        delay: const Duration(milliseconds: 800),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('United Credit Bank'), findsNothing);

      await settle(tester);
      expect(find.text('United Credit Bank'), findsOneWidget);
    });

    testWidgets('it lists the products that fit, with the category', (
      tester,
    ) async {
      await pumpOptions(tester, matchFor());
      await settle(tester);

      expect(find.text('GOOD MATCH'), findsNWidgets(2));
      expect(find.textContaining('2 of 6 products'), findsOneWidget);

      // The disclaimer closes the list, below the cards.
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await settle(tester);
      expect(find.textContaining('not an approval'), findsOneWidget);
    });

    testWidgets('a no-match result explains itself rather than going blank', (
      tester,
    ) async {
      await pumpOptions(
        tester,
        matchFor(amount: 500000, tenure: 120, purpose: 'home'),
      );
      await settle(tester);

      expect(find.textContaining('Nothing in our set fits'), findsOneWidget);
      expect(find.textContaining('6 did not fit'), findsOneWidget);
    });

    testWidgets('a network error offers a retry', (tester) async {
      final service = await pumpOptions(
        tester,
        null,
        error: NetworkException('No connection.'),
      );
      await settle(tester);

      expect(find.textContaining('No connection'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(service.calls, 2);
    });

    testWidgets('an expired session surfaces as an error, not as no matches', (
      tester,
    ) async {
      await pumpOptions(
        tester,
        null,
        error: UnauthorizedException('Please sign in again.'),
      );
      await settle(tester);

      expect(find.textContaining('sign in again'), findsOneWidget);
      expect(find.textContaining('Nothing in our set fits'), findsNothing);
    });

    testWidgets('the request sent is the one the customer made', (
      tester,
    ) async {
      final service = FakeMatchService(matchFor());

      await pumpScreen(
        tester,
        const LoanOptionsScreen(),
        overrides: [
          matchServiceProvider.overrideWithValue(service),
          loanRequestProvider.overrideWith(() => _FixedRequest()),
        ],
      );
      await settle(tester);

      expect(service.lastRequest!.amount, 750000);
      expect(service.lastRequest!.tenureMonths, 36);
      expect(service.lastRequest!.purpose, 'personal');
    });

    testWidgets('the detail screen shows every criterion, unchecked included', (
      tester,
    ) async {
      final service = FakeMatchService(matchFor());

      await pumpScreen(
        tester,
        const LoanDetailScreen(productId: 'prod_bl_b'),
        overrides: [matchServiceProvider.overrideWithValue(service)],
      );
      await settle(tester);

      expect(find.text('How this fits you'), findsOneWidget);
      expect(find.text('Purpose'), findsOneWidget);
      expect(find.text('Affordability'), findsOneWidget);
      expect(find.text('Minimum income'), findsOneWidget);
      expect(find.text('not checked'), findsNWidgets(2));

      // The disclaimer sits at the foot of the page, so scroll to it.
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await settle(tester);
      expect(find.textContaining('not an approval'), findsOneWidget);
    });

    testWidgets('a product no longer in the set fails cleanly', (tester) async {
      final service = FakeMatchService(matchFor());

      await pumpScreen(
        tester,
        const LoanDetailScreen(productId: 'prod_gone'),
        overrides: [matchServiceProvider.overrideWithValue(service)],
      );
      await settle(tester);

      expect(find.textContaining('no longer in our set'), findsOneWidget);
    });

    testWidgets('compare lays out the picked products with their fit', (
      tester,
    ) async {
      final service = FakeMatchService(matchFor());

      await pumpScreen(
        tester,
        const CompareScreen(),
        overrides: [
          matchServiceProvider.overrideWithValue(service),
          compareProvider.overrideWith(() => _FixedCompare()),
        ],
      );
      await settle(tester);

      // Column headers, plus a mention of each lender in the trade-offs.
      expect(find.text('United Credit Bank'), findsWidgets);
      expect(find.text('Arcus Capital'), findsWidgets);
      expect(find.text('GOOD MATCH'), findsNWidgets(2));

      // The catalogue fields the comparison is built from.
      for (final row in const [
        'Category',
        'FynnMatch',
        'Amount range',
        'Interest rate',
        'Monthly EMI',
        'Processing fee',
        'Fee cap',
        'Tenure range',
        'Prepayment',
        'FynnTrust',
      ]) {
        expect(find.text(row), findsOneWidget, reason: '$row is missing');
      }

      // Differences are stated as differences, with no overall winner.
      expect(find.text('The trade-offs'), findsOneWidget);
      expect(find.textContaining('does not choose for you'), findsOneWidget);
      expect(
        find.textContaining('has the lower interest rate'),
        findsOneWidget,
      );
      expect(find.textContaining('Best'), findsNothing);
      expect(find.textContaining('Winner'), findsNothing);
      expect(find.textContaining('Recommended'), findsNothing);
    });
  });
}

/// A fixed request so the screen test can assert what reached the service.
class _FixedRequest extends LoanRequestNotifier {
  @override
  LoanRequest build() =>
      const LoanRequest(amount: 750000, purpose: 'personal', tenureMonths: 36);
}

class _FixedCompare extends CompareNotifier {
  @override
  List<String> build() => const ['prod_bl_b', 'prod_bl_a'];
}
