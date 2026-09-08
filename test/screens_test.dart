import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/features/ai/ai_screen.dart';
import 'package:fynnedge/features/applications/application_detail_screen.dart';
import 'package:fynnedge/features/applications/applications_screen.dart';
import 'package:fynnedge/features/auth/login_screen.dart';
import 'package:fynnedge/features/credit/credit_screen.dart';
import 'package:fynnedge/features/auth/otp_screen.dart';
import 'package:fynnedge/features/explore/explore_screen.dart';
import 'package:fynnedge/features/fynnlab/emi_calculator_screen.dart';
import 'package:fynnedge/features/fynnlab/fynnlab_screen.dart';
import 'package:fynnedge/features/fynnlab/other_calculators.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/features/home/home_screen.dart';
import 'package:fynnedge/features/loans/compare_screen.dart';
import 'package:fynnedge/features/loans/fynn_mirror_screen.dart';
import 'package:fynnedge/features/loans/fynn_trust_screen.dart';
import 'package:fynnedge/features/loans/loan_detail_screen.dart';
import 'package:fynnedge/features/loans/loan_discovery_screen.dart';
import 'package:fynnedge/features/loans/loan_options_screen.dart';
import 'package:fynnedge/features/onboarding/basic_profile_screen.dart';
import 'package:fynnedge/features/onboarding/goal_screen.dart';
import 'package:fynnedge/features/onboarding/intent_screen.dart';
import 'package:fynnedge/features/profile/financial_profile_screen.dart';
import 'package:fynnedge/features/profile/goals_screen.dart';
import 'package:fynnedge/features/profile/notifications_screen.dart';
import 'package:fynnedge/features/profile/privacy_screen.dart';
import 'package:fynnedge/features/profile/profile_screen.dart';
import 'package:fynnedge/features/support/support_screen.dart';
import 'package:fynnedge/features/score/fynn_score_screen.dart';
import 'package:fynnedge/features/splash/splash_screen.dart';
import 'package:fynnedge/features/vault/scan_screen.dart';
import 'package:fynnedge/features/vault/second_opinion_screen.dart';
import 'package:fynnedge/features/vault/vault_screen.dart';
import 'package:fynnedge/features/welcome/welcome_screen.dart';

import 'package:fynnedge/app/session.dart';

import 'package:fynnedge/app/providers.dart';

import 'package:fynnedge/core/utils/clock.dart';

import 'support/harness.dart';
import 'support/screen_catalog.dart';

/// Two offers already ticked, so the comparison table renders.
class _PresetCompare extends CompareNotifier {
  @override
  List<String> build() => const ['prod_bl_b', 'prod_bl_a'];
}

