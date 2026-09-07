import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/screen_catalog.dart';

/// Renders every screen at the three phone widths FynnEdge targets.
///
/// There is no explicit assertion because none is needed: a RenderFlex
/// overflow, a paint assertion or a failed provider read is reported to the
/// test framework and fails the test on its own. Small phones are where
/// layouts break, and 420x900 goldens never catch it.
void main() {
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
  };

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
