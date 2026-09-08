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
import 'package:fynnedge/features/review/review_screen.dart';
import 'package:fynnedge/features/support/support_screen.dart';
import 'package:fynnedge/features/score/fynn_score_screen.dart';
import 'package:fynnedge/features/vault/fynn_scan_screen.dart';
import 'package:fynnedge/features/vault/kyc_screen.dart';
import 'package:fynnedge/features/vault/scan_screen.dart';
import 'package:fynnedge/features/vault/second_opinion_screen.dart';
import 'package:fynnedge/features/vault/vault_screen.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/core/utils/clock.dart';
import 'package:fynnedge/data/models/notification.dart';
import 'package:fynnedge/data/services/notification_service.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/features/welcome/welcome_screen.dart';

import 'package:fynnedge/data/models/support.dart';
import 'package:fynnedge/data/services/support_service.dart';
import 'package:fynnedge/features/support/support_case_screen.dart';
import 'package:fynnedge/features/support/support_request_screen.dart';
import 'support_fixtures.dart';
import 'package:fynnedge/data/models/intelligence.dart';
import 'package:fynnedge/data/services/intelligence_service.dart';
import 'package:fynnedge/features/intelligence/financial_timeline_screen.dart';
import 'intelligence_fixtures.dart';
import 'package:fynnedge/data/models/decision.dart';
import 'package:fynnedge/data/services/decision_service.dart';
import 'package:fynnedge/features/decisions/decision_detail_screen.dart';
import 'package:fynnedge/features/decisions/decision_history_screen.dart';
import 'decision_fixtures.dart';
import 'plan_fixtures.dart';
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

  /// The frozen test clock, so the relative timestamps a golden shows are
  /// the ones the copy actually produces rather than "Just now" for
  /// everything.
  static DateTime get _now => AppClock.now();

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

/// A customer who has explored things.
class PopulatedDecisions implements DecisionService {
  const PopulatedDecisions();

  @override
  Future<List<Decision>> getDecisions() async => decisionHistory;

  @override
  Future<Decision> getDecision(String id) async =>
      decisionHistory.firstWhere((d) => d.id == id);
}

/// A customer who has explored nothing — which, when this shipped, was
/// every customer. The screen has to be honest about that.
class EmptyDecisions implements DecisionService {
  const EmptyDecisions();

  @override
  Future<List<Decision>> getDecisions() async => const [];

  @override
  Future<Decision> getDecision(String id) => throw NetworkException();
}

/// A customer with a financial story.
class PopulatedIntelligence implements IntelligenceService {
  const PopulatedIntelligence();

  @override
  Future<FinancialIntelligence> getIntelligence() async => healthyIntelligence;

  @override
  Future<List<FinancialMoment>> getTimeline() async => financialTimeline;
}

/// A customer with a full three-item plan.
class PlannedIntelligence implements IntelligenceService {
  const PlannedIntelligence();

  @override
  Future<FinancialIntelligence> getIntelligence() async => plannedIntelligence;

  @override
  Future<List<FinancialMoment>> getTimeline() async => financialTimeline;
}

/// A customer FynnEdge has never observed — which, when Module 31 shipped,
/// was every customer. The screen has to be honest about that.
class EmptyIntelligence implements IntelligenceService {
  const EmptyIntelligence();

  @override
  Future<FinancialIntelligence> getIntelligence() async =>
      const FinancialIntelligence();

  @override
  Future<List<FinancialMoment>> getTimeline() async => const [];
}

/// The changes cannot be read, but the story can.
///
/// The two halves of the screen come from two requests, and one failing is
/// not the other failing. This is the state where a customer still sees
/// what happened while FynnEdge cannot tell them what moved.
class ProgressUnavailable extends PopulatedIntelligence {
  const ProgressUnavailable();

  @override
  Future<FinancialIntelligence> getIntelligence() => throw NetworkException();
}

/// A financial story that cannot be reached.
class UnreachableIntelligence extends PopulatedIntelligence {
  const UnreachableIntelligence();

