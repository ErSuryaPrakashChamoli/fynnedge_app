import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/features/auth/login_screen.dart';
import 'package:fynnedge/features/auth/otp_screen.dart';
import 'package:fynnedge/features/onboarding/basic_profile_screen.dart';
import 'package:fynnedge/features/profile/financial_profile_screen.dart';

import 'support/harness.dart';

/// Every screen that takes text input must survive the keyboard being up.
/// A raised keyboard is simulated with viewInsets, exactly as the framework
/// reports it. An overflow fails the test on its own.
void main() {
  setUpAll(initTestEnvironment);

  const keyboard = EdgeInsets.only(bottom: 336);

  final screens = <String, Widget Function()>{
    'login': () => const LoginScreen(),
    'otp': () => const OtpScreen(devHint: '123456'),
    'basic profile': () => const BasicProfileScreen(),
    'financial profile': () => const FinancialProfileScreen(),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key} survives a raised keyboard on a small phone', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        entry.value(),
        size: kSmallPhone,
        viewInsets: keyboard,
      );
      await settle(tester);
    });

    testWidgets('${entry.key} survives a raised keyboard on a normal phone', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        entry.value(),
        size: kNormalPhone,
        viewInsets: keyboard,
      );
      await settle(tester);
    });
  }

  testWidgets('the primary action is reachable with the keyboard up', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const LoginScreen(),
      size: kSmallPhone,
      viewInsets: keyboard,
    );
    await settle(tester);

    // With only ~300px of viewport the CTA may sit below the fold — that is
    // fine, provided the screen scrolls to it rather than clipping it.
    // ensureVisible walks to the CTA's own Scrollable ancestor; a bare
    // Scrollable finder would also match the TextField's internal one.
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();

    final button = tester.getRect(find.text('Continue'));
    final usableBottom = kSmallPhone.height - keyboard.bottom;
    expect(
      button.bottom,
      lessThanOrEqualTo(usableBottom + 1),
      reason: 'Continue could not be brought above the keyboard',
    );
  });
}
