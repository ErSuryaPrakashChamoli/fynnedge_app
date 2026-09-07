import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/features/ai/ai_screen.dart';
import 'package:fynnedge/features/applications/application_detail_screen.dart';
import 'package:fynnedge/features/fynnlab/fynnlab_screen.dart';
import 'package:fynnedge/features/loans/compare_screen.dart';
import 'package:fynnedge/features/loans/fynn_mirror_screen.dart';
import 'package:fynnedge/features/loans/fynn_trust_screen.dart';
import 'package:fynnedge/features/loans/loan_detail_screen.dart';
import 'package:fynnedge/features/loans/loan_discovery_screen.dart';
import 'package:fynnedge/features/profile/financial_profile_screen.dart';
import 'package:fynnedge/features/profile/goals_screen.dart';
import 'package:fynnedge/features/profile/notifications_screen.dart';
import 'package:fynnedge/features/credit/credit_screen.dart';
import 'package:fynnedge/features/profile/privacy_screen.dart';
import 'package:fynnedge/features/profile/support_screen.dart';
import 'package:fynnedge/features/vault/scan_screen.dart';
import 'package:fynnedge/features/vault/second_opinion_screen.dart';
import 'package:fynnedge/features/vault/vault_screen.dart';

import 'package:fynnedge/features/applications/applications_screen.dart';
import 'package:fynnedge/features/auth/login_screen.dart';
import 'package:fynnedge/features/auth/otp_screen.dart';
import 'package:fynnedge/features/explore/explore_screen.dart';
import 'package:fynnedge/features/fynnlab/emi_calculator_screen.dart';
import 'package:fynnedge/features/home/home_screen.dart';
import 'package:fynnedge/features/loans/loan_options_screen.dart';
import 'package:fynnedge/features/onboarding/basic_profile_screen.dart';
import 'package:fynnedge/features/onboarding/goal_screen.dart';
import 'package:fynnedge/features/onboarding/intent_screen.dart';
import 'package:fynnedge/features/profile/profile_screen.dart';
import 'package:fynnedge/features/score/fynn_score_screen.dart';
import 'package:fynnedge/features/splash/splash_screen.dart';
import 'package:fynnedge/features/welcome/welcome_screen.dart';

import 'package:go_router/go_router.dart';

import 'support/harness.dart';

