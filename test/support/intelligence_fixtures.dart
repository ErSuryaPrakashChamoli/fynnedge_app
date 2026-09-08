import 'package:fynnedge/core/utils/clock.dart';
import 'package:fynnedge/data/models/intelligence.dart';

import 'harness.dart';

/// Intelligence fixtures, shared by the unit tests and the golden
/// catalogue.
///
/// Every one is something the API can genuinely produce: the same next
/// action types, the same insight sources, the same moment shapes. A
/// fixture with invented copy would be a picture of a screen that cannot
/// happen — and, in this module particularly, a picture of a claim FynnEdge
/// refuses to make.
/// What FynnEdge observed changing, for a customer who has been observed
/// more than once.
///
/// Coherent with the moments beside it on purpose: the timeline says the
/// score went from 64 to 71, so the progress list says the same thing about
/// the same customer. A fixture where the two disagreed would be a picture
/// of a screen contradicting itself — which is exactly the fault these
/// goldens exist to catch.
List<ObservedChange> get observedProgress => [
  ObservedChange(
    metric: 'fynn_score',
    label: 'FynnScore',
    previousDisplay: '64',
    currentDisplay: '71',
    summary: 'FynnScore changed from 64 to 71.',
    spokenSummary: 'FynnScore increased from 64 to 71.',
    direction: 'increased',
    source: 'calculated',
    observedAt: _observed,
    previousBand: 'good',
    band: 'good',
    components: [
      ObservedScoreComponent(
        label: 'Emergency Buffer',
        previousValue: 2.1,
        currentValue: 3,
        previousScore: 35,
        currentScore: 50,
      ),
    ],
  ),
  ObservedChange(
    metric: 'surplus',
    label: 'Recorded monthly surplus',
    previousDisplay: '₹28,000',
    currentDisplay: '₹40,000',
    summary: 'Recorded monthly surplus changed from ₹28,000 to ₹40,000.',
    spokenSummary:
        'Recorded monthly surplus increased from ₹28,000 to ₹40,000.',
    direction: 'increased',
    source: 'calculated',
    observedAt: _observed,
  ),
  ObservedChange(
    metric: 'emergency_months',
    label: 'Emergency buffer',
    previousDisplay: '2.1 months',
    currentDisplay: '3 months',
    summary: 'Emergency buffer changed from 2.1 months to 3 months.',
    spokenSummary: 'Emergency buffer increased from 2.1 months to 3 months.',
    direction: 'increased',
    source: 'calculated',
    observedAt: _observed,
  ),
];

/// A customer whose recorded outgo used to exceed their recorded income.
///
/// Stated as two figures and nothing else. "Your finances recovered" is an
/// interpretation of somebody's life; "changed from -₹8,000 to ₹12,000" is
/// two rows in a table.
List<ObservedChange> get recoveredProgress => [
  ObservedChange(
    metric: 'surplus',
    label: 'Recorded monthly surplus',
    previousDisplay: '-₹8,000',
    currentDisplay: '₹12,000',
    summary: 'Recorded monthly surplus changed from -₹8,000 to ₹12,000.',
    spokenSummary:
        'Recorded monthly surplus increased from -₹8,000 to ₹12,000.',
    direction: 'increased',
    source: 'calculated',
    observedAt: _observed,
  ),
  ObservedChange(
    metric: 'monthly_income',
    label: 'Recorded monthly income',
    previousDisplay: '₹1,00,00,000',
    currentDisplay: '₹1,25,00,000',
    summary:
        'Recorded monthly income changed from ₹1,00,00,000 to ₹1,25,00,000.',
    spokenSummary:
        'Recorded monthly income increased from ₹1,00,00,000 to ₹1,25,00,000.',
    direction: 'increased',
    source: 'customer_provided',
    observedAt: _observed,
  ),
];

/// Fixed rather than relative: a golden that renders a timestamp must not
/// move when the suite is run on a different day.
final DateTime _observed = kTestNow.subtract(const Duration(hours: 4));

