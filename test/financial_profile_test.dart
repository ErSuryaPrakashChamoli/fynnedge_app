import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/goal.dart';
import 'package:fynnedge/data/models/score.dart';
import 'package:fynnedge/data/models/user.dart';
import 'package:fynnedge/data/repositories/profile_repository.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/data/services/profile_service.dart';
import 'package:fynnedge/features/home/home_controller.dart';
import 'package:fynnedge/features/profile/financial_profile_controller.dart';
import 'package:fynnedge/features/profile/profile_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// A profile service whose behaviour each test dictates.
class FakeProfileService implements ProfileService {
  FakeProfileService({FinancialProfile? initial, this.onGet, this.onUpdate})
    : _financials = initial ?? const FinancialProfile();

  FinancialProfile _financials;

  final Future<FinancialProfile> Function()? onGet;
  final Future<FinancialProfile> Function(FinancialProfile)? onUpdate;

  int getCalls = 0;
  int updateCalls = 0;
  FinancialProfile? lastSent;

  @override
  Future<FinancialProfile> getFinancialProfile() async {
    getCalls++;
    if (onGet != null) return onGet!();
    return _financials.withLocalDerived();
  }

  @override
  Future<FinancialProfile> updateFinancialProfile(
    FinancialProfile profile,
  ) async {
    updateCalls++;
    lastSent = profile;
    if (onUpdate != null) return onUpdate!(profile);
    _financials = profile;
    return _financials.withLocalDerived();
  }

  // Unused by these tests.
  @override
  Future<UserProfile> getProfile() async =>
      const UserProfile(id: '1', mobile: '9876543210');
  @override
  Future<UserProfile> updateProfile(UserProfile profile) async => profile;
  @override
  Future<List<Goal>> getGoals() async => const [];
  @override
  Future<Goal> createGoal(Goal goal) async => goal;
  @override
  Future<Goal> updateGoal(Goal goal) async => goal;
  @override
  Future<void> deleteGoal(String id) async {}
  @override
  Future<FynnScore> getFynnScore() async => const FynnScore(hasScore: false);
}

Future<ProviderContainer> containerWith(
  FakeProfileService service, {
  List<Override> extra = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      profileServiceProvider.overrideWithValue(service),
      profileRepositoryProvider.overrideWith(
        (ref) => ProfileRepository(service, store),
      ),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Waits for the controller's first load to finish.
///
/// Polls rather than sleeping a fixed amount: the real mock services carry
/// deliberate latency, and a hard-coded delay would either be flaky or slow.
Future<void> settleController(ProviderContainer c) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (!c.read(financialProfileControllerProvider).loading) return;
  }
  fail('The controller never finished loading');
}

const _seed = FinancialProfile(
  monthlyIncome: 100000,
  monthlyExpenses: 40000,
  existingEmi: 20000,
  savings: 180000,
  employment: EmploymentType.business,
);

