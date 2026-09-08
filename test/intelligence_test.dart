import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/home/primary_action_rules.dart';
import 'package:fynnedge/data/models/intelligence.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/intelligence_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/intelligence/intelligence_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';
import 'support/intelligence_fixtures.dart';

/// The intelligence layer, as the app sees it.
///
/// NO LANGUAGE MODEL, PREDICTIVE MODEL OR ANALYTICS PLATFORM IS INVOLVED
/// anywhere in this. Everything under test is what the app does with what
/// the API returns — including when what it returns is "we do not know".
class ScriptedIntelligenceService implements IntelligenceService {
  ScriptedIntelligenceService();

  FinancialIntelligence intelligence = const FinancialIntelligence();
  List<FinancialMoment> timeline = const [];
  Object? failure;

  @override
  Future<FinancialIntelligence> getIntelligence() async {
    if (failure != null) throw failure!;
    return intelligence;
  }

  @override
  Future<List<FinancialMoment>> getTimeline() async {
    if (failure != null) throw failure!;
    return timeline;
  }
}

Future<ProviderContainer> containerWith(IntelligenceService service) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      intelligenceServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

void main() {
  setUpAll(initUnitTestEnvironment);

  group('what the app is told about history', () {
    test('a customer with no observations is told there is no history', () async {
      final service = ScriptedIntelligenceService()
        ..intelligence = const FinancialIntelligence(
          observations: 0,
          hasComparableHistory: false,
        );

      final result = await (await containerWith(service))
          .read(intelligenceProvider.future);

      /*
       * The state every customer was in when Module 31 shipped. The flag
       * is carried explicitly rather than inferred from an empty list,
       * because "nothing changed" and "we have not looked before" are
       * different things and only one of them can be shown as a trend.
       */
      expect(result.observations, 0);
      expect(result.hasComparableHistory, isFalse);
    });

    test('one observation is still not a history', () async {
      final service = ScriptedIntelligenceService()
        ..intelligence = const FinancialIntelligence(
          observations: 1,
          hasComparableHistory: false,
        );

      final result = await (await containerWith(service))
          .read(intelligenceProvider.future);

      expect(result.hasComparableHistory, isFalse);
    });
  });

  group('the plan', () {
    test('its first item is the next action', () async {
      final service = ScriptedIntelligenceService()
        ..intelligence = plannedIntelligence;

      final result = await (await containerWith(service))
          .read(intelligenceProvider.future);

      /*
       * One ladder on the server produces both, so a client showing the
       * card and the list must show the same first step. A screen where
       * they differ is a product suggesting two different things at once.
       */
      expect(result.plan, isNotEmpty);
      expect(result.plan.first.type, result.nextAction!.type);
      expect(result.plan.first.reason, result.nextAction!.reason);
    });

    test('it is never longer than three', () async {
      final service = ScriptedIntelligenceService()
        ..intelligence = plannedIntelligence;

      final result = await (await containerWith(service))
          .read(intelligenceProvider.future);

      // A plan of nine is a backlog, and the customer does none of it.
      expect(result.plan.length, lessThanOrEqualTo(3));
    });

    test('every item carries a reason and somewhere to go', () async {
      final service = ScriptedIntelligenceService()
        ..intelligence = plannedIntelligence;

      final result = await (await containerWith(service))
          .read(intelligenceProvider.future);

      for (final action in result.plan) {
        expect(action.reason, isNotEmpty);
        expect(action.actionRoute, startsWith('/'));
        expect(action.title, isNotEmpty);
      }
    });

    test('an empty plan is a valid answer', () async {
      // A customer with nothing pending is told so, not handed a task.
      final result = await (await containerWith(ScriptedIntelligenceService()))
          .read(intelligenceProvider.future);

      expect(result.plan, isEmpty);
      expect(result.nextAction, isNull);
    });

    test('it points at nothing that sells', () async {
      final service = ScriptedIntelligenceService()
        ..intelligence = plannedIntelligence;

      final result = await (await containerWith(service))
          .read(intelligenceProvider.future);

      final whole = result.plan
          .expand((a) => [a.title, a.reason])
          .join(' ')
          .toLowerCase();

      for (final claim in [
        'you should', 'you must', 'apply now', 'best rate', 'guaranteed',
        'approved', 'act fast', 'limited',
      ]) {
        expect(whole, isNot(contains(claim)), reason: 'pressured: $claim');
      }
    });
  });

  group('the next action', () {
    test('is a single answer with a reason', () async {
      final service = ScriptedIntelligenceService()
        ..intelligence = blockedIntelligence;

      final result = await (await containerWith(service))
          .read(intelligenceProvider.future);

      expect(result.nextAction, isNotNull);
      expect(result.nextAction!.type, 'resolve_submission_status');
      expect(result.nextAction!.reason, isNotEmpty);
    });

    test('a missing next action is null rather than a guess', () async {
      final result = await (await containerWith(ScriptedIntelligenceService()))
          .read(intelligenceProvider.future);

      expect(result.nextAction, isNull);
    });
  });

  group('the home rules mirror the server', () {
    test('a blocked submission outranks everything else', () {
      const rules = PrimaryActionRules();

      /*
       * The contradiction this rung exists to prevent. Home used to answer
       * "set your first goal" to a customer who had been told not to
       * resubmit an application FynnEdge could not confirm.
       */
      final action = rules.resolve(
        hasIncome: true,
        hasName: true,
        goalCount: 0,
        applicationCount: 1,
        blockedBySubmission: true,
      );

      expect(action.key, 'resolve_submission_status');
    });

    test('it outranks even an incomplete profile', () {
      const rules = PrimaryActionRules();

      final action = rules.resolve(
        hasIncome: false,
        hasName: false,
        goalCount: 0,
        applicationCount: 1,
        blockedBySubmission: true,
      );

      expect(action.key, 'resolve_submission_status');
    });

    test('without it, the ordinary ladder is unchanged', () {
      const rules = PrimaryActionRules();

      expect(
        rules
            .resolve(hasIncome: false, hasName: false, goalCount: 0, applicationCount: 0)
            .key,
        'complete_profile',
      );
      expect(
        rules
            .resolve(hasIncome: true, hasName: false, goalCount: 0, applicationCount: 0)
            .key,
        'add_your_name',
      );
      expect(
        rules
            .resolve(hasIncome: true, hasName: true, goalCount: 0, applicationCount: 0)
            .key,
        'set_goal',
      );
    });
  });

  group('failures', () {
    test('an unreachable intelligence layer is an error, not a blank screen', () async {
      final service = ScriptedIntelligenceService()..failure = NetworkException();
      final container = await containerWith(service);

      await expectLater(
        container.read(intelligenceProvider.future),
        throwsA(isA<NetworkException>()),
      );
    });

    test('a timeline that cannot load does not lose the session', () async {
      final service = ScriptedIntelligenceService()..failure = NetworkException();
      final container = await containerWith(service);

      await expectLater(
        container.read(financialTimelineProvider.future),
        throwsA(isA<NetworkException>()),
      );

      // Offline is not signed out: nothing here clears a token.
      service.failure = null;
      service.timeline = [scoreMoment];

      container.invalidate(financialTimelineProvider);
      expect(await container.read(financialTimelineProvider.future), hasLength(1));
    });
  });

  group('mock mode', () {
    test('has no financial history, because nothing has happened', () async {
      const service = MockIntelligenceService();

      final intelligence = await service.getIntelligence();

      /*
       * A moment is a record of something that occurred to a real
       * customer. Seeding a timeline would be inventing the events behind
       * it, and a fabricated "your FynnScore improved by 6" is exactly what
       * Module 31 refuses — whether it comes from a rule or a fixture.
       */
      expect(intelligence.recentMoments, isEmpty);
      expect(intelligence.observations, 0);
      expect(intelligence.hasComparableHistory, isFalse);
      expect(await service.getTimeline(), isEmpty);
    });

    test('still suggests a next step, because that is current state', () async {
      final intelligence = await const MockIntelligenceService().getIntelligence();

      expect(intelligence.nextAction, isNotNull);
    });
  });

  group('parsing', () {
    test('an unknown moment type still renders', () {
      // A newer server must not blank an older app's timeline.
      final moment = FinancialMoment.fromJson(const {
        'id': '1',
        'type': 'something_new',
        'importance': 'ordinary',
        'title': 'Something happened',
        'description': 'Open FynnEdge to see.',
      });

      expect(moment.type, 'something_new');
      expect(moment.isMajor, isFalse);
    });

    test('a moment carries no internal reasoning', () {
      final moment = FinancialMoment.fromJson(const {
        'id': '1',
        'type': 'score_improved',
        'importance': 'ordinary',
        'title': 'Your FynnScore improved',
        'description': 'It went from 64 to 71.',
        'rule': 'should not be here',
        'evidence': 'should not be here',
      });

      // The model has nowhere to put them, which is the point: the app
      // cannot display what it cannot hold.
      expect(moment.title, 'Your FynnScore improved');
      expect(moment.description, contains('64'));
    });
  });
}