/// Renders every screen at phone size, checks it builds without throwing, and
/// writes a golden PNG to test/goldens. Refresh with:
///   flutter test test/screens_test.dart --update-goldens
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

  testWidgets('01 splash routes on to Welcome', (tester) async {
    await pumpApp(tester);
    await settle(tester, const Duration(milliseconds: 1500));
    await golden(tester, SplashScreen, '01_splash');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  screenTest('02_welcome', () => const WelcomeScreen(), WelcomeScreen);
  screenTest('03_login', () => const LoginScreen(), LoginScreen);
  screenTest('04_otp', () => const OtpScreen(devHint: '123456'), OtpScreen);
  screenTest(
    '05_basic_profile',
    () => const BasicProfileScreen(),
    BasicProfileScreen,
  );
  screenTest('06_intent', () => const IntentScreen(), IntentScreen);
  screenTest('07_goal', () => const GoalScreen(), GoalScreen);
  screenTest('08_home', () => const HomeScreen(), HomeScreen);
  screenTest('09_explore', () => const ExploreScreen(), ExploreScreen);
  screenTest(
    '10_loan_discovery',
    () => const LoanDiscoveryScreen(),
    LoanDiscoveryScreen,
  );
  screenTest(
    '11_loan_options',
    () => const LoanOptionsScreen(),
    LoanOptionsScreen,
  );
  screenTest(
    '12_loan_detail',
    () => const LoanDetailScreen(productId: 'prod_bl_b'),
    LoanDetailScreen,
  );
  // Both states matter: nothing picked yet, and a populated table.
  screenTest('13_compare_empty', () => const CompareScreen(), CompareScreen);

  testWidgets('13 compare with two offers selected', (tester) async {
    await pumpScreen(
      tester,
      const CompareScreen(),
      overrides: [compareProvider.overrideWith(_PresetCompare.new)],
    );
    await settle(tester);
    await golden(tester, CompareScreen, '13_compare');
  });
  screenTest(
    '14_fynn_trust',
    () => const FynnTrustScreen(productId: 'prod_bl_b'),
    FynnTrustScreen,
  );
  screenTest(
    '15_fynn_mirror',
    () => const FynnMirrorScreen(productId: 'prod_bl_a'),
    FynnMirrorScreen,
  );
  screenTest('16_fynnlab', () => const FynnLabScreen(), FynnLabScreen);
  screenTest('16a_emi', () => const EmiCalculatorScreen(), EmiCalculatorScreen);
  screenTest(
    '16b_affordability',
    () => const AffordabilityScreen(),
    AffordabilityScreen,
  );
  screenTest(
    '16c_prepayment',
    () => const PrepaymentScreen(),
    PrepaymentScreen,
  );
  screenTest(
    '16d_balance_transfer',
    () => const BalanceTransferScreen(),
    BalanceTransferScreen,
  );
  screenTest(
    '16e_emergency_fund',
    () => const EmergencyFundScreen(),
    EmergencyFundScreen,
  );
  screenTest('17_fynn_score', () => const FynnScoreScreen(), FynnScoreScreen);
  screenTest('18_fynn_ai', () => const AiScreen(), AiScreen);
  // Applications only exist once the customer has started one, so these two
  // create a real one through the mock service first — the same path the app
  // takes.
  screenTest(
    '19_applications',
    () => const ApplicationsScreen(),
    ApplicationsScreen,
    setUp: seedApplication,
  );
  screenTest(
    '20_application_detail',
    () => const ApplicationDetailScreen(id: 'app_1'),
    ApplicationDetailScreen,
    setUp: () => seedApplication(submit: true),
  );
  screenTest('21_vault', () => const VaultScreen(), VaultScreen);
  screenTest('22_scan', () => const ScanScreen(), ScanScreen);
  screenTest(
    '23_second_opinion',
    () => const SecondOpinionScreen(),
    SecondOpinionScreen,
  );
  screenTest('24_profile', () => const ProfileScreen(), ProfileScreen);
  screenTest(
    '25_financial_profile',
    () => const FinancialProfileScreen(),
    FinancialProfileScreen,
  );
  screenTest('26_goals', () => const GoalsScreen(), GoalsScreen);

  // The financial plan in each state a customer can be in: no goals, one,
  // a reached one, a strained one, no income at all, and a position that
  // could not be read.
  for (final screen in screenCatalog().where(
    (s) => s.name.startsWith('26') && s.name != '26_goals',
  )) {
    screenTest(
      screen.name,
      screen.build,
      screen.type,
      overrides: screen.overrides,
    );
  }
  screenTest(
    '27_notifications',
    () => const NotificationsScreen(),
    NotificationsScreen,
  );

  // The states that only exist once something has happened: a centre with
  // unread and read messages grouped, and one that could not be reached.
  screenTest(
    '27a_notifications_populated',
    () => const NotificationsScreen(),
    NotificationsScreen,
    overrides: [
      notificationServiceProvider.overrideWithValue(
        const PopulatedNotifications(),
      ),
    ],
  );
  screenTest(
    '27b_notifications_error',
    () => const NotificationsScreen(),
    NotificationsScreen,
    overrides: [
      notificationServiceProvider.overrideWithValue(
        const UnreachableNotifications(),
      ),
    ],
  );
  screenTest('28_privacy', () => const PrivacyScreen(), PrivacyScreen);

  // Mock mode has no bureau connected, so this golden is the state a
  // customer actually sees today: no score, and a plain explanation of why.
  screenTest('28a_credit', () => const CreditScreen(), CreditScreen);
  /*
   * Home with a full plan beneath the primary action.
   *
   * Rendered tall on purpose: the plan sits below what a phone viewport
   * shows, and a golden cut off above it would be a picture of the part
   * that was already tested.
   */
  testWidgets('08a_home_planned', (tester) async {
    /*
     * Reset first.
     *
     * The mock store is shared across this file and earlier tests add
     * goals and applications to it, so without this the golden depends on
     * what ran before it — a 27% pixel difference between running the file
     * and running the test alone.
     */
    MockStore.instance.reset();

    await pumpScreen(
      tester,
      const HomeScreen(),
      overrides: [
        intelligenceServiceProvider.overrideWithValue(
          const PlannedIntelligence(),
        ),
      ],
      size: const Size(390, 2200),
    );
    await settle(tester);

    // The plan is actually on the screen, not merely in the fixture.
    expect(find.text('What else you could do'), findsOneWidget);
    expect(find.text('Look at your savings buffer'), findsOneWidget);
    expect(find.text('Look again at what you explored'), findsOneWidget);

    await golden(tester, HomeScreen, '08a_home_planned');
  });

  // What the customer explored, and why FynnEdge showed it.
  // The financial review, in the states a customer can ask for it in.
  for (final screen in screenCatalog().where((s) => s.name.startsWith('32'))) {
    screenTest(
      screen.name,
      screen.build,
      screen.type,
      overrides: screen.overrides,
    );
  }

  for (final screen in screenCatalog().where((s) => s.name.startsWith('31'))) {
    screenTest(
      screen.name,
      screen.build,
      screen.type,
      overrides: screen.overrides,
    );
  }

  // The financial story: populated, empty, and unreachable.
  for (final screen in screenCatalog().where((s) => s.name.startsWith('30'))) {
    screenTest(
      screen.name,
      screen.build,
      screen.type,
      overrides: screen.overrides,
    );
  }

  screenTest('29_support', () => const SupportScreen(), SupportScreen);

  // The states that only exist once a customer has asked for something.
  for (final screen in screenCatalog().where(
    (s) => s.name.startsWith('29') && s.name != '29_support',
  )) {
    screenTest(
      screen.name,
      screen.build,
      screen.type,
      overrides: screen.overrides,
    );
  }
}
