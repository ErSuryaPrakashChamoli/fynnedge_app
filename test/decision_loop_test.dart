import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/app/session.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/application.dart';
import 'package:fynnedge/data/models/goal.dart';
import 'package:fynnedge/data/models/intent.dart';
import 'package:fynnedge/data/models/loan.dart';
import 'package:fynnedge/data/models/user.dart';
import 'package:fynnedge/data/services/home_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fynnedge/features/applications/application_controller.dart';
import 'package:fynnedge/features/home/home_controller.dart';
import 'package:fynnedge/features/loans/loan_controller.dart';
import 'package:fynnedge/features/profile/financial_profile_controller.dart';
import 'package:fynnedge/features/profile/profile_controller.dart';
import 'package:fynnedge/features/twin/twin_controller.dart';
import 'package:fynnedge/data/models/twin.dart';

import 'support/harness.dart';

/// The canonical FynnEdge journey, stage by stage.
///
/// These are not screen tests — screens_test and navigation_flow_test cover
/// rendering and routing. What is asserted here is that the *decision*
/// survives each handover: the same product, the same amount, the same term
/// and the same pricing, from a goal all the way to a tracked application,
/// with nothing invented along the way and nothing stale left behind.
void main() {
  setUpAll(initUnitTestEnvironment);

  /// The real provider graph in mock mode — the same seam the app uses, with
  /// only the platform key/value store stubbed.
  Future<ProviderContainer> container() async {
    MockStore.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final c = ProviderContainer(
      retry: noAutoRetry,
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// The financial profile controller kicks its own load from build(), so a
  /// test that edits immediately can have its draft wiped by that load
  /// landing afterwards. This waits for the controller to be settled on the
  /// server's copy before anything is changed.
  Future<FinancialProfile> settledProfile(ProviderContainer c) async {
    final controller = c.read(financialProfileControllerProvider.notifier);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      final state = c.read(financialProfileControllerProvider);
      if (!state.loading && state.saved != null) return state.saved!;
    }
    await controller.load();
    return c.read(financialProfileControllerProvider).saved!;
  }

  /// Saves one change to the customer's figures, the way the screen does.
  Future<void> changeFigures(
    ProviderContainer c,
    FinancialProfile Function(FinancialProfile) change,
  ) async {
    final saved = await settledProfile(c);
    final controller = c.read(financialProfileControllerProvider.notifier);
    controller.edit(change(saved));
    expect(await controller.save(), isTrue, reason: 'the save was rejected');
  }

  // -------------------------------------------------------------- journey 1

  group('journey 1 — a new customer', () {
    test('is told nothing about money FynnEdge has not been given', () async {
      MockStore.instance.reset();
      MockStore.instance.financials = const FinancialProfile();
      MockStore.instance.profile = const UserProfile(id: 'u1', mobile: '');
      for (final goal in MockStore.instance.goals) {
        MockStore.instance.removeGoal(goal.id);
      }

      final home = await const MockHomeService().getSnapshot();

      // No name invented, no figure asserted, no score fabricated.
      expect(home.customer.firstName, isNull);
      expect(home.needsFinancialProfile, isTrue);
      expect(home.score.hasScore, isFalse);
      expect(home.financials.monthlyIncome, 0);
      expect(home.attention, isEmpty);
      expect(home.goals, isEmpty);
      expect(home.applications, isEmpty);
      expect(home.vaultDocumentCount, 0);

      // And the one thing it does offer is the step that would fix that.
      expect(home.primaryAction.key, 'complete_profile');
    });

    test('reaches a measured Home once they enter their figures', () async {
      final c = await container();
      MockStore.instance.financials = const FinancialProfile();

      c.listen(homeSnapshotProvider, (_, _) {});
      final before = await c.read(homeSnapshotProvider.future);
      expect(before.needsFinancialProfile, isTrue);

      await changeFigures(
        c,
        (p) => p.copyWith(
          monthlyIncome: 100000,
          monthlyExpenses: 40000,
          existingEmi: 20000,
          savings: 600000,
        ),
      );

      final after = await c.read(homeSnapshotProvider.future);
      expect(after.needsFinancialProfile, isFalse);
      expect(after.financials.monthlyIncome, 100000);
      expect(after.score.hasScore, isTrue);
      expect(after.primaryAction.key, isNot('complete_profile'));
    });
  });

  // -------------------------------------------------------------- journey 2

  group('journey 2 — a goal becomes a product decision', () {
    test('the goal seeds the request, and the request reaches the '
        'match, the detail, FynnTwin and FynnMirror unchanged', () async {
      final c = await container();

      final goal = Goal(
        id: 'g1',
        title: 'Second outlet',
        category: GoalCategory.business,
        targetAmount: 1500000,
        savedAmount: 300000,
        targetDate: kTestNow.add(const Duration(days: 540)),
      );

      // Stage B: what Goals hands to Loan Discovery.
      c
          .read(loanRequestProvider.notifier)
          .update(
            amount: goal.remainingAmount,
            purpose: goal.category.exploreCategory.id,
          );

      final request = c.read(loanRequestProvider);
      expect(request.amount, 1200000);
      expect(request.purpose, LoanCategory.business.id);

      // Stage: FynnMatch answers the request the goal set.
      final matches = await c.read(matchesProvider.future);
      expect(matches, isNotEmpty);

      final chosen = matches.first;
      expect(
        chosen.pricing.amount,
        request.amount,
        reason: 'FynnMatch priced a different amount from the one asked',
      );

      // Stage: Loan Detail is the same match, not a second lookup.
      final onDetail = await c.read(
        simulatedMatchProvider(chosen.product.id).future,
      );
      expect(onDetail.product.id, chosen.product.id);
      expect(onDetail.pricing.amount, chosen.pricing.amount);
      expect(onDetail.pricing.tenureMonths, chosen.pricing.tenureMonths);
      expect(onDetail.projection.emi, chosen.projection.emi);

      // Stage: FynnTwin, opened on that loan.
      c
          .read(twinControllerProvider.notifier)
          .presetLoan(
            productId: chosen.product.id,
            amount: chosen.pricing.amount,
            tenureMonths: chosen.pricing.tenureMonths,
          );
      final twin = c.read(twinControllerProvider);
      expect(twin.type, ScenarioType.loan);
      expect(twin.productId, chosen.product.id);
      expect(twin.amount, chosen.pricing.amount);
      expect(twin.tenureMonths, chosen.pricing.tenureMonths);

      // Stage: FynnTwin hands the same loan to FynnMirror.
      c
          .read(simulationInputsProvider.notifier)
          .setFor(
            productId: twin.productId!,
            amount: twin.amount,
            tenureMonths: twin.tenureMonths,
          );

      final onMirror = await c.read(
        simulatedMatchProvider(chosen.product.id).future,
      );
      expect(onMirror.pricing.amount, chosen.pricing.amount);
      expect(onMirror.pricing.tenureMonths, chosen.pricing.tenureMonths);
      expect(
        onMirror.projection.emi,
        chosen.projection.emi,
        reason: 'FynnMirror is framing a different loan from FynnTwin',
      );
    });

    test(
      'a goal the catalogue cannot serve is not given a fake match',
      () async {
        final c = await container();

        // ₹5,000 short of a goal: below every product's minimum.
        c.read(loanRequestProvider.notifier).update(amount: 5000);

        final result = await c.read(fynnMatchProvider.future);

        expect(result.viable, isEmpty);
        // And the reason is kept, so the screen can say why rather than
        // showing an empty list with no explanation.
        expect(result.rejected, isNotEmpty);
      },
    );
  });

  // -------------------------------------------------------------- journey 3

  group('journey 3 — a decision becomes an application', () {
    test(
      'the application keeps the exact pricing it was created from',
      () async {
        final c = await container();

        final matches = await c.read(matchesProvider.future);
        final chosen = matches.first;

        final application = await c
            .read(applicationFlowProvider.notifier)
            .start(chosen);

        expect(application, isNotNull);

        // Every figure the customer saw when they decided.
        expect(application!.productId, chosen.product.id);
        expect(application.amount, chosen.pricing.amount);
        expect(application.tenureMonths, chosen.pricing.tenureMonths);
        expect(application.interestRate, chosen.pricing.interestRate);
        expect(application.emi, chosen.pricing.emi);
        expect(application.totalInterest, chosen.pricing.totalInterest);
        expect(application.totalPayable, chosen.pricing.totalPayable);
        expect(application.processingFee, chosen.pricing.processingFee);
        expect(application.matchCategory, chosen.category.id);
      },
    );

    test('the snapshot survives a change to the customer\'s figures', () async {
      final c = await container();

      final chosen = (await c.read(matchesProvider.future)).first;
      final application = await c
          .read(applicationFlowProvider.notifier)
          .start(chosen);

      // The customer's income halves after applying.
      await changeFigures(c, (p) => p.copyWith(monthlyIncome: 50000));

      final reloaded = await c.read(
        applicationProvider(application!.id).future,
      );

      // An application records what was offered and accepted at the time.
      // Re-pricing it from today's figures would rewrite history.
      expect(reloaded.emi, application.emi);
      expect(reloaded.interestRate, application.interestRate);
      expect(reloaded.totalPayable, application.totalPayable);
      expect(reloaded.projectedEmiRatio, application.projectedEmiRatio);
    });

    test('it reaches Home and the applications list', () async {
      final c = await container();
      c.listen(homeSnapshotProvider, (_, _) {});
      c.listen(applicationsProvider, (_, _) {});

      expect((await c.read(homeSnapshotProvider.future)).applicationsTotal, 0);

      final chosen = (await c.read(matchesProvider.future)).first;
      await c.read(applicationFlowProvider.notifier).start(chosen);

      final home = await c.read(homeSnapshotProvider.future);
      expect(home.applicationsTotal, 1);
      expect(home.applicationsActive, 1);
      expect(home.primaryAction.key, 'view_applications');

      expect(await c.read(applicationsProvider.future), hasLength(1));
    });
  });

  // -------------------------------------------------------------- journey 4

  group('journey 4 — the figures change', () {
    test('Home, FynnScore and FynnMatch all move together', () async {
      final c = await container();
      c.listen(homeSnapshotProvider, (_, _) {});
      c.listen(fynnScoreProvider, (_, _) {});
      c.listen(fynnMatchProvider, (_, _) {});

      final homeBefore = await c.read(homeSnapshotProvider.future);
      final scoreBefore = await c.read(fynnScoreProvider.future);

      await changeFigures(c, (p) => p.copyWith(existingEmi: 60000));

      final homeAfter = await c.read(homeSnapshotProvider.future);
      final scoreAfter = await c.read(fynnScoreProvider.future);

      expect(homeAfter.financials.existingEmi, 60000);
      expect(
        homeAfter.financials.emiRatio,
        isNot(homeBefore.financials.emiRatio),
      );
      expect(scoreAfter.score, isNot(scoreBefore.score));

      // One score, one set of figures: Home and the FynnScore screen must
      // never disagree about the same customer.
      expect(homeAfter.score.score, scoreAfter.score);
      expect(homeAfter.score.band, scoreAfter.band);
    });

    test(
      'a FynnTwin result computed against the old figures is dropped',
      () async {
        final c = await container();

        final chosen = (await c.read(matchesProvider.future)).first;
        final twin = c.read(twinControllerProvider.notifier);
        twin.setProduct(chosen.product.id);
        await twin.run();

        expect(
          c.read(twinControllerProvider).projection,
          isNotNull,
          reason: 'the simulation did not produce a result to go stale',
        );

        final profile = c.read(financialProfileControllerProvider.notifier);
        await profile.load();
        final saved = c.read(financialProfileControllerProvider).saved!;
        profile.edit(saved.copyWith(monthlyIncome: 45000));
        await profile.save();

        final after = c.read(twinControllerProvider);
        // The left-hand column of that comparison no longer exists.
        expect(after.projection, isNull);
        // The assumptions the customer typed are still theirs.
        expect(after.productId, chosen.product.id);
        expect(after.type, ScenarioType.loan);
      },
    );

    test('a simulation changes nothing the customer has saved', () async {
      final c = await container();

      final before = await settledProfile(c);

      final chosen = (await c.read(matchesProvider.future)).first;
      final twin = c.read(twinControllerProvider.notifier);
      twin.setProduct(chosen.product.id);
      await twin.run();

      expect(c.read(twinControllerProvider).projection, isNotNull);

      final after = await c
          .read(profileRepositoryProvider)
          .getFinancialProfile();
      expect(after.monthlyIncome, before.monthlyIncome);
      expect(after.existingEmi, before.existingEmi);
      expect(after.savings, before.savings);
      expect(MockStore.instance.applications, isEmpty);
    });
  });

  // -------------------------------------------------------------- journey 5

  group('journey 5 — tracking an application', () {
    test('submitting marks it Simulated and claims no lender saw it', () async {
      final c = await container();
      c.listen(homeSnapshotProvider, (_, _) {});

      final chosen = (await c.read(matchesProvider.future)).first;
      final controller = c.read(applicationFlowProvider.notifier);

      final started = await controller.start(chosen);
      expect(started!.status, ApplicationStatus.started);

      // Submitting without acknowledging is refused, as Module 9 requires.
      expect(await controller.submit(), isFalse);

      controller.setAcknowledged(true);
      expect(await controller.submit(), isTrue);

      final application = await c.read(applicationProvider(started.id).future);

      expect(application.status, ApplicationStatus.submitted);
      // Module 9's line, still held: acknowledged by FynnEdge, seen by
      // nobody else.
      expect(application.isSimulated, isTrue);
      expect(application.status.isProviderDecision, isFalse);

      // No provider state was invented on the way.
      final history = application.events.map((e) => e.label).join(' | ');
      for (final claim in const [
        'Approved',
        'Declined',
        'Disbursed',
        'Under review',
        'Received by',
        'Verified',
      ]) {
        expect(
          history,
          isNot(contains(claim)),
          reason: 'a provider event was fabricated: $claim',
        );
      }
      // Every event that exists is FynnEdge speaking about its own side.
      expect(
        application.events.every((e) => e.source != EventSource.provider),
        isTrue,
      );

      final home = await c.read(homeSnapshotProvider.future);
      expect(home.applications.single.isSimulated, isTrue);
      expect(home.applications.single.status, 'submitted');
    });

    test('cancelling clears it from what Home counts as live', () async {
      final c = await container();
      c.listen(homeSnapshotProvider, (_, _) {});

      final chosen = (await c.read(matchesProvider.future)).first;
      final started = await c
          .read(applicationFlowProvider.notifier)
          .start(chosen);

      await c.read(applicationActionsProvider).cancel(started!.id);

      final home = await c.read(homeSnapshotProvider.future);
      expect(home.applicationsTotal, 1);
      expect(home.applicationsActive, 0);
    });
  });
}
