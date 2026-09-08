import 'package:fynnedge/core/utils/clock.dart';
import 'package:fynnedge/data/models/goal.dart';
import 'package:fynnedge/data/models/intent.dart';
import 'package:fynnedge/data/models/score.dart';
import 'package:fynnedge/data/models/intelligence.dart';
import 'package:fynnedge/data/models/user.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/intelligence_service.dart';
import 'package:fynnedge/data/services/profile_service.dart';


/// Fixtures for the financial plan.
///
/// Every position here is one App\Domain\Financial\FinancialPosition can
/// produce, sentence for sentence, and every goal figure is what
/// FinancialEngine derives from the two amounts beside it. A fixture that
/// invented either would make the goldens pictures of a screen that cannot
/// occur.

/// A goal list the screen is handed, and nothing else.
class PlanGoals implements ProfileService {
  const PlanGoals(this._goals);

  final List<Goal> _goals;

  /// Server-derived, exactly as the API returns them — progress, months and
  /// the monthly figure all come from the engine rather than the screen.
  @override
  Future<List<Goal>> getGoals() async =>
      _goals.map((g) => g.withLocalDerived()).toList();

  @override
  Future<Goal> createGoal(Goal goal) async => goal.withLocalDerived();
  @override
  Future<Goal> updateGoal(Goal goal) async => goal.withLocalDerived();
  @override
  Future<void> deleteGoal(String id) async {}
  @override
  Future<UserProfile> getProfile() async =>
      const UserProfile(id: '1', mobile: '9876543210', fullName: 'Rahul');
  @override
  Future<UserProfile> updateProfile(UserProfile p) async => p;
  @override
  Future<FinancialProfile> getFinancialProfile() async =>
      const FinancialProfile();
  @override
  Future<FinancialProfile> updateFinancialProfile(FinancialProfile p) async =>
      p;
  @override
  Future<FynnScore> getFynnScore() async => const FynnScore(hasScore: false);
}

/// A goal list that cannot be read.
class UnreachableGoals extends PlanGoals {
  const UnreachableGoals() : super(const []);

  @override
  Future<List<Goal>> getGoals() => throw NetworkException();
}

/// One fixed answer from /intelligence.
class PlanIntelligence implements IntelligenceService {
  const PlanIntelligence(this._intelligence);

  final FinancialIntelligence _intelligence;

  @override
  Future<FinancialIntelligence> getIntelligence() async => _intelligence;

  @override
  Future<List<FinancialMoment>> getTimeline() async => const [];
}

/// A position that cannot be read, so the plan says so rather than showing
/// a figure from an earlier request as though it were current.
class UnreachableIntelligenceState implements IntelligenceService {
  const UnreachableIntelligenceState();

  @override
  Future<FinancialIntelligence> getIntelligence() => throw NetworkException();

  @override
  Future<List<FinancialMoment>> getTimeline() => throw NetworkException();
}

/// A position that never arrives, for the loading state.
class PendingIntelligence implements IntelligenceService {
  const PendingIntelligence();

  @override
  Future<FinancialIntelligence> getIntelligence() =>
      Future.any([]); // never completes

  @override
  Future<List<FinancialMoment>> getTimeline() async => const [];
}

// --- positions --------------------------------------------------------------

/// Income above outgo, buffer under the six-month reference.
const FinancialPosition comfortablePosition = FinancialPosition(
  isMeasurable: true,
  surplusState: SurplusState.positive,
  statement: 'Your recorded income is higher than your monthly outgo.',
  income: 100000,
  monthlyOutgo: 60000,
  surplus: 40000,
  emergencyMonths: 3,
  emergencyBelowReference: true,
  emergencyStatement:
      'Your recorded savings would cover about 3 months of your monthly '
      'outgo. FynnEdge measures against 6 months.',
);

/// More recorded going out than coming in.
///
/// The plan must never point this customer at borrowing — not in an action,
/// and not in the "explore options" shortcut on a goal card.
const FinancialPosition shortfallPosition = FinancialPosition(
  isMeasurable: true,
  surplusState: SurplusState.negative,
  statement:
      'Your recorded monthly outgo is higher than your recorded income.',
  income: 60000,
  monthlyOutgo: 78000,
  surplus: -18000,
  emergencyMonths: 0.5,
  emergencyBelowReference: true,
  emergencyStatement:
      'Your recorded savings would cover less than a month of your monthly '
      'outgo. FynnEdge measures against 6 months.',
);

/// Nothing entered, so nothing to work out.
const FinancialPosition unknownPosition = FinancialPosition(
  statement:
      'FynnEdge has no monthly income recorded, so it cannot work out your '
      'position.',
);

// --- actions ----------------------------------------------------------------

