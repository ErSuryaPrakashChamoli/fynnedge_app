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
import 'package:fynnedge/features/profile/support_screen.dart';
import 'package:fynnedge/features/score/fynn_score_screen.dart';
import 'package:fynnedge/features/splash/splash_screen.dart';
import 'package:fynnedge/features/vault/scan_screen.dart';
import 'package:fynnedge/features/vault/second_opinion_screen.dart';
import 'package:fynnedge/features/vault/vault_screen.dart';
import 'package:fynnedge/features/welcome/welcome_screen.dart';

import 'package:fynnedge/app/session.dart';

import 'support/harness.dart';

/// Two offers already ticked, so the comparison table renders.
class _PresetCompare extends CompareNotifier {
  @override
  List<String> build() => const ['prod_bl_b', 'prod_bl_a'];
}

/// Renders every screen at phone size, checks it builds without throwing, and
/// writes a golden PNG to test/goldens. Refresh with:
///   flutter test test/screens_test.dart --update-goldens
void main() {
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
  screenTest(
    '27_notifications',
    () => const NotificationsScreen(),
    NotificationsScreen,
  );
  screenTest('28_privacy', () => const PrivacyScreen(), PrivacyScreen);

  // Mock mode has no bureau connected, so this golden is the state a
  // customer actually sees today: no score, and a plain explanation of why.
  screenTest('28a_credit', () => const CreditScreen(), CreditScreen);
  screenTest('29_support', () => const SupportScreen(), SupportScreen);
}
