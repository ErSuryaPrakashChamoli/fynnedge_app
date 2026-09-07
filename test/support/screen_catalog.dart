import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:fynnedge/app/session.dart';
import 'package:fynnedge/features/ai/ai_screen.dart';
import 'package:fynnedge/features/applications/application_detail_screen.dart';
import 'package:fynnedge/features/applications/applications_screen.dart';
import 'package:fynnedge/features/auth/login_screen.dart';
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
import 'package:fynnedge/features/credit/credit_screen.dart';
import 'package:fynnedge/features/profile/privacy_screen.dart';
import 'package:fynnedge/features/profile/profile_screen.dart';
import 'package:fynnedge/features/profile/support_screen.dart';
import 'package:fynnedge/features/score/fynn_score_screen.dart';
import 'package:fynnedge/features/vault/fynn_scan_screen.dart';
import 'package:fynnedge/features/vault/kyc_screen.dart';
import 'package:fynnedge/features/vault/scan_screen.dart';
import 'package:fynnedge/features/vault/second_opinion_screen.dart';
import 'package:fynnedge/features/vault/vault_screen.dart';
import 'package:fynnedge/data/models/notification.dart';
import 'package:fynnedge/data/services/notification_service.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/features/welcome/welcome_screen.dart';

import 'harness.dart';

/// Two offers already ticked, so the comparison table renders.
class PresetCompare extends CompareNotifier {
  @override
  List<String> build() => const ['prod_bl_b', 'prod_bl_a'];
}

/// A notification centre with something in it.
///
/// Every one of these is a message the policy can genuinely produce — the
/// same types, the same copy, the same links. A golden of invented copy
/// would be a picture of a screen that cannot happen, and would let the
/// real copy overflow unnoticed.
class PopulatedNotifications implements NotificationService {
  const PopulatedNotifications();

  static final DateTime _now = DateTime(2026, 9, 7, 14, 30);

  static List<AppNotification> get items => [
    AppNotification(
      id: '6',
      type: 'action_required',
      category: NotificationCategory.application,
      title: 'Your application needs something from you',
      body:
          'The provider needs something more before they can continue. Open '
          'your application to see what to do next.',
      createdAt: _now.subtract(const Duration(minutes: 20)),
      deepLink: 'fynnedge://applications/7',
    ),
    AppNotification(
      id: '5',
      type: 'submission_needs_confirmation',
      category: NotificationCategory.application,
      // The longest message the policy produces, so the golden shows what
      // the tile does with a body that wraps to four lines.
      title: 'Your submission needs confirming',
      body:
          'We could not confirm whether the provider received your '
          'application. Please do not submit it again — that could create a '
          'second application. We are checking, and support can help if you '
          'need it.',
      createdAt: _now.subtract(const Duration(hours: 3)),
      deepLink: 'fynnedge://applications/7',
    ),
    AppNotification(
      id: '4',
      type: 'document_needs_review',
      category: NotificationCategory.document,
      title: 'One of your documents needs attention',
      body:
          'Your income proof needs a look before it can be used. Open it to '
          'see what to check.',
      createdAt: _now.subtract(const Duration(days: 1)),
      read: true,
      deepLink: 'fynnedge://vault/12',
    ),
    AppNotification(
      id: '3',
      type: 'fynnscore_changed',
      category: NotificationCategory.financialHealth,
      title: 'Your FynnScore improved',
      body:
          'Your FynnScore is now in the good range. It is FynnEdge\'s own '
          'reading of the details you entered, not a credit score. Open it '
          'to see what moved.',
      createdAt: _now.subtract(const Duration(days: 3)),
      read: true,
      deepLink: 'fynnedge://fynn-score',
    ),
    AppNotification(
      id: '2',
      type: 'goal_milestone',
      category: NotificationCategory.goal,
      title: 'Goal milestone reached',
      body: 'You are 50% of the way to Emergency fund.',
      createdAt: _now.subtract(const Duration(days: 20)),
      read: true,
      deepLink: 'fynnedge://goals',
    ),
    AppNotification(
      id: '1',
      type: 'application_started',
      category: NotificationCategory.application,
      title: 'Application started',
      body:
          'Your application for SME Term Loan is saved in FynnEdge. It has '
          'not been sent anywhere yet.',
      createdAt: _now.subtract(const Duration(days: 40)),
      read: true,
      deepLink: 'fynnedge://applications/7',
    ),
  ];

  @override
  Future<NotificationPage> getNotifications({
    int? before,
    int limit = 20,
  }) async => NotificationPage(items: items, unreadCount: 2, nextCursor: 1);

  @override
  Future<int> getUnreadCount() async => 2;

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}

  @override
  Future<NotificationPreferences> getPreferences() async =>
      const NotificationPreferences(
        pushEnabled: true,
        mutedCategories: [],
        mutableCategories: ['financial_health', 'goal'],
        pushAvailable: false,
        marketingAvailable: false,
      );

  @override
  Future<NotificationPreferences> updatePreferences({
    bool? pushEnabled,
    List<String>? mutedCategories,
  }) => getPreferences();
}

/// A notification centre that cannot be reached.
class UnreachableNotifications extends PopulatedNotifications {
  const UnreachableNotifications();

  @override
  Future<NotificationPage> getNotifications({int? before, int limit = 20}) =>
      throw NetworkException();
}

/// One screen, declared once and reused by the golden suite and the
/// responsive suite so the two can never drift apart.
class ScreenCase {
  const ScreenCase(
    this.name,
    this.build,
    this.type, {
    this.overrides = const [],
    this.setUp,
  });

