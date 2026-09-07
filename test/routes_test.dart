import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/routes.dart';
import 'package:go_router/go_router.dart';

import 'support/harness.dart';

/// Guards against dead links: every constant in Routes must resolve to a real
/// screen, not the router's error page. Without this, renaming a GoRoute path
/// leaves a constant pointing nowhere and nothing fails until a customer taps.
void main() {
  setUpAll(initTestEnvironment);

  /// Every location the app can navigate to, including the parameterised
  /// builders exercised with a real seed id.
  const locations = <String>[
    Routes.welcome,
    Routes.login,
    Routes.otp,
    Routes.onboardingProfile,
    Routes.onboardingIntent,
    Routes.onboardingGoal,
    Routes.home,
    Routes.explore,
    Routes.ai,
    Routes.applications,
    Routes.profile,
    Routes.loanDiscovery,
    Routes.loanOptions,
    Routes.compare,
    Routes.fynnLab,
    Routes.emiCalculator,
    Routes.affordability,
    Routes.prepayment,
    Routes.balanceTransfer,
    Routes.emergencyFund,
    Routes.fynnScore,
    Routes.vault,
    Routes.scan,
    Routes.secondOpinion,
    Routes.financialProfile,
    Routes.goals,
    Routes.notifications,
    Routes.credit,
    Routes.privacy,
    Routes.privacyAiMemory,
    Routes.support,
  ];

  final parameterised = <String>[
    Routes.documentKyc('doc_1'),
    Routes.loan('prod_bl_b'),
    Routes.fynnTrust('prod_bl_b'),
    Routes.mirrorFor('prod_bl_a'),
    Routes.application('app_1'),
  ];

  for (final location in [...locations, ...parameterised]) {
    testWidgets('$location resolves to a screen', (tester) async {
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go(location);

      // Fixed pumps: loading skeletons animate forever, so pumpAndSettle
      // would never return while a repository is resolving.
      await tester.pump();
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      expect(
        find.textContaining('No screen at'),
        findsNothing,
        reason: '$location fell through to the router error page',
      );
    });
  }
}
