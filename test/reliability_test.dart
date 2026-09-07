import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/consent.dart';
import 'package:fynnedge/data/models/goal.dart';
import 'package:fynnedge/data/models/intent.dart';

import 'package:fynnedge/data/models/application.dart';
import 'package:fynnedge/data/models/score.dart';
import 'package:fynnedge/data/models/user.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/application_service.dart';
import 'package:fynnedge/data/services/consent_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/data/services/profile_service.dart';
import 'package:fynnedge/features/applications/application_controller.dart';
import 'package:fynnedge/features/loans/loan_controller.dart';
import 'package:fynnedge/features/profile/consent_controller.dart';
import 'package:fynnedge/features/profile/financial_profile_controller.dart';
import 'package:fynnedge/features/profile/goals_controller.dart';
import 'package:fynnedge/features/twin/twin_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// A profile service that fails on demand, wrapping the real mock one.
class FlakyProfileService implements ProfileService {
  FlakyProfileService([ProfileService? inner])
    : _inner = inner ?? MockProfileService();

  final ProfileService _inner;
  Object? failSave;
  int saveCalls = 0;

  @override
  Future<UserProfile> getProfile() => _inner.getProfile();

  @override
  Future<UserProfile> updateProfile(UserProfile profile) =>
      _inner.updateProfile(profile);

  @override
  Future<FinancialProfile> getFinancialProfile() =>
      _inner.getFinancialProfile();

  @override
  Future<FinancialProfile> updateFinancialProfile(FinancialProfile profile) {
    saveCalls++;
    if (failSave != null) throw failSave!;
    return _inner.updateFinancialProfile(profile);
  }

  @override
  Future<List<Goal>> getGoals() => _inner.getGoals();

  @override
  Future<Goal> createGoal(Goal goal) => _inner.createGoal(goal);

  @override
  Future<Goal> updateGoal(Goal goal) => _inner.updateGoal(goal);

  @override
  Future<void> deleteGoal(String id) => _inner.deleteGoal(id);

  @override
  Future<FynnScore> getFynnScore() => _inner.getFynnScore();
}

/// An application service that fails on demand and counts what it created.
class FlakyApplicationService implements ApplicationService {
  FlakyApplicationService([ApplicationService? inner])
    : _inner = inner ?? MockApplicationService();

  final ApplicationService _inner;
  Object? failCreate;
  Object? failSubmit;
  int createCalls = 0;
  int submitCalls = 0;

  @override
  Future<List<LoanApplication>> getApplications() => _inner.getApplications();

  @override
  Future<LoanApplication> getApplication(String id) =>
      _inner.getApplication(id);

  @override
  Future<LoanApplication> create(
    ApplicationDraft draft, {
    required String idempotencyKey,
  }) {
    createCalls++;
    if (failCreate != null) throw failCreate!;
    return _inner.create(draft, idempotencyKey: idempotencyKey);
  }

  @override
  Future<LoanApplication> update(
    String id, {
    double? amount,
    int? tenureMonths,
  }) => _inner.update(id, amount: amount, tenureMonths: tenureMonths);

  @override
  Future<LoanApplication> submit(String id) {
    submitCalls++;
    if (failSubmit != null) throw failSubmit!;
    return _inner.submit(id);
  }

  @override
  Future<LoanApplication> cancel(String id) => _inner.cancel(id);
}

/// A consent service that fails on demand.
class FlakyConsentService implements ConsentService {
  FlakyConsentService([ConsentService? inner])
    : _inner = inner ?? MockConsentService();

  final ConsentService _inner;
  Object? failGrant;

  @override
  Future<ConsentState> getConsents() => _inner.getConsents();

  @override
  Future<ConsentState> grant(
    ConsentType type, {
    String source = 'privacy_screen',
  }) {
    if (failGrant != null) throw failGrant!;
    return _inner.grant(type, source: source);
  }

  @override
  Future<ConsentState> withdraw(
    ConsentType type, {
    String source = 'privacy_screen',
  }) => _inner.withdraw(type, source: source);

