import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/models/intelligence.dart';
import 'package:fynnedge/data/services/intelligence_service.dart';
import 'package:fynnedge/features/intelligence/financial_timeline_screen.dart';

import 'support/harness.dart';
import 'support/intelligence_fixtures.dart';
import 'support/plan_fixtures.dart';
import 'support/screen_catalog.dart';

/// Module 35 — what FynnEdge has actually observed changing.
///
/// The screen renders what the server observed and nothing else. It draws no
/// chart, derives no direction and compares nothing itself, so most of what
/// is worth testing here is what it refuses to show and what it says instead.
///
/// Every guard is checked from both sides: the state that must suppress
/// something, and the state that must show it. A test that only ever asserts
/// an absence passes just as well when the thing it guards was unreachable.
void main() {
  setUpAll(initTestEnvironment);

  Future<void> pumpStory(
    WidgetTester tester, {
    required IntelligenceService intelligence,
    Size size = kNormalPhone,
    bool settleFirst = true,
  }) async {
    await pumpScreen(
      tester,
      const FinancialTimelineScreen(),
      overrides: [
        intelligenceServiceProvider.overrideWithValue(intelligence),
      ],
      size: size,
    );
    if (settleFirst) await settle(tester);
  }

  group('a customer FynnEdge has not observed twice', () {
    testWidgets('is told there is nothing to compare, not that nothing moved', (
      tester,
    ) async {
      await pumpStory(
        tester,
        intelligence: const PlanIntelligence(
          FinancialIntelligence(observations: 1),
        ),
      );

      // Two different facts, and the customer gets the true one. "Nothing
      // has changed" would be a claim about their money; this is a claim
      // about what FynnEdge has looked at.
      expect(find.text('Nothing to compare yet'), findsOneWidget);
      expect(find.text('No changes recorded'), findsNothing);
    });

    testWidgets('sees no figures at all', (tester) async {
      await pumpStory(
        tester,
        intelligence: const PlanIntelligence(
          FinancialIntelligence(observations: 1),
        ),
      );

      // No chart drawn through one point, and no baseline invented to draw
      // it from.
      expect(find.textContaining('→'), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets(
      'while a customer observed twice with nothing moving is told that',
      (tester) async {
        await pumpStory(
          tester,
          intelligence: const PlanIntelligence(
            FinancialIntelligence(observations: 4, hasComparableHistory: true),
          ),
        );

        expect(find.text('No changes recorded'), findsOneWidget);
        expect(find.text('Nothing to compare yet'), findsNothing);
      },
    );
  });

  group('an observed change', () {
    testWidgets('shows both figures, in the server\'s words', (tester) async {
      await pumpStory(
        tester,
        intelligence: PlanIntelligence(
          FinancialIntelligence(
            observations: 3,
            hasComparableHistory: true,
            progress: observedProgress,
          ),
        ),
        size: const Size(390, 1600),
      );

      expect(find.text('FynnScore'), findsOneWidget);
      expect(find.text('64'), findsOneWidget);
      expect(find.text('71'), findsOneWidget);

      expect(find.text('Recorded monthly surplus'), findsOneWidget);
      expect(find.text('₹28,000'), findsOneWidget);
      expect(find.text('₹40,000'), findsOneWidget);
    });

    testWidgets('keeps a negative figure negative', (tester) async {
      await pumpStory(
        tester,
        intelligence: PlanIntelligence(
          FinancialIntelligence(
            observations: 3,
            hasComparableHistory: true,
            progress: recoveredProgress,
          ),
        ),
        size: const Size(390, 1600),
      );

      // A shortfall printed as ₹8,000 is not a formatting nicety, it is the
      // wrong number.
      expect(find.text('-₹8,000'), findsOneWidget);
      expect(find.text('₹8,000'), findsNothing);
      expect(find.text('₹12,000'), findsOneWidget);
    });

    testWidgets('explains a score from what was true at the time', (
      tester,
    ) async {
      await pumpStory(
        tester,
        intelligence: PlanIntelligence(
          FinancialIntelligence(
            observations: 3,
            hasComparableHistory: true,
            progress: observedProgress,
          ),
        ),
        size: const Size(390, 1600),
      );

      expect(find.text('When each score was worked out:'), findsOneWidget);
      expect(
        find.textContaining('Emergency Buffer: 2.1 → 3 (35 → 50 points)'),
        findsOneWidget,
      );
    });

    testWidgets('never interprets, predicts or attributes a cause', (
      tester,
    ) async {
      await pumpStory(
        tester,
        intelligence: PlanIntelligence(
          FinancialIntelligence(
            observations: 3,
            hasComparableHistory: true,
            progress: [...observedProgress, ...recoveredProgress],
          ),
        ),
        size: const Size(390, 2400),
      );

      for (final claim in [
        'because',
        'thanks to',
        'as a result',
        'improving',
        'recovered',
        'healthier',
        'stronger',
        'worsening',
        'on track',
        'falling behind',
        'doing great',
        'keep it up',
        'expected',
        'predicted',
        'will reach',
      ]) {
        expect(
          find.textContaining(claim, findRichText: true),
          findsNothing,
          reason: 'the progress screen claimed "$claim"',
        );
      }
    });
  });

  testWidgets('the direction is a word for anyone who cannot see the arrow', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await pumpStory(
      tester,
      intelligence: PlanIntelligence(
        FinancialIntelligence(
          observations: 3,
          hasComparableHistory: true,
          progress: observedProgress,
        ),
      ),
      size: const Size(390, 1600),
    );

    // An arrow between two numbers is legible on a screen and silent when
    // read aloud, so the row announces itself as a sentence.
    expect(
      find.bySemanticsLabel(RegExp('FynnScore increased from 64 to 71')),
      findsOneWidget,
    );

    handle.dispose();
  });

  group('progress that cannot be read', () {
    testWidgets('says so and offers a retry, showing no figures', (
      tester,
    ) async {
      await pumpStory(
        tester,
        intelligence: const ProgressUnavailable(),
        size: const Size(390, 1800),
      );

      // One retry, on the half that failed. The story below came from its
      // own request and is unaffected.
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('→'), findsNothing);
      expect(find.text('No changes recorded'), findsNothing);
      expect(find.text('Nothing to compare yet'), findsNothing);
    });

    testWidgets('still shows the story beneath it', (tester) async {
      await pumpStory(
        tester,
        intelligence: const ProgressUnavailable(),
        size: const Size(390, 1800),
      );

      // The timeline comes from its own request. Progress being unreadable
      // is not the story being unreadable.
      expect(find.text('What happened'), findsOneWidget);
      expect(find.text('Your FynnScore improved'), findsOneWidget);
    });

    testWidgets('shows nothing at all while it is still loading', (
      tester,
    ) async {
      await pumpStory(
        tester,
        intelligence: const PendingIntelligence(),
        settleFirst: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('→'), findsNothing);
      expect(find.text('No changes recorded'), findsNothing);
      expect(find.text('Nothing to compare yet'), findsNothing);
    });
  });

  testWidgets('the two halves of the screen agree about the customer', (
    tester,
  ) async {
    await pumpStory(
      tester,
      intelligence: const PopulatedIntelligence(),
      size: const Size(390, 2400),
    );

    /*
     * The timeline says the score went from 64 to 71, so the change above it
     * says the same thing about the same customer. This caught a fixture
     * where the story described a score improvement while the progress
     * section said the figures had not moved — a picture of a screen
     * contradicting itself.
     */
    expect(find.text('Your FynnScore improved'), findsOneWidget);
    expect(find.text('It went from 64 to 71.'), findsOneWidget);
    expect(find.text('FynnScore'), findsOneWidget);
    expect(find.text('64'), findsOneWidget);
    expect(find.text('71'), findsOneWidget);
  });
}
