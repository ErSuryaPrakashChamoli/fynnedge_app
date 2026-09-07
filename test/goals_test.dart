import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/core/utils/clock.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/goal.dart';
import 'package:fynnedge/data/models/intent.dart';
import 'package:fynnedge/data/models/score.dart';
import 'package:fynnedge/data/models/user.dart';
import 'package:fynnedge/data/repositories/profile_repository.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/data/services/profile_service.dart';
import 'package:fynnedge/features/home/home_controller.dart';
import 'package:fynnedge/features/profile/goals_controller.dart';
import 'package:fynnedge/features/profile/profile_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// A goal service whose behaviour each test dictates.
class FakeGoalService implements ProfileService {
  FakeGoalService({List<Goal>? initial}) : _goals = [...?initial];

  List<Goal> _goals;
  var _nextId = 100;

  Future<List<Goal>> Function()? onList;
  Future<Goal> Function(Goal)? onCreate;
  Future<Goal> Function(Goal)? onUpdate;
  Future<void> Function(String)? onDelete;

  int listCalls = 0;
  int createCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  Goal? lastSent;

  @override
  Future<List<Goal>> getGoals() async {
    listCalls++;
    if (onList != null) return onList!();
    return _goals.map((g) => g.withLocalDerived()).toList();
  }

  @override
  Future<Goal> createGoal(Goal goal) async {
    createCalls++;
    lastSent = goal;
    if (onCreate != null) return onCreate!(goal);
    final created = Goal(
      id: 'goal_${_nextId++}',
      title: goal.title,
      category: goal.category,
      targetAmount: goal.targetAmount,
      targetDate: goal.targetDate,
      savedAmount: goal.savedAmount,
      note: goal.note,
    );
    _goals = [..._goals, created];
    return created.withLocalDerived();
  }

  @override
  Future<Goal> updateGoal(Goal goal) async {
    updateCalls++;
    lastSent = goal;
    if (onUpdate != null) return onUpdate!(goal);
    _goals = _goals.map((g) => g.id == goal.id ? goal : g).toList();
    return goal.withLocalDerived();
  }

  @override
  Future<void> deleteGoal(String id) async {
    deleteCalls++;
    if (onDelete != null) return onDelete!(id);
    _goals = _goals.where((g) => g.id != id).toList();
  }

  // Unused here.
  @override
  Future<UserProfile> getProfile() async =>
      const UserProfile(id: '1', mobile: '9876543210');
  @override
  Future<UserProfile> updateProfile(UserProfile p) async => p;
  @override
  Future<FinancialProfile> getFinancialProfile() async =>
      const FinancialProfile();
  @override
  Future<FinancialProfile> updateFinancialProfile(FinancialProfile p) async =>
      p;
  @override
  Future<FynnScore> getFynnScore() async => const FynnScore(hasScore: false);
}

Goal sampleGoal({
  String id = 'goal_1',
  String title = 'Business Expansion',
  double target = 1500000,
  double saved = 320000,
  int inDays = 540,
}) => Goal(
  id: id,
  title: title,
  category: GoalCategory.business,
  targetAmount: target,
  targetDate: AppClock.now().add(Duration(days: inDays)),
  savedAmount: saved,
);

Future<ProviderContainer> containerWith(FakeGoalService service) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();
  final container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      profileServiceProvider.overrideWithValue(service),
      profileRepositoryProvider.overrideWith(
        (ref) => ProfileRepository(service, store),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(goalsControllerProvider, (_, _) {});
  return container;
}

Future<void> settleGoals(ProviderContainer c) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (!c.read(goalsControllerProvider).loading) return;
  }
  fail('Goals never finished loading');
}

