import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/app/routes.dart';
import 'package:fynnedge/data/models/decision.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/decision_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/decisions/decision_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/decision_fixtures.dart';
import 'support/harness.dart';

/// Decision history, as the app sees it.
///
/// NO LANGUAGE MODEL OR PREDICTIVE MODEL IS INVOLVED. Every explanation is
/// assembled server-side from figures recorded at the time; the app renders
/// them and adds nothing.
class ScriptedDecisionService implements DecisionService {
  ScriptedDecisionService();

  List<Decision> decisions = const [];
  Object? failure;

  @override
  Future<List<Decision>> getDecisions() async {
    if (failure != null) throw failure!;
    return decisions;
  }

  @override
  Future<Decision> getDecision(String id) async {
    if (failure != null) throw failure!;
    return decisions.firstWhere((d) => d.id == id);
  }
}

Future<ProviderContainer> containerWith(DecisionService service) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      decisionServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

void main() {
  setUpAll(initUnitTestEnvironment);

  group('the history', () {
    test('a customer who explored nothing sees nothing', () async {
      final result = await (await containerWith(ScriptedDecisionService()))
          .read(decisionHistoryProvider.future);

      expect(result, isEmpty);
    });

    test('entries arrive as the server ordered them', () async {
      final service = ScriptedDecisionService()..decisions = decisionHistory;

      final result = await (await containerWith(service))
          .read(decisionHistoryProvider.future);

      expect(result.map((d) => d.type), [
        'simulation',
        'comparison',
        'application_started',
      ]);
    });

    test('a simulation is marked as one on the entry itself', () async {
      final service = ScriptedDecisionService()..decisions = decisionHistory;

      final result = await (await containerWith(service))
          .read(decisionHistoryProvider.future);

      /*
       * Carried on the entry, not inferred from the type by the screen. A
       * customer scanning a list must not have to open something to learn
       * whether it was real, and a screen written later must not have to
       * remember the rule.
       */
      expect(result.firstWhere((d) => d.type == 'simulation').isSimulated, isTrue);
      expect(
        result.firstWhere((d) => d.type == 'application_started').isSimulated,
        isFalse,
      );
    });

    test('an unreachable history is an error, not a blank screen', () async {
      final service = ScriptedDecisionService()..failure = NetworkException();
      final container = await containerWith(service);

      await expectLater(
        container.read(decisionHistoryProvider.future),
        throwsA(isA<NetworkException>()),
      );

      // Offline is not signed out: nothing here clears a token.
      service.failure = null;
      service.decisions = decisionHistory;
      container.invalidate(decisionHistoryProvider);

      expect(await container.read(decisionHistoryProvider.future), hasLength(3));
    });
  });

  group('an explanation', () {
    test('carries where every figure came from', () async {
      final service = ScriptedDecisionService()..decisions = decisionHistory;

      final decision = await (await containerWith(service))
          .read(decisionProvider('d3').future);

      final emi = decision.explanation.first;

      expect(emi.rule, isNotEmpty);

      // Every factor names its source, so no number is unattributed.
      for (final factor in emi.factors) {
        expect(factor.source, isNotEmpty);
        expect(factor.sourceLabel, isNotEmpty);
      }

      expect(
        emi.factors.firstWhere((f) => f.label == 'Interest rate').source,
        'catalogue_published',
      );
      expect(emi.result!.source, 'simulated');
    });

    test('says what was not assessed rather than leaving a gap', () async {
      final service = ScriptedDecisionService()..decisions = decisionHistory;

      final decision = await (await containerWith(service))
          .read(decisionProvider('d3').future);

      final affordability = decision.explanation.last;

      // A gap where approval would be is a gap a customer reads as a pass.
      expect(affordability.notAssessed, isNotEmpty);
      expect(affordability.notAssessed.first.toLowerCase(), contains('lender'));
    });

    test('a comparison names no winner', () async {
      final service = ScriptedDecisionService()..decisions = decisionHistory;

      final decision = await (await containerWith(service))
          .read(decisionProvider('d2').future);

      final whole = [
        decision.title,
        decision.description,
        ...decision.explanation.expand((e) => [e.title, e.rule]),
      ].join(' ').toLowerCase();

      for (final claim in ['the winner', 'is best', 'we recommend', 'cheapest']) {
        expect(whole, isNot(contains(claim)), reason: 'claimed: $claim');
      }
    });
  });

  group('routes', () {
    test('a decision has a route of its own', () {
      expect(Routes.decision('d3'), '/decisions/d3');
      expect(Routes.decisions, '/decisions');
    });
  });

  group('mock mode', () {
    test('records no decisions, because none were made', () async {
      /*
       * A decision record says a real customer did a real thing. Seeding
       * one would be fabricating the exploration behind it — a claim about
       * somebody's intentions, which is the specific thing this module
       * refuses to invent.
       */
      expect(await const MockDecisionService().getDecisions(), isEmpty);
    });
  });

  group('parsing', () {
    test('an unknown decision type still renders', () {
      final decision = Decision.fromJson(const {
        'id': 'd1',
        'type': 'something_new',
        'title': 'Something happened',
        'description': 'Open FynnEdge to see.',
      });

      expect(decision.type, 'something_new');
      expect(decision.isSimulated, isFalse);
    });

    test('a decision carries no internal identifiers', () {
      final decision = Decision.fromJson(const {
        'id': 'd1',
        'type': 'simulation',
        'title': 'You ran a simulation',
        'description': 'A what-if.',
        'user_id': 99,
        'idempotency_key': 'should not be here',
      });

      // The model has nowhere to put them, so the app cannot display what
      // it cannot hold.
      expect(decision.id, 'd1');
      expect(decision.type, 'simulation');
    });
  });
}
