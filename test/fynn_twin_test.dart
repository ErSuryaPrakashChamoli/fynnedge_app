import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/engine/financial_engine.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/twin.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/data/services/twin_service.dart';
import 'package:fynnedge/features/twin/twin_controller.dart';
import 'package:fynnedge/features/twin/twin_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// A Twin service that can be made to fail.
class FlakyTwinService implements TwinService {
  FlakyTwinService([MockTwinService? inner])
    : _inner = inner ?? MockTwinService();

  final MockTwinService _inner;
  Object? failCapabilities;
  Object? failSimulate;
  int simulations = 0;

  @override
  Future<TwinCapabilities> capabilities() async {
    if (failCapabilities != null) throw failCapabilities!;
    return _inner.capabilities();
  }

  @override
  Future<TwinProjection> simulate(TwinScenario scenario) async {
    simulations++;
    if (failSimulate != null) throw failSimulate!;
    return _inner.simulate(scenario);
  }
}

Future<ProviderContainer> containerWith(TwinService service) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      twinServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

void main() {
  setUpAll(initTestEnvironment);
  setUp(MockStore.instance.reset);

  const loan = TwinScenario(
    type: ScenarioType.loan,
    amount: 1000000,
    tenureMonths: 60,
    productId: 'prod_bl_b',
  );

  // --- The simulation ------------------------------------------------------

  group('simulating', () {
    test('it starts from the stored customer, through the engine', () async {
      final snapshot = MockStore.instance.snapshot;
      final projection = await MockTwinService().simulate(loan);

      expect(projection.current.monthlyIncome, snapshot.income.rupees);
      expect(projection.current.monthlyOutgo, snapshot.totalOutgo.rupees);
      expect(projection.current.surplus, snapshot.surplus.rupees);
      expect(projection.current.emiRatio, snapshot.emiRatio.value);
      expect(
        projection.current.emergencyMonths,
        snapshot.emergencyMonths.value,
      );
    });

    test('a loan is priced by the catalogue product', () async {
      final projection = await MockTwinService().simulate(loan);

      expect(projection.loan!.productId, 'prod_bl_b');
      expect(projection.loan!.lender, 'United Credit Bank');
      expect(projection.loan!.interestRate, 12.4);
      expect(projection.loan!.emi, 22447.11);
    });

    test('the EMI lands on outgo, and nothing else moves', () async {
      final snapshot = MockStore.instance.snapshot;
      final projection = await MockTwinService().simulate(loan);

      expect(
        projection.projected.monthlyOutgo,
        snapshot.totalOutgo.rupees + projection.loan!.emi,
      );
      // A loan does not change income, spending or savings.
      expect(
        projection.projected.monthlyIncome,
        projection.current.monthlyIncome,
      );
      expect(
        projection.projected.monthlyExpenses,
        projection.current.monthlyExpenses,
      );
      expect(projection.projected.savings, projection.current.savings);
      expect(projection.difference.monthlyOutgo, projection.loan!.emi);
    });

    test('an unknown product is refused rather than guessed at', () async {
      await expectLater(
        MockTwinService().simulate(
          const TwinScenario(
            type: ScenarioType.loan,
            amount: 100000,
            tenureMonths: 12,
            productId: 'prod_imaginary',
          ),
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('spending more moves outgo but not the EMI ratio', () async {
      final projection = await MockTwinService().simulate(
        const TwinScenario(
          type: ScenarioType.expenseChange,
          monthlyChange: 8000,
        ),
      );

      expect(
        projection.projected.monthlyExpenses,
        projection.current.monthlyExpenses + 8000,
      );
      expect(projection.difference.surplus, -8000);
      expect(projection.projected.emiRatio, projection.current.emiRatio);
    });

    test('setting money aside grows savings, not outgo', () async {
      final projection = await MockTwinService().simulate(
        const TwinScenario(
          type: ScenarioType.savingChange,
          monthlyAmount: 10000,
          months: 12,
        ),
      );

      expect(projection.difference.savings, 120000);
      expect(projection.difference.monthlyOutgo, 0);
      expect(
        projection.observations.map((o) => o.key),
        contains('saving_assumption'),
      );
    });

    test('the affordability reference is the existing one', () async {
      final projection = await MockTwinService().simulate(loan);

      expect(
        projection.referencePercent,
        FinancialEngine.affordabilityCeilingPercent,
      );
      expect(projection.projectedEmiRatio, projection.projected.emiRatio);
    });

    test('a negative surplus is preserved and flagged', () async {
      MockStore.instance.financials = MockStore.instance.financials.copyWith(
        monthlyIncome: 50000,
        monthlyExpenses: 30000,
        existingEmi: 20000,
      );

      final projection = await MockTwinService().simulate(loan);

      expect(projection.projected.surplus, lessThan(0));
      expect(
        projection.observations.map((o) => o.key),
        contains('negative_surplus'),
      );
      expect(projection.observations.first.isSerious, isTrue);
    });

    test('with no income nothing is projected', () async {
      MockStore.instance.financials = MockStore.instance.financials.copyWith(
        monthlyIncome: 0,
        monthlyExpenses: 0,
        existingEmi: 0,
      );

      final projection = await MockTwinService().simulate(loan);

      expect(projection.isMeasurable, isFalse);
      expect(projection.projectedEmiRatio, isNull);
      expect(projection.currentScore, isNull);
      expect(projection.observations.single.key, 'no_income');
      expect(await MockTwinService().capabilities(), isA<TwinCapabilities>());
    });

    test('the projected score is the score engine, marked simulated', () async {
      final projection = await MockTwinService().simulate(loan);
      final json = projection.toJson();

      expect(projection.currentScore, isNotNull);
      expect((json['fynn_score'] as Map)['is_simulated'], isTrue);
    });

    test('nothing invented is reported', () async {
      final projection = await MockTwinService().simulate(loan);
      final json = projection.toJson().toString();

      for (final invented in const [
        'impact_score',
        'risk_score',
        'probability',
        'approval',
        'guaranteed',
      ]) {
        expect(json, isNot(contains(invented)));
      }
      expect(projection.isProjection, isTrue);
      expect(projection.disclaimer, contains('not a prediction'));
    });

    test('a simulation changes nothing about the customer', () async {
      final before = MockStore.instance.financials.toJson();
      final goalsBefore = MockStore.instance.goals.length;

      await MockTwinService().simulate(loan);
      await MockTwinService().simulate(
        const TwinScenario(
          type: ScenarioType.expenseChange,
          monthlyChange: 9000,
        ),
      );

      expect(MockStore.instance.financials.toJson(), before);
      expect(MockStore.instance.goals, hasLength(goalsBefore));
      // And no application was created by asking what one would cost.
      expect(MockStore.instance.applications, isEmpty);
    });

    test('the same scenario gives the same projection', () async {
      expect(
        (await MockTwinService().simulate(loan)).toJson().toString(),
        (await MockTwinService().simulate(loan)).toJson().toString(),
      );
    });

    test('a projection survives a JSON round trip', () async {
      final original = await MockTwinService().simulate(loan);
      final restored = TwinProjection.fromJson(original.toJson());

      expect(restored.toJson(), original.toJson());
      expect(restored.projected.surplus, original.projected.surplus);
      expect(restored.loan!.emi, original.loan!.emi);
      expect(
        restored.observations.map((o) => o.key),
        original.observations.map((o) => o.key),
      );
    });
  });

  // --- The controller ------------------------------------------------------

  group('controller', () {
    test('running produces a projection', () async {
      final container = await containerWith(MockTwinService());
      final controller = container.read(twinControllerProvider.notifier);

      controller.setProduct('prod_bl_b');
      expect(await controller.run(), isNotNull);

      final state = container.read(twinControllerProvider);
      expect(state.projection, isNotNull);
      expect(state.running, isFalse);
      expect(state.error, isNull);
    });

    test('a loan needs a product before it can run', () async {
      final container = await containerWith(MockTwinService());
      final controller = container.read(twinControllerProvider.notifier);

      expect(container.read(twinControllerProvider).canRun, isFalse);
      expect(await controller.run(), isNull);

      controller.setProduct('prod_bl_b');
      expect(container.read(twinControllerProvider).canRun, isTrue);
    });

    test('changing an assumption clears the last result', () async {
      final container = await containerWith(MockTwinService());
      final controller = container.read(twinControllerProvider.notifier);

      controller.setProduct('prod_bl_b');
      await controller.run();
      expect(container.read(twinControllerProvider).projection, isNotNull);

      // A projection belongs to the assumptions it came from.
      controller.setAmount(2000000);
      expect(container.read(twinControllerProvider).projection, isNull);
    });

    test('a failure is reported and retryable', () async {
      final service = FlakyTwinService()..failSimulate = NetworkException();
      final container = await containerWith(service);
      final controller = container.read(twinControllerProvider.notifier);

      controller.setProduct('prod_bl_b');
      expect(await controller.run(), isNull);
      expect(
        container.read(twinControllerProvider).error,
        contains('Could not reach FynnEdge'),
      );

      service.failSimulate = null;
      expect(await controller.run(), isNotNull);
      expect(container.read(twinControllerProvider).error, isNull);
    });

    test('an expired session is not a generic failure', () async {
      final service = FlakyTwinService()
        ..failSimulate = UnauthorizedException();
      final container = await containerWith(service);
      final controller = container.read(twinControllerProvider.notifier);

      controller.setProduct('prod_bl_b');
      await controller.run();

      expect(
        container.read(twinControllerProvider).error,
        contains('sign in again'),
      );
    });

    test('the scenario carries only assumptions', () {
      const state = TwinScreenState(
        type: ScenarioType.loan,
        amount: 500000,
        tenureMonths: 36,
        productId: 'prod_pl_a',
      );
      final json = state.scenario.toJson();

      // Nothing about where the customer stands, and no pricing: both are
      // the server's.
      expect(json.keys, ['type', 'amount', 'tenure_months', 'product_id']);
      for (final forbidden in const [
        'emi',
        'surplus',
        'monthly_income',
        'emi_ratio',
        'score',
        'user_id',
      ]) {
        expect(json.containsKey(forbidden), isFalse);
      }
    });
  });

  // --- The screen ----------------------------------------------------------

  group('screen', () {
    testWidgets('it offers the three scenarios', (tester) async {
      await pumpScreen(tester, const TwinScreen(), size: const Size(420, 1800));
      await settle(tester);

      for (final type in ScenarioType.values) {
        expect(find.text(type.label), findsOneWidget);
      }
      expect(find.text('Run the simulation'), findsOneWidget);
    });

    testWidgets('running shows today beside the scenario', (tester) async {
      await pumpScreen(tester, const TwinScreen(), size: const Size(420, 2600));
      await settle(tester);

      await tester.tap(find.textContaining('United Credit Bank').first);
      await settle(tester);
      await tester.tap(find.text('Run the simulation'));
      await settle(tester);

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('SCENARIO'), findsOneWidget);
      expect(find.text('Monthly outgo'), findsOneWidget);
      expect(find.text('Left over'), findsOneWidget);
      expect(find.text('EMI share'), findsOneWidget);
      // Said in the section header and again in the disclaimer.
      expect(find.textContaining('not a prediction'), findsNWidgets(2));
    });

    testWidgets('an empty profile is told, not projected', (tester) async {
      MockStore.instance.financials = MockStore.instance.financials.copyWith(
        monthlyIncome: 0,
        monthlyExpenses: 0,
        existingEmi: 0,
      );

      await pumpScreen(tester, const TwinScreen(), size: const Size(420, 1200));
      await settle(tester);

      expect(find.text('Add your figures first'), findsOneWidget);
      expect(find.text('Financial profile'), findsOneWidget);
      // No simulation is offered against figures that do not exist.
      expect(find.text('Run the simulation'), findsNothing);
    });

    testWidgets('a load failure offers a retry', (tester) async {
      final service = FlakyTwinService()..failCapabilities = NetworkException();

      await pumpScreen(
        tester,
        const TwinScreen(),
        overrides: [twinServiceProvider.overrideWithValue(service)],
      );
      await settle(tester);

      expect(find.textContaining('Could not reach FynnEdge'), findsOneWidget);

      service.failCapabilities = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);

      expect(find.text('What would you like to try?'), findsOneWidget);
    });

    testWidgets('golden: the scenario builder', (tester) async {
      await pumpScreen(tester, const TwinScreen());
      await settle(tester);

      await golden(tester, TwinScreen, '30_fynn_twin');
    });

    testWidgets('golden: a loan result', (tester) async {
      await pumpScreen(tester, const TwinScreen(), size: const Size(420, 2600));
      await settle(tester);

      await tester.tap(find.textContaining('United Credit Bank').first);
      await settle(tester);
      await tester.tap(find.text('Run the simulation'));
      await settle(tester);

      await golden(tester, TwinScreen, '30a_fynn_twin_result');
    });
  });
}
