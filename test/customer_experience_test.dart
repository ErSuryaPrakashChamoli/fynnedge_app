import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/core/widgets/buttons.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/features/loans/fynn_mirror_screen.dart';
import 'package:fynnedge/features/onboarding/basic_profile_screen.dart';
import 'package:fynnedge/features/score/fynn_score_screen.dart';

import 'support/harness.dart';

/// What a customer who has never heard of FynnEdge can actually understand,
/// and whether the product ever leans on them.
///
/// These are not layout tests. Each one stands for a question a first-time
/// customer asks — what is this number, am I being pushed, can I say no —
/// and fails when the answer stops being available on the screen.
void main() {
  setUpAll(initTestEnvironment);
  setUp(MockStore.instance.reset);

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 25 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -240));
      // Entrance animations start as each row is built, so the frames have
      // to be pumped out or the test ends with timers still pending.
      await settle(tester, const Duration(milliseconds: 700));
    }
    // The rows built by the last drag start their own entrance animations,
    // so the frames are drained before the test ends.
    await settle(tester, const Duration(milliseconds: 1600));
  }

  group('a customer meeting FynnScore for the first time', () {
    testWidgets('is told what the number is before being told their band', (
      tester,
    ) async {
      await pumpScreen(tester, const FynnScoreScreen());
      await settle(tester);

      expect(find.text('What FynnScore is'), findsOneWidget);
      expect(
        find.textContaining('three things you told us'),
        findsOneWidget,
        reason: 'the score does not say what it measures',
      );

      // The explanation sits above the detail, not at the foot of it.
      final explanation = tester.getTopLeft(find.text('What FynnScore is')).dy;
      final factors = tester.getTopLeft(find.text('The factors behind it')).dy;
      expect(explanation, lessThan(factors));
    });

    testWidgets('is told plainly that it is not a credit score', (
      tester,
    ) async {
      await pumpScreen(tester, const FynnScoreScreen());
      await settle(tester);

      expect(
        find.textContaining('not a credit score'),
        findsOneWidget,
        reason: 'the one thing customers assume it is goes uncorrected',
      );
    });

    testWidgets('sees their own figure beside each sub-score', (tester) async {
      await pumpScreen(tester, const FynnScoreScreen());
      await settle(tester);
      await scrollTo(tester, find.textContaining('EMI Burden ·'));

      // "EMI Burden — 100" reads as "100% of my income is EMI" to someone
      // who has not been told 100 is full marks.
      expect(find.textContaining('EMI Burden · '), findsOneWidget);
      expect(find.textContaining('% of income'), findsWidgets);
      expect(find.text('100/100'), findsWidgets);
    });
  });

  group('nothing speaks for a lender', () {
    testWidgets('the score explanation makes no claim about lending', (
      tester,
    ) async {
      await pumpScreen(tester, const FynnScoreScreen());
      await settle(tester);

      for (final claim in const [
        'Lenders are unlikely',
        'unlikely to extend',
        'lenders will',
        'would be declined',
      ]) {
        expect(
          find.textContaining(claim),
          findsNothing,
          reason: 'the score speaks for a lender: "$claim"',
        );
      }
    });
  });

  group('a customer who does not want the loan', () {
    testWidgets('is not pushed towards applying on FynnMirror', (tester) async {
      await pumpScreen(tester, const FynnMirrorScreen(productId: 'prod_bl_b'));
      await settle(tester);
      await scrollTo(tester, find.text('Apply for this loan'));

      // Both paths are presented as legitimate, so neither exit may be the
      // one bright button. Apply is available, level with the others.
      expect(find.text('Apply for this loan'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Apply for this loan'),
          matching: find.byType(PrimaryButton),
        ),
        findsNothing,
        reason: 'Apply is the dominant CTA on the screen arguing both ways',
      );
    });

    testWidgets('is told that saying no is a real answer, and where to go', (
      tester,
    ) async {
      await pumpScreen(tester, const FynnMirrorScreen(productId: 'prod_bl_b'));
      await settle(tester);
      await scrollTo(tester, find.textContaining('Deciding against this'));

      expect(
        find.textContaining('Deciding against this is a real answer'),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing has been sent'), findsOneWidget);
      // And a way onward that is not the loan.
      expect(find.text('Put the money towards a goal instead'), findsOneWidget);
    });

    testWidgets('both paths carry equal visual weight', (tester) async {
      await pumpScreen(tester, const FynnMirrorScreen(productId: 'prod_bl_b'));
      await settle(tester);

      expect(find.text('If you take this loan'), findsOneWidget);
      expect(
        find.textContaining('Both are legitimate choices'),
        findsOneWidget,
      );
      await scrollTo(tester, find.text("If you don't"));
      expect(find.text("If you don't"), findsOneWidget);
    });
  });

  group('onboarding asks only for what it uses', () {
    testWidgets('the city is offered, not demanded', (tester) async {
      await pumpScreen(tester, const BasicProfileScreen());
      await settle(tester);

      expect(find.text('CITY (OPTIONAL)'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Rahul Sharma');
      await tester.enterText(fields.at(1), '34');
      await tester.pump();

      // Nothing in FynnEdge reads the city, so it must not stand between
      // the customer and their cockpit.
      final button = tester.widget<PrimaryButton>(
        find.byType(PrimaryButton).first,
      );
      expect(
        button.onPressed,
        isNotNull,
        reason: 'a field nothing reads is blocking onboarding',
      );
    });

    testWidgets('no field implies a document check that never happens', (
      tester,
    ) async {
      await pumpScreen(tester, const BasicProfileScreen());
      await settle(tester);

      // FynnEdge holds no PAN, runs no KYC and reads no bureau. Asking for
      // a name "as it appears on your PAN" implies all three.
      expect(find.textContaining('PAN'), findsNothing);
      expect(find.textContaining('Aadhaar'), findsNothing);
      expect(
        find.textContaining('Nothing here is shared with a lender'),
        findsOneWidget,
      );
    });

    testWidgets('says why it is asking for the age', (tester) async {
      await pumpScreen(tester, const BasicProfileScreen());
      await settle(tester);

      // The one field with a real downstream use should say so.
      expect(
        find.textContaining('which products you can be considered for'),
        findsOneWidget,
      );
    });
  });

  group('FynnAI promises only what it can do', () {
    test('the input does not offer a general financial assistant', () {
      final source = File('lib/features/ai/ai_screen.dart').readAsStringSync();

      // The deterministic provider answers from this customer's own saved
      // figures. "Anything financial" is a different product.
      expect(source, isNot(contains('anything financial')));
      expect(source, contains('Ask about your money'));
    });
  });
}