  @override
  Future<List<FinancialMoment>> getTimeline() => throw NetworkException();
}

/// A support desk with requests in it.
///
/// Every case is one the API can genuinely produce — the same statuses, the
/// same server-written sentences, the same reference shape. NO ADVISOR
/// SYSTEM IS CONNECTED, so none of them carries a reply from a person; what
/// they carry is what FynnEdge itself recorded.
class PopulatedSupport implements SupportService {
  const PopulatedSupport();

  static SupportContext get _application => const SupportContext(
    type: 'application',
    label: 'Application',
    reference: 'FE-2026-000042',
    statusLabel: 'Submission status needs confirmation',
    productName: 'SME Term Loan',
  );

  static List<SupportCase> get cases => [
    supportCase(
      id: '3',
      reference: 'FE-SUP-2026-000003',
      category: 'submission_status',
      categoryLabel: 'Application status',
      status: SupportCaseStatus.waitingForCustomer,
      statusLabel: 'Needs your reply',
      statusDescription:
          'We need some information from you to continue.',
      subject: 'Help with application submission status',
      priority: 'high',
      context: _application,
      age: const Duration(hours: 3),
    ),
    supportCase(
      id: '2',
      reference: 'FE-SUP-2026-000002',
      category: 'documents',
      categoryLabel: 'Document help',
      status: SupportCaseStatus.inProgress,
      statusLabel: 'In progress',
      statusDescription: 'We are looking into your request.',
      subject: 'My payslip will not upload',
      age: const Duration(days: 1),
    ),
    supportCase(
      id: '1',
      reference: 'FE-SUP-2026-000001',
      category: 'fynnscore',
      categoryLabel: 'Understanding my FynnScore',
      status: SupportCaseStatus.resolved,
      statusLabel: 'Resolved',
      statusDescription: 'This request has been resolved.',
      subject: 'What moves my FynnScore?',
      age: const Duration(days: 9),
    ),
  ];

  @override
  Future<List<SupportCategoryOption>> getCategories() async =>
      supportCategories;

  @override
  Future<List<SupportCase>> getCases() async => cases;

  @override
  Future<SupportCase> getCase(String id) async {
    final base = cases.firstWhere((c) => c.id == id);

    // The detail view carries what a list does not.
    return supportCase(
      id: base.id,
      reference: base.reference,
      category: base.category,
      categoryLabel: base.categoryLabel,
      status: base.status,
      statusLabel: base.statusLabel,
      statusDescription: base.statusDescription,
      subject: base.subject,
      priority: base.priority,
      context: base.context,
      description:
          'I submitted my application on Tuesday and I am not sure whether '
          'it reached the provider. The app told me not to send it again, '
          'so I would like someone to check what happened to it.',
      messages: id == '3'
          ? [
              SupportMessage(
                id: '1',
                fromCustomer: true,
                body:
                    'I have the reference from the confirmation screen if '
                    'that helps.',
                createdAt: AppClock.now().subtract(const Duration(hours: 2)),
              ),
            ]
          : const [],
      timeline: [
        SupportEvent(
          label: 'Request created',
          source: 'customer',
          occurredAt: AppClock.now().subtract(const Duration(hours: 3)),
        ),
        if (id != '1')
          SupportEvent(
            label: 'You added information',
            source: 'customer',
            occurredAt: AppClock.now().subtract(const Duration(hours: 2)),
          ),
        if (base.status == SupportCaseStatus.resolved)
          SupportEvent(
            label: 'Request resolved',
            source: 'advisor',
            occurredAt: AppClock.now().subtract(const Duration(days: 8)),
          ),
      ],
      age: const Duration(hours: 3),
    );
  }

  @override
  Future<SupportCase> createCase(SupportRequestDraft draft) => getCase('3');

  @override
  Future<SupportCase> addMessage(String id, String body) => getCase(id);

  @override
  Future<SupportCase> closeCase(String id) => getCase(id);
}

/// A support desk that cannot be reached.
class UnreachableSupport extends PopulatedSupport {
  const UnreachableSupport();

