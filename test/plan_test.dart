import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/core/utils/clock.dart';
import 'package:fynnedge/data/models/goal.dart';
import 'package:fynnedge/data/models/intent.dart';
import 'package:fynnedge/data/models/intelligence.dart';
import 'package:fynnedge/data/services/intelligence_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/intelligence/intelligence_controller.dart';
import 'package:fynnedge/features/profile/goals_controller.dart';
import 'package:fynnedge/features/profile/goals_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';
import 'support/plan_fixtures.dart';

/// Module 34 — the financial plan.
///
/// The plan is a view, not an engine. It shows the position the server
/// worked out, the goals the customer created and the one step the existing
/// action ladder produced. These tests are about what it may and may not
/// say about those three things.
///
/// Every guard here is checked twice: once for the state that must suppress
/// something, and once for the state that must show it. A test that only
/// ever asserts an absence passes just as well when the thing it guards was
/// never reachable — which is exactly how Module 33's sales-bias defect
/// survived a test written to prevent it.
void main() {
  setUpAll(initTestEnvironment);

  Future<void> pumpPlan(
    WidgetTester tester, {
    required List<Goal> goals,
    IntelligenceService? intelligence,
    FinancialPosition position = comfortablePosition,
    NextAction action = bufferAction,
    Size size = kNormalPhone,
    bool settleFirst = true,
  }) async {
    await pumpScreen(
      tester,
      const GoalsScreen(),
      overrides: [
        profileServiceProvider.overrideWithValue(PlanGoals(goals)),
        intelligenceServiceProvider.overrideWithValue(
          intelligence ?? PlanIntelligence(planned(position, action)),
        ),
      ],
      size: size,
    );
    if (settleFirst) await settle(tester);
  }

  const exploreLink = 'Explore options for this goal';

  group('a customer spending more than they earn', () {
    testWidgets('is not pointed at borrowing from their goal', (tester) async {
      await pumpPlan(
        tester,
        goals: [planGoal()],
        position: shortfallPosition,
        action: reviewFiguresAction,
        size: const Size(390, 1600),
      );

      // The goal card is on screen — this is not passing because the card
      // never rendered.
      expect(find.text('Emergency fund'), findsOneWidget);
      expect(find.text('Update what you have saved'), findsOneWidget);

      expect(find.text(exploreLink), findsNothing);

      // And nothing else on the plan suggests a way to cover the gap.
      for (final word in ['loan', 'borrow', 'credit card', 'top-up']) {
        expect(
          find.textContaining(word, findRichText: true),
          findsNothing,
          reason: 'the plan suggested "$word" to a customer with a shortfall',
        );
      }
    });

    testWidgets('states the position without judging it', (tester) async {
      await pumpPlan(
        tester,
        goals: const [],
        position: shortfallPosition,
        action: reviewFiguresAction,
      );

      expect(
        find.text(
          'Your recorded monthly outgo is higher than your recorded income.',
        ),
        findsOneWidget,
      );
      // The sign leads the figure, so the direction is not carried by
      // colour alone.
      expect(find.text('-₹18,000'), findsOneWidget);
    });

    /*
     * The other half of the guard.
     *
     * Without this the absence above proves nothing: the link could have
     * been removed from the card altogether, or the card could be
     * unreachable, and the test would still pass. It is reachable, and the
     * only thing keeping it away from this customer is the surplus.
     */
    testWidgets('but the same card offers it when there is a surplus', (
      tester,
    ) async {
      await pumpPlan(
        tester,
        goals: [planGoal()],
        size: const Size(390, 1600),
      );

      expect(find.text(exploreLink), findsOneWidget);
    });

    testWidgets('and it is withheld while the position is unknown', (
      tester,
    ) async {
      await pumpPlan(
        tester,
        goals: [planGoal()],
        intelligence: const UnreachableIntelligenceState(),
        size: const Size(390, 1600),
      );

      expect(find.text('Emergency fund'), findsOneWidget);
      expect(find.text(exploreLink), findsNothing);
    });
  });

  group('a goal whose amounts have met', () {
    testWidgets('is shown as reached, with no monthly figure', (tester) async {
      await pumpPlan(
        tester,
        goals: [reachedGoal],
        size: const Size(390, 1600),
      );

      expect(find.textContaining('Goal reached'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      // Nothing is still required of them, and nothing points them onward.
      expect(find.textContaining('calculated monthly amount'), findsNothing);
      expect(find.text(exploreLink), findsNothing);
    });

    testWidgets('while an unmet goal still shows what it comes to', (
      tester,
    ) async {
      await pumpPlan(
        tester,
        goals: [planGoal()],
        size: const Size(390, 1600),
      );

      expect(find.textContaining('Goal reached'), findsNothing);
      expect(find.textContaining('calculated monthly amount'), findsOneWidget);
    });
  });

  testWidgets('a passed target date is stated, never scored', (tester) async {
    await pumpPlan(
      tester,
      goals: [strainedGoal],
      size: const Size(390, 1600),
    );

    expect(
      find.text('The target date has passed. Review the date or the amount.'),
      findsOneWidget,
    );

    for (final word in ['failed', 'missed', 'behind', 'off track']) {
      expect(
        find.textContaining(word, findRichText: true),
        findsNothing,
        reason: 'an overdue goal was described as "$word"',
      );
    }
  });

  testWidgets('a customer who has entered nothing is told so', (tester) async {
    await pumpPlan(
      tester,
      goals: const [],
      position: unknownPosition,
      action: completeProfileAction,
    );

    expect(
      find.text(
        'FynnEdge has no monthly income recorded, so it cannot work out your '
        'position.',
      ),
      findsOneWidget,
    );

    // No surplus, no outgo, no buffer — not even as zero. A zero here would
    // be a figure the customer never entered.
    expect(find.text('Monthly surplus'), findsNothing);
    expect(find.text('Monthly outgo'), findsNothing);
    expect(find.textContaining('₹'), findsNothing);
  });

  testWidgets('a position that cannot be read is not filled in', (
    tester,
  ) async {
    await pumpPlan(
      tester,
      goals: [planGoal()],
      intelligence: const UnreachableIntelligenceState(),
      size: const Size(390, 1600),
    );

    expect(
      find.text('Your current position could not be loaded.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Monthly surplus'), findsNothing);

    // The goals themselves are still what the server last saved, and still
    // render — an unreachable position is not an unreachable plan.
    expect(find.text('Emergency fund'), findsOneWidget);
  });

  testWidgets('a position still loading shows no figures', (tester) async {
    await pumpPlan(
      tester,
      goals: [planGoal()],
      intelligence: const PendingIntelligence(),
      settleFirst: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Monthly surplus'), findsNothing);
    expect(find.text('Your current position could not be loaded.'), findsNothing);
  });

  group('the monthly figure', () {
    testWidgets('is a calculation, never a commitment', (tester) async {
      await pumpPlan(
        tester,
        goals: [planGoal()],
        size: const Size(390, 1600),
      );

      expect(
        find.textContaining(
          'At your current target and date, the calculated monthly amount is',
        ),
        findsOneWidget,
      );

      /*
       * The wording this replaced.
       *
       * The card used to read "Set aside ₹9,474 a month for 19 months to
       * get there" — an instruction the customer never agreed to, followed
       * by a promise about where it would take them. FynnEdge holds no
       * savings commitment and cannot know where anything leads.
       */
      for (final claim in [
        'Set aside',
        'to get there',
        'on track',
        'you will',
        "you'll",
        'guaranteed',
        'required saving',
      ]) {
        expect(
          find.textContaining(claim, findRichText: true),
          findsNothing,
          reason: 'the plan claimed "$claim"',
        );
      }
    });

    testWidgets('comes from the server, not from the screen', (tester) async {
      // Deliberately not what saved/target and the date would produce: if
      // the screen recalculated, this figure would not appear.
      final serverFigure = Goal(
        id: 'g',
        title: 'Emergency fund',
        category: GoalCategory.other,
        targetAmount: 300000,
        targetDate: AppClock.now().add(const Duration(days: 540)),
        savedAmount: 120000,
        derived: const GoalDerived(
          progress: 0.4,
          monthsRemaining: 18,
          monthlyRequired: 11111,
          remainingAmount: 180000,
          isComplete: false,
          isOverdue: false,
        ),
      );

      await pumpScreen(
        tester,
        const GoalsScreen(),
        overrides: [
          profileServiceProvider.overrideWithValue(_FixedGoals([serverFigure])),
          intelligenceServiceProvider.overrideWithValue(
            PlanIntelligence(planned(comfortablePosition, bufferAction)),
          ),
        ],
        size: const Size(390, 1600),
      );
      await settle(tester);

      expect(find.textContaining('₹11,111 over 18 months'), findsOneWidget);
    });
  });

  testWidgets('the next step never repeats the sentence above it', (
    tester,
  ) async {
    // The buffer rung's reason is the buffer sentence, so the position card
    // and the step beneath it carry the same words.
    await pumpPlan(tester, goals: const []);

    expect(
      find.text(
        'Your recorded savings would cover about 3 months of your monthly '
        'outgo. FynnEdge measures against 6 months.',
      ),
      findsOneWidget,
    );
    expect(find.text('Look at your savings buffer'), findsOneWidget);
  });

  testWidgets('progress is readable without colour', (tester) async {
    await pumpPlan(
      tester,
      goals: [planGoal()],
      size: const Size(390, 1600),
    );

    // The bar is decoration. The same fact is on screen as a percentage and
    // as two amounts.
    expect(find.text('40%'), findsOneWidget);
    expect(find.textContaining('saved of'), findsOneWidget);
  });

  group('a goal change reaches the plan', () {
    test('creating one re-reads the intelligence the plan is built from', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final service = _CountingIntelligence();

      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          profileServiceProvider.overrideWithValue(const PlanGoals([])),
          intelligenceServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);

      container.listen(intelligenceProvider, (_, _) {});
      container.listen(goalsControllerProvider, (_, _) {});
      await container.read(intelligenceProvider.future);
      expect(service.reads, 1);

      await container
          .read(goalsControllerProvider.notifier)
          .create(planGoal(id: ''));

      /*
       * Not merely refreshed: the plan and Home's next steps are derived
       * from the customer's current state, so the ladder that said "set
       * something to aim at" is wrong the moment they do. Nothing
       * invalidated this, and both screens went on suggesting the step the
       * customer had just taken.
       */
      await container.read(intelligenceProvider.future);
      expect(service.reads, 2);
    });
  });
}

/// Returns exactly the goals it was given, server figures and all.
class _FixedGoals extends PlanGoals {
  const _FixedGoals(this._fixed) : super(const []);

  final List<Goal> _fixed;

  @override
  Future<List<Goal>> getGoals() async => _fixed;
}

class _CountingIntelligence implements IntelligenceService {
  int reads = 0;

  @override
  Future<FinancialIntelligence> getIntelligence() async {
    reads++;
    return planned(comfortablePosition, bufferAction);
  }

  @override
  Future<List<FinancialMoment>> getTimeline() async => const [];
}