const NextAction bufferAction = NextAction(
  type: 'review_buffer',
  title: 'Look at your savings buffer',
  reason:
      'Your recorded savings would cover about 3 months of your monthly '
      'outgo. FynnEdge measures against 6 months.',
  actionLabel: 'Plan a buffer',
  actionRoute: '/fynnlab/emergency-fund',
  priority: 10,
);

const NextAction reviewFiguresAction = NextAction(
  type: 'review_profile',
  title: 'Check your recorded figures',
  reason:
      'What FynnEdge has recorded going out each month is more than what it '
      'has recorded coming in. If any of those figures have changed, '
      'updating them gives a more accurate picture.',
  actionLabel: 'Review your figures',
  actionRoute: '/financial-profile',
  priority: 10,
);

const NextAction completeProfileAction = NextAction(
  type: 'complete_profile',
  title: 'Add your financial details',
  reason:
      'Without them FynnEdge cannot work out your FynnScore or what you can '
      'afford.',
  actionLabel: 'Add your details',
  actionRoute: '/financial-profile',
  priority: 10,
);

FinancialIntelligence planned(FinancialPosition position, NextAction action) =>
    FinancialIntelligence(
      position: position,
      nextAction: action,
      plan: [action],
    );

// --- goals ------------------------------------------------------------------

Goal planGoal({
  String id = 'goal_1',
  String title = 'Emergency fund',
  GoalCategory category = GoalCategory.other,
  double target = 300000,
  double saved = 120000,
  int inDays = 540,
}) => Goal(
  id: id,
  title: title,
  category: category,
  targetAmount: target,
  targetDate: AppClock.now().add(Duration(days: inDays)),
  savedAmount: saved,
);

/// Saved has met target, which is the only definition of a reached goal —
/// there is no completed status to set.
Goal get reachedGoal =>
    planGoal(id: 'goal_done', title: 'New laptop', target: 90000, saved: 90000);

/// The awkward one: a title that has to wrap, figures in crores, and a date
/// that has gone by.
Goal get strainedGoal => Goal(
  id: 'goal_long',
  title: 'Buy a bigger home for the family in North Bengaluru',
  category: GoalCategory.home,
  targetAmount: 25000000,
  targetDate: AppClock.now().subtract(const Duration(days: 30)),
  savedAmount: 4500000,
);

// --- reviews -----------------------------------------------------------------

/// A goal whose two amounts have met, and one still running — the pair a
/// review has to be able to describe differently.
List<Goal> get reviewGoals => [
  planGoal(id: 'g1', title: 'Emergency fund'),
  reachedGoal,
];

/// The awkward review: a title that has to wrap and figures in crores.
List<Goal> get largeGoals => [
  Goal(
    id: 'g_large',
    title: 'Buy a bigger home for the family in North Bengaluru',
    category: GoalCategory.home,
    targetAmount: 25000000,
    targetDate: AppClock.now().add(const Duration(days: 900)),
    savedAmount: 4500000,
  ),
];

const ScoreSummary strongScore = ScoreSummary(
  hasScore: true,
  score: 83,
  band: 'strong',
  bandLabel: 'Strong',
  summary: 'Your financial health looks strong.',
);

/// Where observedProgress ends: 71, in the Good band.
///
/// Every profile change records an observation, so a customer's current
/// score and the newest observed score are the same number. A fixture
/// showing 83 beside "changed from 64 to 71" would be a picture of a screen
/// that cannot occur.
const ScoreSummary goodScore = ScoreSummary(
  hasScore: true,
  score: 71,
  band: 'good',
  bandLabel: 'Good',
  summary: 'Your financial health looks good, with room to improve.',
);

const ScoreSummary stretchedScore = ScoreSummary(
  hasScore: true,
  score: 38,
  band: 'at_risk',
  bandLabel: 'At Risk',
  summary: 'Your finances are stretched. Steady them before taking on new '
      'debt.',
);

/// No income recorded, so no score — and the engine's own reason for it.
const ScoreSummary noScore = ScoreSummary(
  summary: 'Add your monthly income and we can work out your FynnScore. '
      'Everything else follows from it.',
  missing: ['monthly_income'],
);

/// One read of one customer, assembled the way the server assembles it.
FinancialIntelligence review({
  FinancialPosition position = comfortablePosition,
  ScoreSummary score = strongScore,
  List<Goal> goals = const [],
  List<ObservedChange> progress = const [],
  NextAction? action = bufferAction,
}) => FinancialIntelligence(
  position: position,
  score: score,
  goals: goals.map((g) => g.withLocalDerived()).toList(),
  goalCount: goals.length,
  progress: progress,
  nextAction: action,
  plan: action == null ? const [] : [action],
  observations: progress.isEmpty ? 0 : 3,
  hasComparableHistory: progress.isNotEmpty,
);
