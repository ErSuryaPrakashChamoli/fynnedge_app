import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/models/intelligence.dart';
import 'package:fynnedge/data/services/decision_service.dart';
import 'package:fynnedge/features/review/review_screen.dart';

import 'support/harness.dart';
import 'support/intelligence_fixtures.dart';
import 'support/plan_fixtures.dart';
import 'support/screen_catalog.dart';

/// Module 36 — the financial review.
///
/// The screen gathers; it computes nothing. So the tests are about what it
/// shows when a section has something to say, what it leaves out when a
/// section does not, and what it must never say however complete the rest
/// of the review looks.
///
/// Every guard is checked from both sides. A test that only asserts an
/// absence passes just as well when the thing it guards was unreachable.
void main() {
  setUpAll(initTestEnvironment);

  Future<void> pumpReview(
    WidgetTester tester, {
    required FinancialIntelligence data,
    DecisionService decisions = const EmptyDecisions(),
    Size size = const Size(390, 2200),
  }) async {
    await pumpScreen(
      tester,
      const ReviewScreen(),
      overrides: [
        intelligenceServiceProvider.overrideWithValue(PlanIntelligence(data)),
        decisionServiceProvider.overrideWithValue(decisions),
      ],
      size: size,
    );
    await settle(tester);
  }

  group('a customer who has entered nothing', () {
    testWidgets('is told what cannot be worked out, and shown no figures', (
      tester,
    ) async {
      await pumpReview(
        tester,
        data: review(
          position: unknownPosition,
          score: noScore,
          action: completeProfileAction,
        ),
      );

      expect(
        find.text('Your financial position cannot be worked out yet'),
        findsOneWidget,
      );
      expect(find.text('No FynnScore yet'), findsOneWidget);

      // No ₹0 surplus, no 0-month buffer, no invented goal.
      expect(find.textContaining('₹'), findsNothing);
      expect(find.text('Goals'), findsNothing);
      expect(find.text('What changed'), findsNothing);
      expect(find.text('What you explored'), findsNothing);
    });

    testWidgets('is given the one step that leads somewhere', (tester) async {
      await pumpReview(
        tester,
        data: review(
          position: unknownPosition,
          score: noScore,
          action: completeProfileAction,
        ),
      );

      expect(find.text('Next step'), findsOneWidget);
      expect(find.text('Add your financial details'), findsOneWidget);
    });

    testWidgets('while a complete customer gets the sections they earn', (
      tester,
    ) async {
      await pumpReview(
        tester,
        data: review(
          score: goodScore,
          goals: reviewGoals,
          progress: observedProgress,
        ),
        decisions: const PopulatedDecisions(),
      );

      for (final section in [
        'Financial position',
        'FynnScore',
        'Goals',
        'What changed',
        'What you explored',
        'Next step',
      ]) {
        expect(find.text(section), findsOneWidget, reason: 'missing $section');
      }
    });
  });

  group('a customer spending more than they earn', () {
    testWidgets('is never pointed at borrowing anywhere on the review', (
      tester,
    ) async {
      await pumpReview(
        tester,
        data: review(
          position: shortfallPosition,
          score: stretchedScore,
          goals: reviewGoals,
          action: reviewFiguresAction,
        ),
      );

      // The review is on screen and complete — this is not passing because
      // nothing rendered.
      expect(find.text('Financial position'), findsOneWidget);
      expect(find.text('Emergency fund'), findsOneWidget);
      expect(find.text('Check your recorded figures'), findsOneWidget);

      for (final sale in [
        'Explore your options',
        'borrow',
        'Take a loan',
        'credit card',
        'top-up',
        'apply now',
      ]) {
        expect(
          find.textContaining(sale, findRichText: true),
          findsNothing,
          reason: 'the review offered "$sale" to a customer with a shortfall',
        );
      }
    });

    testWidgets('sees the shortfall stated with its sign', (tester) async {
      await pumpReview(
        tester,
        data: review(
          position: shortfallPosition,
          score: stretchedScore,
          action: reviewFiguresAction,
        ),
      );

      expect(
        find.text(
          'Your recorded monthly outgo is higher than your recorded income.',
        ),
        findsOneWidget,
      );
      // A shortfall printed as ₹18,000 would be the wrong number.
      expect(find.text('-₹18,000'), findsOneWidget);
    });
  });

  group('goals on the review', () {
    testWidgets('are stated as figures, never as a commitment or a forecast', (
      tester,
    ) async {
      await pumpReview(
        tester,
        data: review(score: goodScore, goals: reviewGoals),
      );

      expect(
        find.text('₹1,20,000 saved toward ₹3,00,000'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'At the current target and date, the calculated monthly amount is',
        ),
        findsOneWidget,
      );

      for (final claim in [
        'on track',
        "you'll",
        'you will',
        'Set aside',
        'you need to save',
        'falling behind',
      ]) {
        expect(
          find.textContaining(claim, findRichText: true),
          findsNothing,
          reason: 'the review claimed "$claim" about a goal',
        );
      }
    });

    testWidgets('show a reached goal as reached, with no monthly figure', (
      tester,
    ) async {
      await pumpReview(
        tester,
        data: review(score: goodScore, goals: [reachedGoal]),
      );

      expect(find.text('Goal reached.'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.textContaining('calculated monthly amount'), findsNothing);
    });

    testWidgets('are counted, never ranked', (tester) async {
      await pumpReview(
        tester,
        data: review(score: goodScore, goals: reviewGoals),
      );

      expect(find.text('2 goals, nearest target date first.'), findsOneWidget);

      for (final claim in [
        'most important',
        'your main goal',
        'priority goal',
        'top goal',
      ]) {
        expect(
          find.textContaining(claim, findRichText: true),
          findsNothing,
          reason: 'the review ranked a goal: "$claim"',
        );
      }
    });
  });

  testWidgets('what changed comes from observations and states no cause', (
    tester,
  ) async {
    await pumpReview(
      tester,
      data: review(score: goodScore, progress: observedProgress),
    );

    // The server's sentence, so a figure quoted here and the same figure on
    // the progress screen cannot differ.
    expect(find.text('FynnScore changed from 64 to 71.'), findsOneWidget);

    for (final claim in [
      'because',
      'thanks to',
      'as a result',
      'improved to',
      'recovered',
      'healthier',
    ]) {
      expect(
        find.textContaining(claim, findRichText: true),
        findsNothing,
        reason: 'the review claimed "$claim"',
      );
    }
  });

  testWidgets('what was explored is stated as an act, never as a preference', (
    tester,
  ) async {
    await pumpReview(
      tester,
      data: review(score: goodScore),
      decisions: const PopulatedDecisions(),
    );

    expect(find.text('What you explored'), findsOneWidget);

    for (final inference in [
      'you preferred',
      'you were considering',
      'you wanted',
      'your favourite',
      'best for you',
    ]) {
      expect(
        find.textContaining(inference, findRichText: true),
        findsNothing,
        reason: 'the review inferred "$inference"',
      );
    }
  });

  testWidgets('the next step is the one the server produced', (tester) async {
    await pumpReview(
      tester,
      data: review(score: goodScore, goals: reviewGoals),
    );

    /*
     * One ladder. The review does not rank anything of its own, so this
     * card and Home's primary action cannot suggest different things — they
     * are the same field of the same read.
     */
    expect(find.text(bufferAction.title), findsOneWidget);

    // The buffer rung's reason is the buffer sentence, which the position
    // card above already made. Said twice on one screen it reads as a
    // rendering fault, so it is said once.
    expect(find.text(bufferAction.reason), findsOneWidget);
  });

  testWidgets('a reason the review has not already given is shown', (
    tester,
  ) async {
    await pumpReview(
      tester,
      data: review(
        position: shortfallPosition,
        score: stretchedScore,
        action: reviewFiguresAction,
      ),
    );

    // The counterpart: the suppression above is about a repeat, not about
    // the review swallowing the reason it gives for a step.
    expect(find.text(reviewFiguresAction.title), findsOneWidget);
    expect(find.text(reviewFiguresAction.reason), findsOneWidget);
  });

  testWidgets('nothing on the review promises or schedules anything', (
    tester,
  ) async {
    await pumpReview(
      tester,
      data: review(
        score: goodScore,
        goals: reviewGoals,
        progress: observedProgress,
      ),
      decisions: const PopulatedDecisions(),
    );

    for (final claim in [
      'Next review',
      'review due',
      'Last reviewed',
      'every month',
      'every week',
      'check daily',
      'reminder',
      'health grade',
      'review score',
    ]) {
      expect(
        find.textContaining(claim, findRichText: true),
        findsNothing,
        reason: 'the review claimed "$claim"',
      );
    }

    // What it does say instead: come back when something changes.
    expect(
      find.textContaining('whenever your circumstances change'),
      findsOneWidget,
    );
  });

  testWidgets('a review that cannot be loaded says so and offers a retry', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const ReviewScreen(),
      overrides: [
        intelligenceServiceProvider.overrideWithValue(
          const UnreachableIntelligenceState(),
        ),
        decisionServiceProvider.overrideWithValue(const EmptyDecisions()),
      ],
    );
    await settle(tester);

    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('₹'), findsNothing);
    expect(find.text('Financial position'), findsNothing);
  });

  testWidgets('every figure is announced with what it is', (tester) async {
    final handle = tester.ensureSemantics();

    await pumpReview(
      tester,
      data: review(score: goodScore, progress: observedProgress),
    );

    // A change row reads as a sentence with the direction in words: an
    // arrow is legible on a screen and silent when read aloud.
    expect(
      find.bySemanticsLabel(RegExp('FynnScore increased from 64 to 71')),
      findsOneWidget,
    );

    // And the band is a word beside the number, not a colour.
    expect(find.text('Good'), findsOneWidget);

    handle.dispose();
  });
}