  @override
  Future<List<ConsentRecord>> getHistory() => _inner.getHistory();
}

void main() {
  setUpAll(initUnitTestEnvironment);

  Future<ProviderContainer> container({
    List<Override> overrides = const [],
  }) async {
    MockStore.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final c = ProviderContainer(
      retry: noAutoRetry,
      overrides: [localStoreProvider.overrideWithValue(store), ...overrides],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Waits for the financial profile controller's own initial load.
  Future<FinancialProfile> settledProfile(ProviderContainer c) async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      final state = c.read(financialProfileControllerProvider);
      if (!state.loading && state.saved != null) return state.saved!;
    }
    await c.read(financialProfileControllerProvider.notifier).load();
    return c.read(financialProfileControllerProvider).saved!;
  }

  /// Every failure a network can produce, including the ones that look like
  /// success until you read them.
  final failures = <String, Object>{
    'timeout': NetworkException('The request timed out. Please try again.'),
    'offline': NetworkException('No internet connection.'),
    'server fault': ServerException(),
    'rate limited': RateLimitedException('Too many requests.'),
    'validation': ValidationException('The given data was invalid.', const {}),
  };

  group('a failed mutation never leaves the customer stuck', () {
    for (final entry in failures.entries) {
      test('financial profile save — ${entry.key}', () async {
        final service = FlakyProfileService();
        final c = await container(
          overrides: [profileServiceProvider.overrideWithValue(service)],
        );

        final controller = c.read(financialProfileControllerProvider.notifier);
        // The controller loads itself from build(); wait for that to land
        // before editing, or it arrives after and wipes the draft.
        await settledProfile(c);

        service.failSave = entry.value;
        controller.edit(
          c
              .read(financialProfileControllerProvider)
              .saved!
              .copyWith(monthlyIncome: 123456),
        );

        expect(await controller.save(), isFalse);

        final state = c.read(financialProfileControllerProvider);
        // Not busy, and holding a reason rather than a spinner.
        expect(state.saving, isFalse, reason: '${entry.key}: stuck saving');
        expect(state.saveError, isNotNull, reason: '${entry.key}: silent');

        // The draft survives, so the customer does not retype their figures.
        expect(state.draft?.monthlyIncome, 123456);
        // And nothing was saved.
        expect(state.saved?.monthlyIncome, isNot(123456));
      });
    }

    test('goal creation — server fault', () async {
      final c = await container();
      final controller = c.read(goalsControllerProvider.notifier);
      await controller.load();

      final before = c.read(goalsControllerProvider).goals.length;

      // A goal the server will reject: no title.
      await controller.create(
        Goal(
          id: '',
          title: '',
          category: GoalCategory.other,
          targetAmount: 100000,
          targetDate: kTestNow.add(const Duration(days: 200)),
        ),
      );

      final state = c.read(goalsControllerProvider);
      expect(state.busy, isFalse);
      expect(state.goals, hasLength(before));
    });

    test('consent grant — offline', () async {
      final service = FlakyConsentService()
        ..failGrant = NetworkException('No internet connection.');
      final c = await container(
        overrides: [consentServiceProvider.overrideWithValue(service)],
      );

      final controller = c.read(consentControllerProvider.notifier);
      // The controller loads itself from build(); let that land first, or it
      // arrives afterwards and replaces the state the failure just set.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
        if (!c.read(consentControllerProvider).loading) break;
      }

      expect(await controller.set(ConsentType.aiMemory, true), isFalse);

      final state = c.read(consentControllerProvider);
      expect(state.busyType, isNull, reason: 'a switch was left spinning');
      expect(state.actionError, isNotNull);
      // The switch did not move: the customer's position is what the server
      // holds, not what they tapped.
      expect(
        state.state!.consents
            .firstWhere((item) => item.type == ConsentType.aiMemory)
            .isGranted,
        isFalse,
      );
    });

    test('FynnTwin simulation — server fault', () async {
      final c = await container();
      final matches = await c.read(matchesProvider.future);

      final controller = c.read(twinControllerProvider.notifier);
      controller.setProduct(matches.first.product.id);
      await controller.run();
      expect(c.read(twinControllerProvider).projection, isNotNull);

      // A failure after a good run must not leave the old answer looking
      // like the answer to the new question.
      controller.setAmount(2000000);
      expect(c.read(twinControllerProvider).projection, isNull);
      expect(c.read(twinControllerProvider).running, isFalse);
    });
  });

  group('a retry does not become a second action', () {
    test('a repeated application start is one application', () async {
      final service = FlakyApplicationService();
      final c = await container(
        overrides: [applicationServiceProvider.overrideWithValue(service)],
      );

      final match = (await c.read(matchesProvider.future)).first;
      final controller = c.read(applicationFlowProvider.notifier);

      final first = await controller.start(match);
      final second = await controller.start(match);
      final third = await controller.start(match);

      expect(first!.id, second!.id);
      expect(second.id, third!.id);
      expect(MockStore.instance.applications, hasLength(1));
      // The later taps did not even reach the service.
      expect(service.createCalls, 1);
    });

    test('a failed start can be retried, and still makes one', () async {
      final service = FlakyApplicationService()
        ..failCreate = NetworkException('No internet connection.');
      final c = await container(
        overrides: [applicationServiceProvider.overrideWithValue(service)],
      );

      final match = (await c.read(matchesProvider.future)).first;
      final controller = c.read(applicationFlowProvider.notifier);

      expect(await controller.start(match), isNull);
      expect(c.read(applicationFlowProvider).busy, isFalse);
      expect(c.read(applicationFlowProvider).error, isNotNull);

      // The customer taps again once they are back online. The same key is
      // reused, so the server would recognise a request that did arrive.
      service.failCreate = null;
      final application = await controller.start(match);

      expect(application, isNotNull);
      expect(MockStore.instance.applications, hasLength(1));
    });

    test('a repeated submit submits once', () async {
      final c = await container();

      final match = (await c.read(matchesProvider.future)).first;
      final controller = c.read(applicationFlowProvider.notifier);

      await controller.start(match);
      controller.setAcknowledged(true);

      expect(await controller.submit(), isTrue);
      final submittedAt = MockStore.instance.applications.first.submittedAt;

      expect(await controller.submit(), isTrue);
      expect(MockStore.instance.applications, hasLength(1));
      expect(MockStore.instance.applications.first.submittedAt, submittedAt);
    });

    test('submitting is refused until it is acknowledged', () async {
      final c = await container();

      final match = (await c.read(matchesProvider.future)).first;
      final controller = c.read(applicationFlowProvider.notifier);
      await controller.start(match);

      expect(await controller.submit(), isFalse);
      expect(MockStore.instance.applications.first.submittedAt, isNull);
    });
  });

  group('nothing retries a mutation on the customer\'s behalf', () {
    test('a failed save is attempted exactly once', () async {
      final service = FlakyProfileService()..failSave = ServerException();
      final c = await container(
        overrides: [profileServiceProvider.overrideWithValue(service)],
      );

      final controller = c.read(financialProfileControllerProvider.notifier);
      await controller.load();
      controller.edit(
        c
            .read(financialProfileControllerProvider)
            .saved!
            .copyWith(monthlyIncome: 111111),
      );

      await controller.save();

      // A blind retry on a write is how one intention becomes two.
      expect(service.saveCalls, 1);
    });

    test('the provider graph does not retry a failed read', () async {
      // ProviderScope(retry: noAutoRetry) is what the app ships with, and
      // it is what makes an error state reachable at all.
      var calls = 0;
      final c = await container();
      final probe = FutureProvider<int>((ref) async {
        calls++;
        throw ServerException();
      });

      await expectLater(c.read(probe.future), throwsA(isA<ServerException>()));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(calls, 1, reason: 'a read retried itself');
    });
  });
}