  @override
  Future<List<SupportCase>> getCases() => throw NetworkException();
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
///
/// The clock must already be frozen when this is called. Several cases
/// build fixtures whose dates come from AppClock.now(), and a suite that
/// declares its groups before freezing captures the wall clock instead —
/// which passes on the day the goldens were written and fails the next
/// morning. The assertion turns that into a message rather than a pixel
/// diff somebody has to read a date out of.
List<ScreenCase> screenCatalog() {
  assert(
    AppClock.now() == kTestNow,
    'Freeze the clock before building the screen catalogue: fixture dates '
    'are read now, and setUpAll runs too late.',
  );

  return _catalogue();
}

List<ScreenCase> _catalogue() => [
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
  ScreenCase(
    '08a_home_planned',
    () => const HomeScreen(),
    HomeScreen,
    overrides: [
      intelligenceServiceProvider.overrideWithValue(const PlannedIntelligence()),
    ],
  ),
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

  /*
   * The financial plan, in the states a customer can actually be in.
   *
   * Each pairs a goal list with the position the server would return for
   * the same customer. The pairing is the point: a plan is a position and a
   * set of goals read at one instant, and a fixture that mismatched them
   * would show a screen FynnEdge cannot produce.
   */
  ScreenCase(
    '26a_plan_empty',
    () => const GoalsScreen(),
    GoalsScreen,
    overrides: [
      profileServiceProvider.overrideWithValue(const PlanGoals([])),
      intelligenceServiceProvider.overrideWithValue(
        PlanIntelligence(planned(comfortablePosition, bufferAction)),
      ),
    ],
  ),
  ScreenCase(
    '26b_plan_one_goal',
    () => const GoalsScreen(),
    GoalsScreen,
    overrides: [
      profileServiceProvider.overrideWithValue(PlanGoals([planGoal()])),
      intelligenceServiceProvider.overrideWithValue(
        PlanIntelligence(planned(comfortablePosition, bufferAction)),
      ),
    ],
  ),

  // Spending more than they earn. No borrowing shortcut may appear.
  ScreenCase(
    '26c_plan_shortfall',
    () => const GoalsScreen(),
    GoalsScreen,
    overrides: [
      profileServiceProvider.overrideWithValue(PlanGoals([planGoal()])),
      intelligenceServiceProvider.overrideWithValue(
        PlanIntelligence(planned(shortfallPosition, reviewFiguresAction)),
      ),
    ],
  ),

  // A goal whose two amounts have met, and one that has not.
  ScreenCase(
    '26d_plan_reached',
    () => const GoalsScreen(),
    GoalsScreen,
    overrides: [
      profileServiceProvider.overrideWithValue(
        PlanGoals([reachedGoal, planGoal()]),
      ),
      intelligenceServiceProvider.overrideWithValue(
        PlanIntelligence(planned(comfortablePosition, bufferAction)),
      ),
    ],
  ),

  // A wrapping title, figures in crores and a date that has gone by.
  ScreenCase(
    '26e_plan_strained',
    () => const GoalsScreen(),
    GoalsScreen,
    overrides: [
      profileServiceProvider.overrideWithValue(PlanGoals([strainedGoal])),
      intelligenceServiceProvider.overrideWithValue(
        PlanIntelligence(planned(comfortablePosition, bufferAction)),
      ),
    ],
  ),

  // Nothing entered: no figures are shown, and none are invented.
  ScreenCase(
    '26f_plan_no_income',
    () => const GoalsScreen(),
    GoalsScreen,
    overrides: [
      profileServiceProvider.overrideWithValue(const PlanGoals([])),
      intelligenceServiceProvider.overrideWithValue(
        PlanIntelligence(planned(unknownPosition, completeProfileAction)),
      ),
    ],
  ),

  // The position could not be read. Goals still render; no stale surplus is
  // presented as the current one.
  ScreenCase(
    '26g_plan_position_error',
    () => const GoalsScreen(),
    GoalsScreen,
    overrides: [
      profileServiceProvider.overrideWithValue(PlanGoals([planGoal()])),
      intelligenceServiceProvider.overrideWithValue(
        const UnreachableIntelligenceState(),
      ),
    ],
  ),
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
  ScreenCase(
    '31_decisions',
    () => const DecisionHistoryScreen(),
    DecisionHistoryScreen,
    overrides: [
      decisionServiceProvider.overrideWithValue(const PopulatedDecisions()),
    ],
  ),
  ScreenCase(
    '31a_decisions_empty',
    () => const DecisionHistoryScreen(),
    DecisionHistoryScreen,
    overrides: [
      decisionServiceProvider.overrideWithValue(const EmptyDecisions()),
    ],
  ),
  ScreenCase(
    '31b_decision_simulation',
    () => const DecisionDetailScreen(decisionId: 'd3'),
    DecisionDetailScreen,
    overrides: [
      decisionServiceProvider.overrideWithValue(const PopulatedDecisions()),
    ],
  ),
  ScreenCase(
    '31c_decision_comparison',
    () => const DecisionDetailScreen(decisionId: 'd2'),
    DecisionDetailScreen,
    overrides: [
      decisionServiceProvider.overrideWithValue(const PopulatedDecisions()),
    ],
  ),
  ScreenCase(
    '31d_decision_application',
    () => const DecisionDetailScreen(decisionId: 'a1:started'),
    DecisionDetailScreen,
    overrides: [
      decisionServiceProvider.overrideWithValue(const PopulatedDecisions()),
    ],
  ),
  ScreenCase(
    '30_financial_story',
    () => const FinancialTimelineScreen(),
    FinancialTimelineScreen,
    overrides: [
      intelligenceServiceProvider.overrideWithValue(
        const PopulatedIntelligence(),
      ),
    ],
  ),
  ScreenCase(
    '30a_financial_story_empty',
    () => const FinancialTimelineScreen(),
    FinancialTimelineScreen,
    overrides: [
      intelligenceServiceProvider.overrideWithValue(const EmptyIntelligence()),
    ],
  ),
  ScreenCase(
    '30b_financial_story_error',
    () => const FinancialTimelineScreen(),
    FinancialTimelineScreen,
    overrides: [
      intelligenceServiceProvider.overrideWithValue(
        const UnreachableIntelligence(),
      ),
    ],
  ),
  /*
   * The financial review, in the states a customer can ask for it in.
   *
   * Each is one read of one customer, so a section can never describe them
   * at a different instant from the section above it.
   */
  ScreenCase('32_review', () => const ReviewScreen(), ReviewScreen),
  ScreenCase(
    '32a_review_empty',
    () => const ReviewScreen(),
    ReviewScreen,
    overrides: [
      // Nothing entered. No figures, no score, no goals — and the one step
      // that leads anywhere.
      intelligenceServiceProvider.overrideWithValue(
        PlanIntelligence(
          review(
            position: unknownPosition,
            score: noScore,
            action: completeProfileAction,
          ),
        ),
      ),
      decisionServiceProvider.overrideWithValue(const EmptyDecisions()),
    ],
  ),
  ScreenCase(
    '32b_review_shortfall',
    () => const ReviewScreen(),
    ReviewScreen,
    overrides: [
      // Spending more than they earn. Nothing on the screen may point at
      // borrowing.
      intelligenceServiceProvider.overrideWithValue(
        PlanIntelligence(
          review(
            position: shortfallPosition,
            score: stretchedScore,
            goals: reviewGoals,
            action: reviewFiguresAction,
          ),
        ),
      ),
      decisionServiceProvider.overrideWithValue(const EmptyDecisions()),
    ],
  ),
  ScreenCase(
    '32c_review_dense',
    () => const ReviewScreen(),
    ReviewScreen,
    overrides: [
      // Every section at once: position, score, a reached goal beside a
      // running one, observed changes, recorded decisions and a next step.
      intelligenceServiceProvider.overrideWithValue(
        PlanIntelligence(
          review(
            score: goodScore,
            goals: reviewGoals,
            progress: observedProgress,
          ),
        ),
      ),
      decisionServiceProvider.overrideWithValue(const PopulatedDecisions()),
    ],
  ),
  ScreenCase(
    '32d_review_large',
    () => const ReviewScreen(),
    ReviewScreen,
    overrides: [
      // A wrapping goal title and figures in crores.
      intelligenceServiceProvider.overrideWithValue(
        PlanIntelligence(
          review(
            position: comfortablePosition,
            goals: largeGoals,
            progress: recoveredProgress,
          ),
        ),
      ),
      decisionServiceProvider.overrideWithValue(const EmptyDecisions()),
    ],
  ),
  ScreenCase(
    '32e_review_error',
    () => const ReviewScreen(),
    ReviewScreen,
    overrides: [
      intelligenceServiceProvider.overrideWithValue(
        const UnreachableIntelligenceState(),
      ),
      decisionServiceProvider.overrideWithValue(const EmptyDecisions()),
    ],
  ),

  /*
   * Progress: the states a customer's observed history can actually be in.
   *
   * Each pairs the changes with a story coherent with them. A fixture whose
   * timeline said the score went from 64 to 71 while the progress list said
   * nothing had moved would be a picture of a screen contradicting itself.
   */
  ScreenCase(
    '30c_progress_baseline',
    () => const FinancialTimelineScreen(),
    FinancialTimelineScreen,
    overrides: [
      // Observed once. A baseline is not a trend, and the screen says which
      // of the two this customer has.
      intelligenceServiceProvider.overrideWithValue(
        const PlanIntelligence(FinancialIntelligence(observations: 1)),
      ),
    ],
  ),
  ScreenCase(
    '30d_progress_recovered',
    () => const FinancialTimelineScreen(),
    FinancialTimelineScreen,
    overrides: [
      // A surplus that was negative and is not any more, and a figure in
      // crores — the two shapes that break a row's layout.
      intelligenceServiceProvider.overrideWithValue(
        PlanIntelligence(
          FinancialIntelligence(
            observations: 3,
            hasComparableHistory: true,
            progress: recoveredProgress,
          ),
        ),
      ),
    ],
  ),
  ScreenCase(
    '30e_progress_unreachable',
    () => const FinancialTimelineScreen(),
    FinancialTimelineScreen,
    overrides: [
      // The changes cannot be read. The story below them still can, and no
      // figure is shown in place of the ones that are missing.
      intelligenceServiceProvider.overrideWithValue(
        const ProgressUnavailable(),
      ),
    ],
  ),

  ScreenCase('29_support', () => const SupportScreen(), SupportScreen),
  ScreenCase(
    '29a_support_populated',
    () => const SupportScreen(),
    SupportScreen,
    overrides: [
      supportServiceProvider.overrideWithValue(const PopulatedSupport()),
    ],
  ),
  ScreenCase(
    '29b_support_error',
    () => const SupportScreen(),
    SupportScreen,
    overrides: [
      supportServiceProvider.overrideWithValue(const UnreachableSupport()),
    ],
  ),
  ScreenCase(
    '29c_support_request',
    () => const SupportRequestScreen(
      category: 'submission_status',
      contextType: 'application',
      contextId: '42',
    ),
    SupportRequestScreen,
    overrides: [
      supportServiceProvider.overrideWithValue(const PopulatedSupport()),
    ],
  ),
  ScreenCase(
    '29d_support_case_waiting',
    () => const SupportCaseScreen(caseId: '3'),
    SupportCaseScreen,
    overrides: [
      supportServiceProvider.overrideWithValue(const PopulatedSupport()),
    ],
  ),
  ScreenCase(
    '29e_support_case_in_progress',
    () => const SupportCaseScreen(caseId: '2'),
    SupportCaseScreen,
    overrides: [
      supportServiceProvider.overrideWithValue(const PopulatedSupport()),
    ],
  ),
  ScreenCase(
    '29f_support_case_resolved',
    () => const SupportCaseScreen(caseId: '1'),
    SupportCaseScreen,
    overrides: [
      supportServiceProvider.overrideWithValue(const PopulatedSupport()),
    ],
  ),
];