/// The position MockStore's customer actually has.
///
/// ₹1,00,000 recorded coming in, ₹60,000 going out, ₹1,80,000 saved — which
/// is three months of outgo against FynnEdge's six-month reference. Every
/// golden that pairs an intelligence fixture with the mock home snapshot
/// shows both, so a fixture that quoted a different buffer would put two
/// answers about one customer on one screen.
const FinancialPosition mockPosition = FinancialPosition(
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

FinancialMoment get scoreMoment => FinancialMoment(
  id: '4',
  type: 'score_improved',
  importance: 'ordinary',
  title: 'Your FynnScore improved',
  description: 'It went from 64 to 71.',
  occurredAt: AppClock.now().subtract(const Duration(hours: 4)),
);

/// A customer whose application FynnEdge sent and never heard back about.
const FinancialIntelligence blockedIntelligence = FinancialIntelligence(
  position: mockPosition,
  nextAction: NextAction(
    type: 'resolve_submission_status',
    title: 'Your application needs attention',
    reason: 'We could not confirm whether the provider received '
        'FE-2026-000042.',
    actionLabel: 'Open application',
    actionRoute: '/applications/1',
  ),
  insights: [
    FinancialInsight(
      type: 'application_attention',
      source: 'application',
      title: 'Your application needs attention',
      body: 'We could not confirm whether the provider received '
          'FE-2026-000042. Please do not submit it again — we can check '
          'what happened to it.',
      actionLabel: 'Get help',
      actionRoute: '/applications/1',
    ),
  ],
  observations: 3,
  hasComparableHistory: true,
);

/// A customer with several things worth doing, in ladder order.
///
/// Every item is one the server can genuinely produce, with the reason it
/// would give. Nothing here points at a product.
FinancialIntelligence get plannedIntelligence => FinancialIntelligence(
  position: mockPosition,
  progress: observedProgress,
  nextAction: coachPlan.first,
  plan: coachPlan,
  insights: const [],
  recentMoments: financialTimeline.take(2).toList(),
  observations: 3,
  hasComparableHistory: true,
);

/// A three-item plan whose first item is what Home's primary action card
/// shows.
///
/// That agreement is not decoration. On the server both come from one
/// ladder, so a fixture whose first item differed from the card above it
/// would be a picture of a screen that cannot occur — and the golden would
/// stop being evidence of anything.
const List<NextAction> coachPlan = [
  NextAction(
    type: 'explore_options',
    title: 'Explore your options',
    reason: 'See what suits the goal you set.',
    actionLabel: 'Explore',
    actionRoute: '/loan-discovery',
    priority: 10,
  ),
  NextAction(
    type: 'review_buffer',
    title: 'Look at your savings buffer',
    reason: 'Your recorded savings would cover about 3 months of your '
        'monthly outgo. FynnEdge measures against 6 months.',
    actionLabel: 'Plan a buffer',
    actionRoute: '/fynnlab/emergency-fund',
    priority: 20,
  ),
  NextAction(
    type: 'review_decision',
    title: 'Look again at what you explored',
    reason: 'You have something in your history. You can see the figures '
        'FynnEdge used at the time and how it was worked out.',
    actionLabel: 'What you explored',
    actionRoute: '/decisions',
    priority: 30,
  ),
];

/// A customer with a story and nothing wrong.
FinancialIntelligence get healthyIntelligence => FinancialIntelligence(
  position: mockPosition,
  progress: observedProgress,
  nextAction: const NextAction(
    type: 'explore_options',
    title: 'Explore your options',
    reason: 'See what suits the goal you set.',
    actionLabel: 'Explore',
    actionRoute: '/loan-discovery',
  ),
  plan: const [
    NextAction(
      type: 'explore_options',
      title: 'Explore your options',
      reason: 'See what suits the goal you set.',
      actionLabel: 'Explore',
      actionRoute: '/loan-discovery',
      priority: 10,
    ),
  ],
  insights: const [
    FinancialInsight(
      type: 'goal_deadline',
      source: 'goal',
      title: 'Your target date is close',
      body: 'You have about 2 months left and ₹40,000 still to save.',
      actionLabel: 'Review your goal',
      actionRoute: '/goals',
    ),
  ],
  recentMoments: financialTimeline.take(3).toList(),
  observations: 4,
  hasComparableHistory: true,
);

/// The customer's story, as the API would return it.
List<FinancialMoment> get financialTimeline => [
  scoreMoment,
  FinancialMoment(
    id: '3',
    type: 'goal_milestone',
    importance: 'ordinary',
    title: 'A milestone worth noting',
    description: 'You are 50% of the way to Emergency fund.',
    occurredAt: AppClock.now().subtract(const Duration(days: 4)),
  ),
  FinancialMoment(
    id: '2',
    type: 'application_started',
    importance: 'ordinary',
    title: 'You started an application',
    description: 'For SME Term Loan. Nothing has been sent anywhere yet.',
    occurredAt: AppClock.now().subtract(const Duration(days: 11)),
    contextType: 'application',
    contextReference: 'FE-2026-000042',
  ),
  FinancialMoment(
    id: '1',
    type: 'score_available',
    importance: 'notable',
    title: 'Your FynnScore is ready',
    description: 'It is 64, in the good range. It is FynnEdge\'s own reading '
        'of the details you entered, not a credit score.',
    occurredAt: AppClock.now().subtract(const Duration(days: 40)),
  ),
];