void main() {
  setUpAll(initUnitTestEnvironment);

  group('Loading', () {
    test('starts loading with nothing to show', () async {
      final container = await containerWith(
        FakeGoalService(initial: [sampleGoal()]),
      );

      expect(container.read(goalsControllerProvider).loading, isTrue);
      expect(container.read(goalsControllerProvider).goals, isEmpty);
    });

    test('resolves to the customer\'s real goals', () async {
      final service = FakeGoalService(
        initial: [
          sampleGoal(),
          sampleGoal(id: 'goal_2', title: 'Home'),
        ],
      );
      final container = await containerWith(service);
      await settleGoals(container);

      final state = container.read(goalsControllerProvider);
      expect(state.goals, hasLength(2));
      expect(state.goals.first.title, 'Business Expansion');
      expect(service.listCalls, 1);
    });

    test('no goals reports as empty, not as an error', () async {
      final container = await containerWith(FakeGoalService());
      await settleGoals(container);

      final state = container.read(goalsControllerProvider);
      expect(state.isEmpty, isTrue);
      expect(state.loadError, isNull);
    });

    test('a failed load is reported and retryable', () async {
      final service = FakeGoalService(initial: [sampleGoal()]);
      var attempts = 0;
      service.onList = () async {
        attempts++;
        if (attempts == 1) throw NetworkException();
        return [sampleGoal().withLocalDerived()];
      };

      final container = await containerWith(service);
      await settleGoals(container);
      expect(container.read(goalsControllerProvider).loadError, isNotNull);

      await container.read(goalsControllerProvider.notifier).load();
      final state = container.read(goalsControllerProvider);
      expect(state.loadError, isNull);
      expect(state.goals, hasLength(1));
    });
  });

  group('Derived values', () {
    test('the server\'s figures are used, not recomputed', () async {
      final service = FakeGoalService();
      service.onList = () async => [
        Goal(
          id: 'g1',
          title: 'Odd',
          category: GoalCategory.other,
          targetAmount: 100000,
          targetDate: AppClock.now().add(const Duration(days: 365)),
          savedAmount: 50000,
          derived: const GoalDerived(
            progress: 0.99,
            monthsRemaining: 3,
            monthlyRequired: 12345,
          ),
        ),
      ];

      final container = await containerWith(service);
      await settleGoals(container);

      final goal = container.read(goalsControllerProvider).goals.single;
      expect(goal.isServerDerived, isTrue);
      expect(goal.progress, 0.99);
      expect(goal.monthsRemaining, 3);
      expect(goal.monthlyRequired, 12345);
    });

    test('a local edit drops the server figures and derives locally', () {
      final fromServer = Goal.fromJson({
        'id': 'g1',
        'title': 'Home',
        'category': 'home',
        'target_amount': 1000000,
        'saved_amount': 250000,
        'target_date': AppClock.now()
            .add(const Duration(days: 365))
            .toIso8601String(),
        'derived': {
          'progress': 0.25,
          'months_remaining': 12,
          'monthly_required': 62500,
        },
      });
      expect(fromServer.isServerDerived, isTrue);

      final edited = fromServer.copyWith(targetAmount: 2000000);
      expect(edited.isServerDerived, isFalse);
      // Recomputed for the new target, not the stale server figure.
      expect(edited.progress, 0.125);
    });
  });

  group('Create', () {
    test('a created goal appears in the list', () async {
      final service = FakeGoalService();
      final container = await containerWith(service);
      await settleGoals(container);

      final result = await container
          .read(goalsControllerProvider.notifier)
          .create(sampleGoal(id: '', title: 'New Vehicle'));

      expect(result, GoalActionResult.success);
      final state = container.read(goalsControllerProvider);
      expect(state.goals, hasLength(1));
      expect(state.goals.single.title, 'New Vehicle');
      expect(state.goals.single.id, isNotEmpty);
      expect(state.changedAt, isNotNull);
    });

    test('every field reaches the service', () async {
      final service = FakeGoalService();
      final container = await containerWith(service);
      await settleGoals(container);

      final date = AppClock.now().add(const Duration(days: 800));
      await container
          .read(goalsControllerProvider.notifier)
          .create(
            Goal(
              id: '',
              title: 'Education Fund',
              category: GoalCategory.education,
              targetAmount: 2500000,
              targetDate: date,
              savedAmount: 125000,
              note: 'Postgraduate',
            ),
          );

      final sent = service.lastSent!;
      expect(sent.title, 'Education Fund');
      expect(sent.category, GoalCategory.education);
      expect(sent.targetAmount, 2500000);
      expect(sent.savedAmount, 125000);
      expect(sent.note, 'Postgraduate');
      expect(sent.targetDate.day, date.day);
    });

    test('a second submit while busy is ignored', () async {
      final service = FakeGoalService();
      service.onCreate = (g) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return g.withLocalDerived();
      };
      final container = await containerWith(service);
      await settleGoals(container);

      final controller = container.read(goalsControllerProvider.notifier);
      final results = await Future.wait([
        controller.create(sampleGoal(id: '')),
        controller.create(sampleGoal(id: '')),
      ]);

      expect(service.createCalls, 1, reason: 'duplicate submission');
      expect(results, contains(GoalActionResult.success));
      expect(results, contains(GoalActionResult.failed));
    });
  });

  group('Edit', () {
    test('an updated goal is reflected in the list', () async {
      final service = FakeGoalService(initial: [sampleGoal()]);
      final container = await containerWith(service);
      await settleGoals(container);

      final existing = container.read(goalsControllerProvider).goals.single;
      final result = await container
          .read(goalsControllerProvider.notifier)
          .update(existing.copyWith(title: 'Renamed', targetAmount: 2000000));

      expect(result, GoalActionResult.success);
      final goal = container.read(goalsControllerProvider).goals.single;
      expect(goal.title, 'Renamed');
      expect(goal.targetAmount, 2000000);
      // The list comes back from the server, so derived values are fresh.
      expect(goal.isServerDerived, isTrue);
    });
  });

  group('Delete', () {
    test('a deleted goal disappears', () async {
      final service = FakeGoalService(
        initial: [
          sampleGoal(),
          sampleGoal(id: 'goal_2', title: 'Home'),
        ],
      );
      final container = await containerWith(service);
      await settleGoals(container);

      final result = await container
          .read(goalsControllerProvider.notifier)
          .delete('goal_1');

      expect(result, GoalActionResult.success);
      final titles = container
          .read(goalsControllerProvider)
          .goals
          .map((g) => g.title);
      expect(titles, ['Home']);
    });

    test('deleting the last goal returns to the empty state', () async {
      final service = FakeGoalService(initial: [sampleGoal()]);
      final container = await containerWith(service);
      await settleGoals(container);

      await container.read(goalsControllerProvider.notifier).delete('goal_1');

      expect(container.read(goalsControllerProvider).isEmpty, isTrue);
    });
  });

  group('Failures', () {
    test('field errors are mapped onto the fields the server named', () async {
      final service = FakeGoalService();
      service.onCreate = (_) async => throw ValidationException('Invalid', {
        'saved_amount': [
          'You have already saved more than the target. Raise the target instead.',
        ],
        'target_date': ['Pick a date in the future.'],
      });

      final container = await containerWith(service);
      await settleGoals(container);

      final result = await container
          .read(goalsControllerProvider.notifier)
          .create(sampleGoal(id: ''));

      expect(result, GoalActionResult.validationFailed);
      final state = container.read(goalsControllerProvider);
      expect(
        state.fieldErrors['saved_amount'],
        contains('more than the target'),
      );
      expect(state.fieldErrors['target_date'], 'Pick a date in the future.');
      expect(state.busy, isFalse);
    });

    test('a network failure is reported and retryable', () async {
      final service = FakeGoalService();
      var attempts = 0;
      service.onCreate = (g) async {
        attempts++;
        if (attempts == 1) throw NetworkException();
        return g.withLocalDerived();
      };

      final container = await containerWith(service);
      await settleGoals(container);
      final controller = container.read(goalsControllerProvider.notifier);

      expect(
        await controller.create(sampleGoal(id: '')),
        GoalActionResult.failed,
      );
      expect(
        container.read(goalsControllerProvider).actionError,
        contains('Could not reach FynnEdge'),
      );

      expect(
        await controller.create(sampleGoal(id: '')),
        GoalActionResult.success,
      );
      expect(container.read(goalsControllerProvider).actionError, isNull);
    });

    test(
      'a 401 shows no inline error — the global handler takes over',
      () async {
        final service = FakeGoalService();
        service.onCreate = (_) async => throw UnauthorizedException();

        final container = await containerWith(service);
        await settleGoals(container);

        final result = await container
            .read(goalsControllerProvider.notifier)
            .create(sampleGoal(id: ''));

        expect(result, GoalActionResult.unauthorized);
        final state = container.read(goalsControllerProvider);
        expect(state.actionError, isNull);
        expect(state.busy, isFalse);
      },
    );

    test('a deleted-elsewhere goal surfaces as a plain failure', () async {
      final service = FakeGoalService(initial: [sampleGoal()]);
      service.onDelete = (_) async =>
          throw NotFoundException('That goal no longer exists.');

      final container = await containerWith(service);
      await settleGoals(container);

      expect(
        await container.read(goalsControllerProvider.notifier).delete('goal_1'),
        GoalActionResult.failed,
      );
      expect(
        container.read(goalsControllerProvider).actionError,
        'That goal no longer exists.',
      );
    });

    test('clearErrors wipes stale validation', () async {
      final service = FakeGoalService();
      service.onCreate = (_) async => throw ValidationException('Invalid', {
        'title': ['Give the goal a name.'],
      });

      final container = await containerWith(service);
      await settleGoals(container);
      final controller = container.read(goalsControllerProvider.notifier);

      await controller.create(sampleGoal(id: ''));
      expect(container.read(goalsControllerProvider).fieldErrors, isNotEmpty);

      controller.clearErrors();
      expect(container.read(goalsControllerProvider).fieldErrors, isEmpty);
    });
  });

  group('Mock mode and Home synchronisation', () {
    // No fakes: this proves the shipped mock wiring shares one customer.
    setUp(MockStore.instance.reset);
    tearDown(MockStore.instance.reset);

    Future<ProviderContainer> realMockContainer() async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      container.listen(goalsControllerProvider, (_, _) {});
      return container;
    }

    test('mock mode returns server-shaped derived values', () async {
      final container = await realMockContainer();
      await settleGoals(container);

      final goals = container.read(goalsControllerProvider).goals;
      expect(goals, isNotEmpty);
      expect(goals.every((g) => g.isServerDerived), isTrue);
      // Ordered by deadline, as the API orders them.
      for (var i = 1; i < goals.length; i++) {
        expect(goals[i].targetDate.isBefore(goals[i - 1].targetDate), isFalse);
      }
    });

    test('creating a goal is visible on Home', () async {
      final container = await realMockContainer();
      container.listen(homeSnapshotProvider, (_, _) {});
      await settleGoals(container);

      final before = await container.read(homeSnapshotProvider.future);
      final totalBefore = before.goalsTotal;

      await container
          .read(goalsControllerProvider.notifier)
          .create(
            Goal(
              id: '',
              title: 'Sabbatical',
              category: GoalCategory.personal,
              targetAmount: 600000,
              // Sooner than anything seeded, so it leads the nearest-first
              // list Home shows rather than sitting past the cut.
              targetDate: AppClock.now().add(const Duration(days: 20)),
            ),
          );

      final after = await container.read(homeSnapshotProvider.future);
      // Home shows the nearest few and reports how many there are.
      expect(after.goalsTotal, totalBefore + 1);
      expect(after.goals.first.title, 'Sabbatical');
    });

    test('deleting a goal removes it from Home', () async {
      final container = await realMockContainer();
      container.listen(homeSnapshotProvider, (_, _) {});
      await settleGoals(container);

      final target = container.read(goalsControllerProvider).goals.first;
      await container.read(goalsControllerProvider.notifier).delete(target.id);

      final after = await container.read(homeSnapshotProvider.future);
      expect(
        after.goals.map((g) => g.id),
        isNot(contains(target.id)),
        reason: 'Home must not keep showing a deleted goal',
      );
    });

    test('renaming a goal updates Home', () async {
      final container = await realMockContainer();
      container.listen(homeSnapshotProvider, (_, _) {});
      await settleGoals(container);

      final target = container.read(goalsControllerProvider).goals.first;
      await container
          .read(goalsControllerProvider.notifier)
          .update(target.copyWith(title: 'Renamed On Purpose'));

      final after = await container.read(homeSnapshotProvider.future);
      expect(after.goals.map((g) => g.title), contains('Renamed On Purpose'));
    });

    test('the shared goals provider is refreshed too', () async {
      final container = await realMockContainer();
      container.listen(goalsProvider, (_, _) {});
      await settleGoals(container);

      final before = await container.read(goalsProvider.future);

      await container
          .read(goalsControllerProvider.notifier)
          .create(
            Goal(
              id: '',
              title: 'Extra',
              category: GoalCategory.other,
              targetAmount: 100000,
              targetDate: AppClock.now().add(const Duration(days: 200)),
            ),
          );

      final after = await container.read(goalsProvider.future);
      expect(after.length, before.length + 1);
    });

    test('mock mode enforces saved > target, as the API does', () async {
      final container = await realMockContainer();
      await settleGoals(container);

      final result = await container
          .read(goalsControllerProvider.notifier)
          .create(
            Goal(
              id: '',
              title: 'Overshot',
              category: GoalCategory.other,
              targetAmount: 100000,
              targetDate: AppClock.now().add(const Duration(days: 365)),
              savedAmount: 200000,
            ),
          );

      expect(result, GoalActionResult.validationFailed);
      expect(
        container.read(goalsControllerProvider).fieldErrors['saved_amount'],
        isNotNull,
      );
    });

    test('mock mode rejects a past target date', () async {
      final container = await realMockContainer();
      await settleGoals(container);

      final result = await container
          .read(goalsControllerProvider.notifier)
          .create(
            Goal(
              id: '',
              title: 'Backwards',
              category: GoalCategory.other,
              targetAmount: 100000,
              targetDate: AppClock.now().subtract(const Duration(days: 10)),
            ),
          );

      expect(result, GoalActionResult.validationFailed);
      expect(
        container.read(goalsControllerProvider).fieldErrors['target_date'],
        isNotNull,
      );
    });

    test('mock mode 404s on a goal that is not the customer\'s', () async {
      final container = await realMockContainer();
      await settleGoals(container);

      expect(
        await container
            .read(goalsControllerProvider.notifier)
            .delete('someone-elses-goal'),
        GoalActionResult.failed,
      );
    });
  });
}
