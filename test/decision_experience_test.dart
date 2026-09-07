import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/app/session.dart';
import 'package:fynnedge/core/money/money.dart';
import 'package:fynnedge/data/engine/financial_engine.dart';
import 'package:fynnedge/data/match/fynn_match_engine.dart';
import 'package:fynnedge/data/mock/mock_data.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/match.dart';
import 'package:fynnedge/core/utils/formatters.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/match_service.dart';
import 'package:fynnedge/features/loans/compare_screen.dart';
import 'package:fynnedge/features/loans/fynn_mirror_screen.dart';
import 'package:fynnedge/features/loans/fynn_trust_screen.dart';
import 'package:fynnedge/features/loans/loan_controller.dart';
import 'package:fynnedge/features/loans/loan_detail_screen.dart';
import 'package:fynnedge/features/loans/loan_options_screen.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/profile/financial_profile_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// A service backed by the real engine and the real catalogue, so a screen
/// test asserts figures the product would actually show.
class EngineMatchService implements MatchService {
  EngineMatchService({this.income = 100000, this.existingEmi = 20000});

  final double income;
  final double existingEmi;
  int simulateCalls = 0;
  MatchRequest? lastSimulation;

  FinancialSnapshot get _financials => const FinancialEngine().snapshot(
    income: Money.of(income),
    expenses: Money.of(40000),
    existingEmi: Money.of(existingEmi),
    otherObligations: Money.zero,
    savings: Money.of(180000),
  );

  @override
  Future<MatchResult> findMatches(MatchRequest request) async =>
      const FynnMatchEngine().match(
        products: MockData.products,
        request: request,
        financials: _financials,
        customerAge: 34,
      );

  @override
  Future<ProductMatch> simulate(String productId, MatchRequest request) async {
    simulateCalls++;
    lastSimulation = request;
    return const FynnMatchEngine().evaluate(
      product: MockData.products.firstWhere((p) => p.id == productId),
      request: request,
      financials: _financials,
      customerAge: 34,
    );
  }
}

class _Picked extends CompareNotifier {
  @override
  List<String> build() => const ['prod_bl_b', 'prod_bl_a'];
}