void main() {
  setUpAll(initUnitTestEnvironment);

  group('Loading', () {
    test('starts in a loading state with nothing to show', () async {
      final service = FakeProfileService(initial: _seed);
      final container = await containerWith(service);
      // A listener keeps the provider alive while its first load runs.
      container.listen(financialProfileControllerProvider, (_, _) {});

      final initial = container.read(financialProfileControllerProvider);
      expect(initial.loading, isTrue);
      expect(initial.current, isNull);
    });

    test('resolves to the customer\'s real figures', () async {
      final service = FakeProfileService(initial: _seed);
      final container = await containerWith(service);
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      final state = container.read(financialProfileControllerProvider);
      expect(state.loading, isFalse);
      expect(state.saved!.monthlyIncome, 100000);
      expect(state.saved!.employment, EmploymentType.business);
      expect(service.getCalls, 1);
    });

    test('a failed load is reported and retryable', () async {
      var attempts = 0;
      final service = FakeProfileService(
        onGet: () async {
          attempts++;
          if (attempts == 1) throw NetworkException();
          return _seed.withLocalDerived();
        },
      );
      final container = await containerWith(service);
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      expect(
        container.read(financialProfileControllerProvider).loadError,
        isNotNull,
      );

      await container.read(financialProfileControllerProvider.notifier).load();

      final state = container.read(financialProfileControllerProvider);
      expect(state.loadError, isNull);
      expect(state.saved!.monthlyIncome, 100000);
    });

    test('an unfilled profile reports as empty', () async {
      final service = FakeProfileService(initial: const FinancialProfile());
      final container = await containerWith(service);
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      expect(
        container.read(financialProfileControllerProvider).isEmpty,
        isTrue,
      );
    });
  });

  group('Derived values', () {
    test('the server\'s figures are used, not recomputed', () async {
      // A server that reports a surplus the local arithmetic would not:
      // whatever it says must win.
      final service = FakeProfileService(
        onGet: () async => const FinancialProfile(
          monthlyIncome: 100000,
          monthlyExpenses: 40000,
          existingEmi: 20000,
          derived: FinancialDerived(
            surplus: 12345,
            emiRatio: 99,
            expenseRatio: 1,
            monthlyOutgo: 55555,
            emergencyMonths: 7,
          ),
        ),
      );
      final container = await containerWith(service);
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      final profile = container.read(financialProfileControllerProvider).saved!;
      expect(profile.surplus, 12345);
      expect(profile.emiRatio, 99);
      expect(profile.emergencyMonths, 7);
      expect(profile.isServerDerived, isTrue);
    });

    test('an edit drops the server figures and derives locally', () async {
      final service = FakeProfileService(initial: _seed);
      final container = await containerWith(service);
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      final controller = container.read(
        financialProfileControllerProvider.notifier,
      );
      final saved = container.read(financialProfileControllerProvider).saved!;
      controller.edit(saved.copyWith(monthlyIncome: 200000));

      final draft = container.read(financialProfileControllerProvider).draft!;
      expect(draft.isServerDerived, isFalse);
      // Live feedback while dragging: 200000 - 40000 - 20000.
      expect(draft.surplus, 140000);
    });
  });

  group('Editing', () {
    test('an unchanged draft is not treated as a change', () async {
      final service = FakeProfileService(initial: _seed);
      final container = await containerWith(service);
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      final state = container.read(financialProfileControllerProvider);
      container
          .read(financialProfileControllerProvider.notifier)
          .edit(state.saved!.copyWith(monthlyIncome: 100000));

      expect(
        container.read(financialProfileControllerProvider).hasUnsavedChanges,
        isFalse,
      );
    });

    test('discarding returns to the server copy', () async {
      final service = FakeProfileService(initial: _seed);
      final container = await containerWith(service);
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      final controller = container.read(
        financialProfileControllerProvider.notifier,
      );
      controller.edit(
        container
            .read(financialProfileControllerProvider)
            .saved!
            .copyWith(monthlyIncome: 500000),
      );
      controller.discardChanges();

      final state = container.read(financialProfileControllerProvider);
      expect(state.draft, isNull);
      expect(state.current!.monthlyIncome, 100000);
    });
  });

  group('Saving', () {
    test('a successful save replaces state with the server response', () async {
      final service = FakeProfileService(initial: _seed);
      final container = await containerWith(service);
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      final controller = container.read(
        financialProfileControllerProvider.notifier,
      );
      controller.edit(
        container
            .read(financialProfileControllerProvider)
            .saved!
            .copyWith(monthlyIncome: 150000, otherObligations: 5000),
      );

      expect(await controller.save(), isTrue);

      final state = container.read(financialProfileControllerProvider);
      expect(state.draft, isNull);
      expect(state.saved!.monthlyIncome, 150000);
      expect(state.saved!.otherObligations, 5000);
      // Derived values come back updated: 150000 - 40000 - 20000 - 5000.
      expect(state.saved!.surplus, 85000);
      expect(state.savedAt, isNotNull);
      expect(state.saveError, isNull);
    });

    test('every field reaches the service, none silently dropped', () async {
      final service = FakeProfileService(initial: _seed);
      final container = await containerWith(service);
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      final controller = container.read(
        financialProfileControllerProvider.notifier,
      );
      controller.edit(
        const FinancialProfile(
          monthlyIncome: 111,
          monthlyExpenses: 222,
          existingEmi: 333,
          savings: 444,
          otherObligations: 555,
          employment: EmploymentType.professional,
        ),
      );
      await controller.save();

      final sent = service.lastSent!;
      expect(sent.monthlyIncome, 111);
      expect(sent.monthlyExpenses, 222);
      expect(sent.existingEmi, 333);
      expect(sent.savings, 444);
      expect(sent.otherObligations, 555);
      expect(sent.employment, EmploymentType.professional);
    });

    test('a second tap while saving is ignored', () async {
      final service = FakeProfileService(
        initial: _seed,
        onUpdate: (p) async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return p.withLocalDerived();
        },
      );
      final container = await containerWith(service);
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      final controller = container.read(
        financialProfileControllerProvider.notifier,
      );
      controller.edit(
        container
            .read(financialProfileControllerProvider)
            .saved!
            .copyWith(monthlyIncome: 150000),
      );

      final results = await Future.wait([controller.save(), controller.save()]);

      expect(service.updateCalls, 1, reason: 'duplicate submission');
      expect(results, [true, false]);
    });

    test('nothing is sent when there is nothing to save', () async {
      final service = FakeProfileService(initial: _seed);
      final container = await containerWith(service);
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      expect(
        await container
            .read(financialProfileControllerProvider.notifier)
            .save(),
        isFalse,
      );
      expect(service.updateCalls, 0);
    });
  });

  group('Save failures', () {
    test('field errors are mapped onto the fields the server named', () async {
      final service = FakeProfileService(
        initial: _seed,
        onUpdate: (_) async =>
            throw ValidationException('Please check the details you entered.', {
              'monthly_expenses': [
                'Your outgoings are far above your income. Please check these figures.',
              ],
              'employment_type': ['Choose one of the listed employment types.'],
            }),
      );
      final container = await containerWith(service);
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      final controller = container.read(
        financialProfileControllerProvider.notifier,
      );
      controller.edit(
        container
            .read(financialProfileControllerProvider)
            .saved!
            .copyWith(monthlyExpenses: 900000),
      );

      expect(await controller.save(), isFalse);

      final state = container.read(financialProfileControllerProvider);
      expect(
        state.fieldErrors['monthly_expenses'],
        contains('far above your income'),
      );
      expect(state.fieldErrors['employment_type'], isNotNull);
      // The customer's entry is preserved so they can correct it.
      expect(state.draft!.monthlyExpenses, 900000);
      expect(state.saving, isFalse);
    });

    test('a network failure keeps the draft and offers a retry', () async {
      var attempts = 0;
      final service = FakeProfileService(
        initial: _seed,
        onUpdate: (p) async {
          attempts++;
          if (attempts == 1) throw NetworkException();
          return p.withLocalDerived();
        },
      );
      final container = await containerWith(service);
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      final controller = container.read(
        financialProfileControllerProvider.notifier,
      );
      controller.edit(
        container
            .read(financialProfileControllerProvider)
            .saved!
            .copyWith(monthlyIncome: 150000),
      );

      expect(await controller.save(), isFalse);

      var state = container.read(financialProfileControllerProvider);
      expect(state.saveError, contains('Could not reach FynnEdge'));
      // Not pretending it worked, and not losing the entry.
      expect(state.draft!.monthlyIncome, 150000);
      expect(state.saved!.monthlyIncome, 100000);

      // The retry path succeeds.
      expect(await controller.save(), isTrue);
      state = container.read(financialProfileControllerProvider);
      expect(state.saveError, isNull);
      expect(state.saved!.monthlyIncome, 150000);
    });

    test(
      'a 401 shows no inline error — the global handler takes over',
      () async {
        final service = FakeProfileService(
          initial: _seed,
          onUpdate: (_) async => throw UnauthorizedException(),
        );
        final container = await containerWith(service);
        container.listen(financialProfileControllerProvider, (_, _) {});
        await settleController(container);

        final controller = container.read(
          financialProfileControllerProvider.notifier,
        );
        controller.edit(
          container
              .read(financialProfileControllerProvider)
              .saved!
              .copyWith(monthlyIncome: 150000),
        );

        expect(await controller.save(), isFalse);

        final state = container.read(financialProfileControllerProvider);
        expect(state.saveError, isNull);
        expect(state.saving, isFalse);
      },
    );

    test('editing after a rejection clears the stale field errors', () async {
      final service = FakeProfileService(
        initial: _seed,
        onUpdate: (_) async => throw ValidationException('Invalid', {
          'monthly_income': ['That figure cannot be negative.'],
        }),
      );
      final container = await containerWith(service);
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      final controller = container.read(
        financialProfileControllerProvider.notifier,
      );
      final saved = container.read(financialProfileControllerProvider).saved!;
      controller.edit(saved.copyWith(monthlyIncome: 150000));
      await controller.save();

      expect(
        container.read(financialProfileControllerProvider).fieldErrors,
        isNotEmpty,
      );

      controller.edit(saved.copyWith(monthlyIncome: 160000));

      expect(
        container.read(financialProfileControllerProvider).fieldErrors,
        isEmpty,
      );
    });
  });

  group('Home synchronisation (real mock services)', () {
    // Deliberately no fakes here: this proves the shipped mock wiring shares
    // one customer, which is the behaviour that stops Home showing a figure
    // the customer already changed.
    setUp(MockStore.instance.reset);
    tearDown(MockStore.instance.reset);

    Future<ProviderContainer> realMockContainer() async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a save on Financial Profile reaches Home', () async {
      final container = await realMockContainer();
      container.listen(financialProfileControllerProvider, (_, _) {});
      container.listen(homeSnapshotProvider, (_, _) {});
      await settleController(container);

      final before = await container.read(homeSnapshotProvider.future);
      expect(before.financials.monthlyIncome, 100000);

      final controller = container.read(
        financialProfileControllerProvider.notifier,
      );
      final saved = container.read(financialProfileControllerProvider).saved!;
      controller.edit(saved.copyWith(monthlyIncome: 175000));
      expect(await controller.save(), isTrue);

      final after = await container.read(homeSnapshotProvider.future);
      expect(
        after.financials.monthlyIncome,
        175000,
        reason: 'Home must not keep showing a figure the customer changed',
      );
      expect(after.financials.surplus, 115000);
    });

    test('the shared financial provider is refreshed too', () async {
      final container = await realMockContainer();
      container.listen(financialProfileControllerProvider, (_, _) {});
      container.listen(financialProfileProvider, (_, _) {});
      await settleController(container);

      expect(
        (await container.read(financialProfileProvider.future)).monthlyIncome,
        100000,
      );

      final controller = container.read(
        financialProfileControllerProvider.notifier,
      );
      controller.edit(
        container
            .read(financialProfileControllerProvider)
            .saved!
            .copyWith(monthlyIncome: 190000),
      );
      await controller.save();

      expect(
        (await container.read(financialProfileProvider.future)).monthlyIncome,
        190000,
      );
    });

    test('mock mode enforces the same validation as the API', () async {
      final container = await realMockContainer();
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      final controller = container.read(
        financialProfileControllerProvider.notifier,
      );
      // Outgoings far above income: rejected by the backend FormRequest, so
      // mock mode must reject it too rather than quietly accepting.
      controller.edit(
        const FinancialProfile(monthlyIncome: 50000, monthlyExpenses: 400000),
      );

      expect(await controller.save(), isFalse);
      expect(
        container
            .read(financialProfileControllerProvider)
            .fieldErrors['monthly_expenses'],
        isNotNull,
      );
    });

    test('mock mode returns server-shaped derived values', () async {
      final container = await realMockContainer();
      container.listen(financialProfileControllerProvider, (_, _) {});
      await settleController(container);

      final saved = container.read(financialProfileControllerProvider).saved!;
      // Indistinguishable from the real API from the screen's point of view.
      expect(saved.isServerDerived, isTrue);
      expect(saved.surplus, 40000);
      expect(saved.emiRatio, 20);
      expect(saved.emergencyMonths, 3);
    });
  });
}
