import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fynnedge/core/utils/clock.dart';

import 'support/harness.dart';
import 'support/screen_catalog.dart';

/// Renders every screen at the three phone widths FynnEdge targets.
///
/// There is no explicit assertion because none is needed: a RenderFlex
/// overflow, a paint assertion or a failed provider read is reported to the
/// test framework and fails the test on its own. Small phones are where
/// layouts break, and 420x900 goldens never catch it.
void main() {
  /*
   * Frozen here rather than in setUpAll, and the difference is a day.
   *
   * The groups below call screenCatalog() while the file is being declared,
   * which happens before any setUpAll runs — so a fixture that read
   * AppClock.now() to build a goal's target date read the wall clock, and
   * every golden containing a date drifted the next morning. Freezing is
   * synchronous, so it can happen here; loading fonts is not, so that stays
   * where it is.
   */
  AppClock.freeze(kTestNow);

  setUpAll(initTestEnvironment);

  final sizes = {
    'small 360x640': kSmallPhone,
    'normal 390x844': kNormalPhone,
    'large 430x932': kLargePhone,
  };

  // The dense screens also get a small-phone golden, because 360px is where
  // crowding shows up long before anything actually overflows.
  const dense = {
    '08_home',
    '11_loan_options',
    '13_compare',
    '15_fynn_mirror',
    '16a_emi',
    '19_applications',
    '20_application_detail',
    '25_financial_profile',

    // A plan of three, each with a reason that wraps.
    '08a_home_planned',

    // Long copy in a bordered tile with an icon column beside it. 360 is
    // where that crowds long before it overflows.
    '27a_notifications_populated',

    // The plan: a position card, a next step and goal cards with wrapping
    // reasons, one under another. 360 is where that crowds.
    '26b_plan_one_goal',
    '26c_plan_shortfall',
    '26e_plan_strained',

    // A status banner, a context card and a timeline, one under another.
    '29a_support_populated',
    '29d_support_case_waiting',

    // A timeline spine beside wrapping copy, and change rows carrying two
    // figures and an arrow: 360 is where both crowd.
    '30_financial_story',
    '30d_progress_recovered',

    // The review stacks five sections of wrapping copy and figures. 360 is
    // where that crowds long before anything overflows.
    '32c_review_dense',
    '32d_review_large',

    // Label and value on one row, with a provenance line under each.
    '31_decisions',
    '31b_decision_simulation',
  };

  /*
   * 420px, for the copy-heavy screens.
   *
   * The rest are covered at 360, 390 and 430, which brackets the range.
   * These earn a fourth because they carry the longest copy in the product
   * — the unconfirmed-submission message runs to four lines, and the plan's
   * position and buffer sentences each wrap — and a width in the middle is
   * where a wrap lands awkwardly rather than overflowing outright.
   */
  group('the plan, notifications and support at 420x900', () {
    for (final screen in screenCatalog().where(
      (s) =>
          s.name.startsWith('26') ||
          s.name.startsWith('27') ||
          s.name.startsWith('29') ||
          // Every 30* case: the story, the progress states above it and
          // the Twin screens. Change rows carry two figures, an arrow and a
          // component line, and a middle width is where those wrap badly.
          s.name.startsWith('30') ||
          s.name.startsWith('31') ||
          s.name.startsWith('32'),
    )) {
      testWidgets(screen.name.replaceAll('_', ' '), (tester) async {
        await screen.setUp?.call();
        await pumpScreen(
          tester,
          screen.build(),
          overrides: screen.overrides,
          size: const Size(420, 900),
        );
        await settle(tester);
        await golden(tester, screen.type, 'w420/${screen.name}');
      });
    }
  });

  group('small-phone goldens', () {
    for (final screen in screenCatalog().where((s) => dense.contains(s.name))) {
      testWidgets(screen.name.replaceAll('_', ' '), (tester) async {
        await screen.setUp?.call();
        await pumpScreen(
          tester,
          screen.build(),
          overrides: screen.overrides,
          size: kSmallPhone,
        );
        await settle(tester);
        await golden(tester, screen.type, 'small/${screen.name}');
      });
    }
  });

  for (final entry in sizes.entries) {
    group(entry.key, () {
      for (final screen in screenCatalog()) {
        testWidgets(screen.name.replaceAll('_', ' '), (tester) async {
          await screen.setUp?.call();
          await pumpScreen(
            tester,
            screen.build(),
            overrides: screen.overrides,
            size: entry.value,
          );
          await settle(tester);
        });
      }
    });
  }
}