void main() {
  setUpAll(initTestEnvironment);
  setUp(MockStore.instance.reset);

  const engine = FynnMatchEngine();
  const financial = FinancialEngine();

  FinancialSnapshot snapshotOf({double income = 100000, double emi = 20000}) =>
      financial.snapshot(
        income: Money.of(income),
        expenses: Money.of(40000),
        existingEmi: Money.of(emi),
        otherObligations: Money.zero,
        savings: Money.of(180000),
      );

  MatchResult resultFor({FinancialSnapshot? financials}) => engine.match(
    products: MockData.products,
    request: const MatchRequest(
      amount: 1000000,
      tenureMonths: 60,
      purpose: 'business',
    ),
    financials: financials ?? snapshotOf(),
    customerAge: 34,
  );

  // --- The projection -----------------------------------------------------

  group('projection', () {
    test('it is the one source of every before/after figure', () {
      final match = resultFor().byId('prod_bl_b')!;
      final p = match.projection;

      expect(p.currentOutgo.rupees, 60000);
      expect(p.projectedOutgo.rupees, 60000 + match.pricing.emi);
      expect(p.currentSurplus.rupees, 40000);
      expect(p.projectedSurplus.rupees, 40000 - match.pricing.emi);
      expect(p.currentEmiRatio.value, 20);
      expect(p.projectedEmiRatio.value, match.pricing.projectedEmiRatio);
      expect(p.emi.rupees, match.pricing.emi);
    });

    test('the ceiling and headroom follow the income', () {
      final p = resultFor().byId('prod_bl_b')!.projection;

      expect(p.ceilingPercent, 45);
      expect(p.emiCeiling.rupees, 45000);
      expect(p.headroomBefore.rupees, 25000);
      expect(
        p.headroomAfter.paise,
        Money.of(45000).paise - Money.of(20000).paise - p.emi.paise,
      );
      expect(p.withinCeiling, isTrue);
    });

    test('a loan past the ceiling is flagged, never rejected', () {
      final p = resultFor(financials: snapshotOf(income: 60000, emi: 15000))
          .byId('prod_bl_b')!
          .projection;

      expect(p.withinCeiling, isFalse);
      expect(p.headroomAfter.rupees, 0);
      // Still a viable match: FynnEdge does not underwrite.
      expect(
        resultFor(financials: snapshotOf(income: 60000, emi: 15000))
            .byId('prod_bl_b')!
            .isViable,
        isTrue,
      );
    });

    test('with no income nothing is projected or claimed', () {
      final result = resultFor(financials: snapshotOf(income: 0, emi: 0));
      final p = result.byId('prod_bl_b')!.projection;

      expect(p.isMeasurable, isFalse);
      expect(p.withinCeiling, isFalse);
      expect(p.emiCeiling.rupees, 0);
      expect(result.affordability.isMeasurable, isFalse);
    });

    test('the standing affordability picture carries no loan', () {
      final a = resultFor().affordability;

      expect(a.emi.rupees, 0);
      expect(a.currentEmiRatio.value, a.projectedEmiRatio.value);
      expect(a.headroomBefore.rupees, a.headroomAfter.rupees);
      expect(a.emiCeiling.rupees, 45000);
    });

    test('it always declares itself an estimate', () {
      final json = resultFor().byId('prod_bl_b')!.projection.toJson();

      expect(json['is_estimate'], isTrue);
      expect(json['ceiling_percent'], 45);
    });

    test('it survives a JSON round trip', () {
      final original = resultFor().byId('prod_bl_b')!.projection;
      final restored = LoanProjection.fromJson(original.toJson());

      expect(restored.emi.rupees, original.emi.rupees);
      expect(
        restored.projectedSurplus.rupees,
        original.projectedSurplus.rupees,
      );
      expect(
        restored.projectedEmiRatio.value,
        original.projectedEmiRatio.value,
      );
      expect(restored.emiCeiling.rupees, original.emiCeiling.rupees);
      expect(restored.headroomAfter.rupees, original.headroomAfter.rupees);
      expect(restored.withinCeiling, original.withinCeiling);
      expect(restored.isMeasurable, original.isMeasurable);
    });
  });

  // --- One product, described the same way on every screen -----------------

  group('state consistency', () {
    // The same loan, described by each screen in turn. All four read one
    // ProductMatch, so all four must show the same figures.
    late final expected = resultFor().byId('prod_bl_b')!;
    String emi() => Fmt.money(expected.pricing.emi);
    String surplusAfter() =>
        Fmt.money(expected.projection.projectedSurplus.rupees);

    testWidgets('Loan Options shows the match EMI', (tester) async {
      await pumpScreen(
        tester,
        const LoanOptionsScreen(),
        overrides: [
          matchServiceProvider.overrideWithValue(EngineMatchService()),
        ],
      );
      await settle(tester);

      expect(find.text(emi()), findsOneWidget);
    });

    testWidgets('Loan Detail shows the same EMI and the projection', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const LoanDetailScreen(productId: 'prod_bl_b'),
        size: const Size(420, 2400),
        overrides: [
          matchServiceProvider.overrideWithValue(EngineMatchService()),
        ],
      );
      await settle(tester);

      expect(find.textContaining(emi()), findsWidgets);
      expect(find.text(surplusAfter()), findsOneWidget);
    });

    testWidgets('FynnMirror shows the same EMI and surplus', (tester) async {
      await pumpScreen(
        tester,
        const FynnMirrorScreen(productId: 'prod_bl_b'),
        size: const Size(420, 1400),
        overrides: [
          matchServiceProvider.overrideWithValue(EngineMatchService()),
        ],
      );
      await settle(tester);

      expect(find.text(emi()), findsOneWidget);
      expect(find.text(surplusAfter()), findsOneWidget);
    });

    testWidgets('Compare shows the same EMI', (tester) async {
      await pumpScreen(
        tester,
        const CompareScreen(),
        size: const Size(420, 1400),
        overrides: [
          matchServiceProvider.overrideWithValue(EngineMatchService()),
          compareProvider.overrideWith(_Picked.new),
        ],
      );
      await settle(tester);

      expect(find.text(emi()), findsOneWidget);
    });

    testWidgets('FynnTrust shows the catalogue value, not a derived one', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const FynnTrustScreen(productId: 'prod_pl_b'),
        size: const Size(420, 2200),
        overrides: [
          matchServiceProvider.overrideWithValue(EngineMatchService()),
        ],
      );
      await settle(tester);

      final product = MockData.products.firstWhere((p) => p.id == 'prod_pl_b');
      final mean =
          product.trustBreakdown.all
              .map((f) => f.value)
              .reduce((a, b) => a + b) /
          5;

      // The published value is 78; the five factors average 76. The screen
      // must show what the catalogue published, and must not claim the two
      // are related by a formula nobody has documented.
      expect(product.fynnTrust, 78);
      expect(mean, isNot(product.fynnTrust));
      expect(find.text('78'), findsWidgets);
      expect(find.textContaining('weighted equally'), findsNothing);
      expect(
        find.textContaining('does not derive one from the other'),
        findsOneWidget,
      );
    });

    testWidgets('FynnTrust says what the product does not publish', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const FynnTrustScreen(productId: 'prod_bl_a'),
        size: const Size(420, 2400),
        overrides: [
          matchServiceProvider.overrideWithValue(EngineMatchService()),
        ],
      );
      await settle(tester);

      expect(find.text('Not published, so not scored'), findsOneWidget);
      expect(find.text('Minimum income requirement'), findsOneWidget);
      expect(find.text('Age requirement'), findsOneWidget);
      expect(find.textContaining('approve you'), findsOneWidget);
    });
  });

  // --- Simulation ----------------------------------------------------------

  group('simulation', () {
    testWidgets('it starts from the customer\'s own request', (tester) async {
      final service = EngineMatchService();
      await pumpAndRead(tester, service);

      // Nothing simulated until the customer changes something.
      expect(service.simulateCalls, 0);
      expect(find.text('Try different numbers'), findsOneWidget);
    });

    testWidgets('a change re-prices through the service', (tester) async {
      final service = EngineMatchService();
      final container = await pumpAndRead(tester, service);
      final baseline = resultFor().byId('prod_bl_b')!;

      container
          .read(simulationInputsProvider.notifier)
          .setAmount(baseline, 2000000);
      await settle(tester);

      expect(service.simulateCalls, 1);
      expect(service.lastSimulation!.amount, 2000000);

      // The term the customer did not touch is kept, so only the amount
      // moves: 20L at 12.4% over the same 60 months.
      expect(service.lastSimulation!.tenureMonths, 60);

      final expected = await service.simulate(
        'prod_bl_b',
        const MatchRequest(
          amount: 2000000,
          tenureMonths: 60,
          purpose: 'business',
        ),
      );
      expect(expected.pricing.emi, 44894.22);
      expect(
        find.textContaining(Fmt.money(expected.pricing.emi)),
        findsWidgets,
      );
    });

    testWidgets('a simulation never rewrites the stated request', (
      tester,
    ) async {
      final service = EngineMatchService();
      final container = await pumpAndRead(tester, service);
      final before = container.read(loanRequestProvider);

      container
          .read(simulationInputsProvider.notifier)
          .setAmount(resultFor().byId('prod_bl_b')!, 2500000);
      await settle(tester);

      final after = container.read(loanRequestProvider);
      expect(after.amount, before.amount);
      expect(after.tenureMonths, before.tenureMonths);
    });

    testWidgets('a simulation never touches saved customer data', (
      tester,
    ) async {
      final store = MockStore.instance;
      final before = store.financials.toJson();
      final container = await pumpAndRead(tester, EngineMatchService());

      container
          .read(simulationInputsProvider.notifier)
          .setTenure(resultFor().byId('prod_bl_b')!, 84);
      await settle(tester);

      expect(store.financials.toJson(), before);
    });

    testWidgets('resetting returns to the customer\'s request', (tester) async {
      final service = EngineMatchService();
      final container = await pumpAndRead(tester, service);
      final baseline = resultFor().byId('prod_bl_b')!;

      container
          .read(simulationInputsProvider.notifier)
          .setAmount(baseline, 2000000);
      await settle(tester);
      expect(find.text('Back to my request'), findsOneWidget);

      container.read(simulationInputsProvider.notifier).reset();
      await settle(tester);

      expect(find.text('Back to my request'), findsNothing);
      expect(
        find.textContaining(
          Fmt.money(resultFor().byId('prod_bl_b')!.pricing.emi),
        ),
        findsWidgets,
      );
    });

    test('inputs only apply to the product they were made on', () {
      const inputs = SimulationInputs(
        productId: 'prod_bl_b',
        amount: 2000000,
        tenureMonths: 60,
        isCustomised: true,
      );

      expect(inputs.appliesTo('prod_bl_b'), isTrue);
      expect(inputs.appliesTo('prod_bl_a'), isFalse);
      expect(const SimulationInputs().appliesTo('prod_bl_b'), isFalse);
    });
  });

  // --- Estimates are labelled ----------------------------------------------

  group('estimate vs confirmed', () {
    testWidgets('every projected figure is marked as an estimate', (
      tester,
    ) async {
      await pumpAndRead(tester, EngineMatchService());

      expect(find.text('ESTIMATE'), findsWidgets);
      expect(
        find.textContaining('Nothing is saved or sent anywhere'),
        findsOneWidget,
      );
    });

    testWidgets('FynnMirror says it is not an offer or a decision', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const FynnMirrorScreen(productId: 'prod_bl_b'),
        size: const Size(420, 1300),
        overrides: [
          matchServiceProvider.overrideWithValue(EngineMatchService()),
        ],
      );
      await settle(tester);

      expect(find.text('ESTIMATE'), findsOneWidget);
      expect(
        find.textContaining('Not an offer, and not a lender decision'),
        findsOneWidget,
      );
    });

    testWidgets('no screen invents a lender rule about the EMI share', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const FynnMirrorScreen(productId: 'prod_bl_b'),
        size: const Size(420, 1300),
        overrides: [
          matchServiceProvider.overrideWithValue(EngineMatchService()),
        ],
      );
      await settle(tester);

      for (final claim in const [
        'Lenders start getting cautious',
        'you are eligible',
        'You are eligible',
        'guaranteed',
        'pre-approved',
      ]) {
        expect(find.textContaining(claim), findsNothing);
      }
      expect(find.textContaining('affordability reference'), findsOneWidget);
    });
  });

  // --- State invalidation --------------------------------------------------

  group('state invalidation', () {
    test('saving the financial profile re-runs FynnMatch', () async {
      // Mock mode runs the real engine over MockStore, so a saved profile has
      // to move the matches exactly as it would against the API.
      final container = await appContainer();

      final before = await container.read(fynnMatchProvider.future);
      final beforeRatio =
          before.matches.first.projection.projectedEmiRatio.value;

      final controller = container.read(
        financialProfileControllerProvider.notifier,
      );
      await controller.load();

      final loaded = container.read(financialProfileControllerProvider);
      expect(loaded.loadError, isNull);
      expect(loaded.current, isNotNull);

      controller.edit(loaded.current!.copyWith(existingEmi: 45000));
      expect(await controller.save(), isTrue);

      final after = await container.read(fynnMatchProvider.future);

      expect(
        after.matches.first.projection.projectedEmiRatio.value,
        greaterThan(beforeRatio),
      );
      expect(
        after.affordability.headroomBefore.rupees,
        lessThan(before.affordability.headroomBefore.rupees),
      );
    });

    test('a simulation does not invalidate anything', () async {
      final container = await appContainer();

      final before = await container.read(fynnMatchProvider.future);
      final baseline = before.byId('prod_bl_b')!;

      container
          .read(simulationInputsProvider.notifier)
          .setAmount(baseline, 2500000);

      // The match list is untouched: only the one product being modelled
      // moves, and only on the screen doing the modelling.
      final after = await container.read(fynnMatchProvider.future);
      expect(after.byId('prod_bl_b')!.pricing.emi, baseline.pricing.emi);

      final simulated = await container.read(
        simulatedMatchProvider('prod_bl_b').future,
      );
      expect(simulated.pricing.amount, 2500000);
    });
  });

  // --- Errors and incomplete data ------------------------------------------

  group('error and incomplete states', () {
    testWidgets('an incomplete profile is explained, not left blank', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const LoanDetailScreen(productId: 'prod_bl_b'),
        overrides: [
          matchServiceProvider.overrideWithValue(
            EngineMatchService(income: 0, existingEmi: 0),
          ),
        ],
      );
      await settle(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await settle(tester);

      expect(find.textContaining('Add your monthly income'), findsWidgets);
    });

    testWidgets('a failure shows one readable sentence, not an exception', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const LoanDetailScreen(productId: 'prod_bl_b'),
        overrides: [matchServiceProvider.overrideWithValue(_FailingService())],
      );
      await settle(tester);

      expect(find.textContaining('Could not reach FynnEdge'), findsOneWidget);
      expect(find.textContaining('ApiException'), findsNothing);
    });
  });
}

/// A provider container wired the way the app wires one, for tests that drive
/// providers without mounting a screen.
Future<ProviderContainer> appContainer() async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [localStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);

  return container;
}

/// Mounts Loan Detail and hands back a container for driving providers.
Future<ProviderContainer> pumpAndRead(
  WidgetTester tester,
  MatchService service,
) async {
  // Tall enough that the simulator and the before/after panel are both built,
  // so a finder is testing the screen rather than the scroll position.
  await pumpScreen(
    tester,
    const LoanDetailScreen(productId: 'prod_bl_b'),
    size: const Size(420, 2400),
    overrides: [matchServiceProvider.overrideWithValue(service)],
  );
  await settle(tester);

  return ProviderScope.containerOf(
    tester.element(find.byType(LoanDetailScreen)),
  );
}

class _FailingService implements MatchService {
  @override
  Future<MatchResult> findMatches(MatchRequest request) async =>
      throw NetworkException();

  @override
  Future<ProductMatch> simulate(String productId, MatchRequest request) async =>
      throw NetworkException();
}