/// Walks the real router through the customer journey. This is the guard
/// against "25 screens with broken navigation".
void main() {
  setUpAll(initTestEnvironment);

  Future<void> advance(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  _fullJourney();

  testWidgets('signs up and reaches Home through every onboarding step', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byType(SplashScreen), findsOneWidget);

    // Splash hands off on its own timer.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField), '9876543210');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await advance(tester);
    expect(find.byType(OtpScreen), findsOneWidget);

    // The mock OTP service accepts any six digits except 000000.
    await tester.enterText(find.byType(TextField), '123456');
    await advance(tester);
    expect(find.byType(BasicProfileScreen), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Rahul Sharma');
    await tester.enterText(fields.at(1), '34');
    await tester.enterText(fields.at(2), 'Pune');
    await tester.pump();
    await tester.tap(find.text('Save and continue'));
    await advance(tester);
    expect(find.byType(IntentScreen), findsOneWidget);

    await tester.tap(find.text('I need a loan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await advance(tester);
    expect(find.byType(GoalScreen), findsOneWidget);

    await tester.tap(find.text('Business'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await advance(tester);
    expect(find.byType(HomeScreen), findsOneWidget);

    // The name typed during onboarding should drive the greeting.
    expect(find.text('Rahul'), findsOneWidget);
  });

  testWidgets('bottom navigation reaches all five destinations', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // Skip onboarding by driving the router straight to the shell.
    final context = tester.element(find.byType(WelcomeScreen));
    await _go(tester, context, '/home');
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.tap(find.text('Explore').last);
    await tester.pumpAndSettle();
    expect(find.byType(ExploreScreen), findsOneWidget);

    await tester.tap(find.text('FynnAI').last);
    await tester.pumpAndSettle();
    expect(find.byType(AiScreen), findsOneWidget);

    await tester.tap(find.text('Activity').last);
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationsScreen), findsOneWidget);

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('Home quick actions push their destination screens', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(WelcomeScreen));
    await _go(tester, context, '/home');

    // FynnScore hero.
    await tester.tap(find.text('See the breakdown'));
    await tester.pumpAndSettle();
    expect(find.byType(FynnScoreScreen), findsOneWidget);
    await _back(tester);
    expect(find.byType(HomeScreen), findsOneWidget);

    // Quick action into the EMI calculator, at the foot of the screen.
    await tester.scrollUntilVisible(
      find.text('EMI calculator'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('EMI calculator'));
    await tester.pumpAndSettle();
    expect(find.byType(EmiCalculatorScreen), findsOneWidget);
    await _back(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('loan journey runs from discovery to compare', (tester) async {
    await pumpApp(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(WelcomeScreen));
    await _go(tester, context, '/loan-options');
    expect(find.byType(LoanOptionsScreen), findsOneWidget);

    // Two offers must be selectable for comparison.
    expect(find.text('Compare'), findsNWidgets(2));
    await tester.tap(find.text('Compare').first);
    await tester.pumpAndSettle();
    expect(find.text('Added'), findsOneWidget);
  });
}

Future<void> _go(
  WidgetTester tester,
  BuildContext context,
  String location,
) async {
  // ignore: use_build_context_synchronously
  GoRouterHelper(context).go(location);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  navigator.pop();
  await tester.pumpAndSettle();
}

/// Walks the complete journey named in the brief, screen by screen, driving
/// the real router. Each hop asserts the destination actually rendered.
void _fullJourney() {
  testWidgets('walks the entire 25-screen customer journey', (tester) async {
    await pumpApp(tester);

    // 1 Splash -> 2 Welcome (its own timer)
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget, reason: 'Welcome');

    // 3 Login
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget, reason: 'Login');

    // 4 OTP
    await tester.enterText(find.byType(TextField), '9876543210');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _advance(tester);
    expect(find.byType(OtpScreen), findsOneWidget, reason: 'OTP');

    // 5 Basic profile
    await tester.enterText(find.byType(TextField), '123456');
    await _advance(tester);
    expect(find.byType(BasicProfileScreen), findsOneWidget, reason: 'Profile');

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Rahul Sharma');
    await tester.enterText(fields.at(1), '34');
    await tester.enterText(fields.at(2), 'Pune');
    await tester.pump();
    await tester.tap(find.text('Save and continue'));
    await _advance(tester);

    // 6 Financial intent
    expect(find.byType(IntentScreen), findsOneWidget, reason: 'Intent');
    await tester.tap(find.text('I need a loan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await _advance(tester);

    // 7 Goal
    expect(find.byType(GoalScreen), findsOneWidget, reason: 'Goal');
    await tester.tap(find.text('Business'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await _advance(tester);

    // 8 Home
    expect(find.byType(HomeScreen), findsOneWidget, reason: 'Home');

    // 9 Explore, via the bottom navigation.
    await tester.tap(find.text('Explore').last);
    await tester.pumpAndSettle();
    expect(find.byType(ExploreScreen), findsOneWidget, reason: 'Explore');

    // Hold the router itself: a captured BuildContext is deactivated the
    // moment its screen leaves the tree.
    final router = GoRouter.of(tester.element(find.byType(ExploreScreen)));

    // 10..25 — every remaining destination, each verified on arrival.
    final hops = <(String, Type)>[
      ('/loan-discovery', LoanDiscoveryScreen),
      ('/loan-options', LoanOptionsScreen),
      ('/loan/prod_bl_b', LoanDetailScreen),
      ('/compare', CompareScreen),
      ('/fynn-trust/prod_bl_b', FynnTrustScreen),
      ('/fynn-mirror/prod_bl_a', FynnMirrorScreen),
      ('/fynnlab', FynnLabScreen),
      ('/fynnlab/emi', EmiCalculatorScreen),
      ('/fynn-score', FynnScoreScreen),
      ('/ai', AiScreen),
      ('/applications', ApplicationsScreen),
      ('/applications/app_1', ApplicationDetailScreen),
      ('/vault', VaultScreen),
      ('/scan', ScanScreen),
      ('/second-opinion', SecondOpinionScreen),
      ('/profile', ProfileScreen),
      ('/financial-profile', FinancialProfileScreen),
      ('/goals', GoalsScreen),
      ('/notifications', NotificationsScreen),
      ('/credit', CreditScreen),
      ('/privacy', PrivacyScreen),
      ('/support', SupportScreen),
    ];

    for (final (route, type) in hops) {
      router.go(route);
      // Fixed pumps, not pumpAndSettle: loading skeletons shimmer on a loop,
      // so "settled" never arrives while a repository is resolving.
      await _pumpFor(tester, const Duration(milliseconds: 1600));
      expect(find.byType(type), findsOneWidget, reason: route);
    }
  });
}

Future<void> _advance(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

/// Advances frame by frame without waiting for quiescence.
Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const frame = Duration(milliseconds: 32);
  await tester.pump();
  for (var i = 0; i < total.inMilliseconds ~/ frame.inMilliseconds; i++) {
    await tester.pump(frame);
  }
}