  final String name;
  final Widget Function() build;
  final Type type;
  final List<Override> overrides;

  /// Runs before the screen is pumped, for screens whose content only exists
  /// once the customer has done something.
  final Future<void> Function()? setUp;
}

/// Every screen in the product, in journey order.
List<ScreenCase> screenCatalog() => [
  ScreenCase('02_welcome', () => const WelcomeScreen(), WelcomeScreen),
  ScreenCase('03_login', () => const LoginScreen(), LoginScreen),
  ScreenCase('04_otp', () => const OtpScreen(devHint: '123456'), OtpScreen),
  ScreenCase(
    '05_basic_profile',
    () => const BasicProfileScreen(),
    BasicProfileScreen,
  ),
  ScreenCase('06_intent', () => const IntentScreen(), IntentScreen),
  ScreenCase('07_goal', () => const GoalScreen(), GoalScreen),
  ScreenCase('08_home', () => const HomeScreen(), HomeScreen),
  ScreenCase('09_explore', () => const ExploreScreen(), ExploreScreen),
  ScreenCase(
    '10_loan_discovery',
    () => const LoanDiscoveryScreen(),
    LoanDiscoveryScreen,
  ),
  ScreenCase(
    '11_loan_options',
    () => const LoanOptionsScreen(),
    LoanOptionsScreen,
  ),
  ScreenCase(
    '12_loan_detail',
    () => const LoanDetailScreen(productId: 'prod_bl_b'),
    LoanDetailScreen,
  ),
  ScreenCase('13_compare_empty', () => const CompareScreen(), CompareScreen),
  ScreenCase(
    '13_compare',
    () => const CompareScreen(),
    CompareScreen,
    overrides: [compareProvider.overrideWith(PresetCompare.new)],
  ),
  ScreenCase(
    '14_fynn_trust',
    () => const FynnTrustScreen(productId: 'prod_bl_b'),
    FynnTrustScreen,
  ),
  ScreenCase(
    '15_fynn_mirror',
    () => const FynnMirrorScreen(productId: 'prod_bl_a'),
    FynnMirrorScreen,
  ),
  ScreenCase('16_fynnlab', () => const FynnLabScreen(), FynnLabScreen),
  ScreenCase('16a_emi', () => const EmiCalculatorScreen(), EmiCalculatorScreen),
  ScreenCase(
    '16b_affordability',
    () => const AffordabilityScreen(),
    AffordabilityScreen,
  ),
  ScreenCase(
    '16c_prepayment',
    () => const PrepaymentScreen(),
    PrepaymentScreen,
  ),
  ScreenCase(
    '16d_balance_transfer',
    () => const BalanceTransferScreen(),
    BalanceTransferScreen,
  ),
  ScreenCase(
    '16e_emergency_fund',
    () => const EmergencyFundScreen(),
    EmergencyFundScreen,
  ),
  ScreenCase('17_fynn_score', () => const FynnScoreScreen(), FynnScoreScreen),
  ScreenCase('18_fynn_ai', () => const AiScreen(), AiScreen),
  ScreenCase(
    '19_applications',
    () => const ApplicationsScreen(),
    ApplicationsScreen,
    setUp: seedApplication,
  ),
  ScreenCase(
    '20_application_detail',
    () => const ApplicationDetailScreen(id: 'app_1'),
    ApplicationDetailScreen,
    setUp: () => seedApplication(submit: true),
  ),
  ScreenCase('21_vault', () => const VaultScreen(), VaultScreen),
  ScreenCase('22_scan', () => const ScanScreen(), ScanScreen),

  // Mock mode has no document provider, so this golden is the state a
  // customer actually sees today: stored, unread, and a plain reason why.
  ScreenCase(
    '22b_fynn_scan',
    () => const FynnScanScreen(documentId: 'doc_1'),
    FynnScanScreen,
  ),

  // Mock mode has no verification service, so this golden is the state a
  // customer actually sees today: not available, and a plain reason why.
  ScreenCase(
    '22c_kyc',
    () => const KycScreen(documentId: 'doc_1'),
    KycScreen,
  ),
  ScreenCase(
    '23_second_opinion',
    () => const SecondOpinionScreen(),
    SecondOpinionScreen,
  ),
  ScreenCase('24_profile', () => const ProfileScreen(), ProfileScreen),
  ScreenCase(
    '25_financial_profile',
    () => const FinancialProfileScreen(),
    FinancialProfileScreen,
  ),
  ScreenCase('26_goals', () => const GoalsScreen(), GoalsScreen),
  ScreenCase(
    '27_notifications',
    () => const NotificationsScreen(),
    NotificationsScreen,
  ),
  ScreenCase(
    '27a_notifications_populated',
    () => const NotificationsScreen(),
    NotificationsScreen,
    overrides: [
      notificationServiceProvider.overrideWithValue(
        const PopulatedNotifications(),
      ),
    ],
  ),
  ScreenCase(
    '27b_notifications_error',
    () => const NotificationsScreen(),
    NotificationsScreen,
    overrides: [
      notificationServiceProvider.overrideWithValue(
        const UnreachableNotifications(),
      ),
    ],
  ),
  ScreenCase('28_privacy', () => const PrivacyScreen(), PrivacyScreen),
  ScreenCase('28a_credit', () => const CreditScreen(), CreditScreen),
  ScreenCase('29_support', () => const SupportScreen(), SupportScreen),
];
