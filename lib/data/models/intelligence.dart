import '../../core/utils/clock.dart';
import 'goal.dart';
import 'json.dart';

/// The one next step FynnEdge suggests.
class NextAction {
  const NextAction({
    required this.type,
    required this.title,
    required this.reason,
    required this.actionLabel,
    required this.actionRoute,
    this.priority = 0,
  });

  final String type;
  final String title;

  /// Why this one, in the customer's terms. Never a promise about what
  /// happens if they take it.
  final String reason;

  final String actionLabel;
  final String actionRoute;

  /// Where this sat in the ladder. Lower is more urgent.
  final int priority;

  factory NextAction.fromJson(Map<String, dynamic> json) => NextAction(
    type: J.str(json['type']),
    title: J.str(json['title']),
    reason: J.str(json['reason']),
    actionLabel: J.str(json['action_label']),
    actionRoute: J.str(json['action_route']),
    priority: J.integer(json['priority']),
  );
}

/// One thing FynnEdge can say about the customer's money now.
class FinancialInsight {
  const FinancialInsight({
    required this.type,
    required this.source,
    required this.title,
    required this.body,
    this.actionLabel,
    this.actionRoute,
  });

  final String type;

  /// Which authoritative part of FynnEdge produced it. Never a model.
  final String source;

  final String title;
  final String body;
  final String? actionLabel;
  final String? actionRoute;

  factory FinancialInsight.fromJson(Map<String, dynamic> json) =>
      FinancialInsight(
        type: J.str(json['type']),
        source: J.str(json['source']),
        title: J.str(json['title']),
        body: J.str(json['body']),
        actionLabel: J.strOrNull(json['action_label']),
        actionRoute: J.strOrNull(json['action_route']),
      );
}

/// Something that happened in the customer's financial life.
class FinancialMoment {
  const FinancialMoment({
    required this.id,
    required this.type,
    required this.importance,
    required this.title,
    required this.description,
    required this.occurredAt,
    this.contextType,
    this.contextReference,
  });

  final String id;
  final String type;
  final String importance;
  final String title;
  final String description;
  final DateTime occurredAt;
  final String? contextType;

  /// A reference the customer already sees elsewhere, e.g. FE-2026-000042.
  final String? contextReference;

  bool get isMajor => importance == 'major';

  factory FinancialMoment.fromJson(Map<String, dynamic> json) =>
      FinancialMoment(
        id: J.str(json['id']),
        type: J.str(json['type']),
        importance: J.str(json['importance']),
        title: J.str(json['title']),
        description: J.str(json['description']),
        occurredAt: J.date(json['occurred_at']) ?? AppClock.now(),
        contextType: J.strOrNull(json['context_type']),
        contextReference: J.strOrNull(json['context_reference']),
      );
}

/// Where the customer's recorded income sits against their recorded outgo.
///
/// Mirrors App\Domain\Financial\SurplusState. [unknown] is not a fourth
/// judgement — it is the absence of an income figure, and the screen says so
/// rather than showing a zero.
enum SurplusState {
  positive,
  matched,
  negative,
  unknown;

  static SurplusState fromId(String? id) => switch (id) {
    'positive' => SurplusState.positive,
    'matched' => SurplusState.matched,
    'negative' => SurplusState.negative,
    _ => SurplusState.unknown,
  };
}

/// Where the customer currently stands, as the server described it.
///
/// Every figure was produced by FinancialEngine and every sentence was
/// written by App\Domain\Financial\FinancialPosition. The app repeats both;
/// it derives neither. A plan header that recomputed a surplus would be a
/// second opinion about the customer's own money.
class FinancialPosition {
  const FinancialPosition({
    this.isMeasurable = false,
    this.surplusState = SurplusState.unknown,
    this.statement = '',
    this.income = 0,
    this.monthlyOutgo = 0,
    this.surplus = 0,
    this.emergencyMonths,
    this.emergencyReferenceMonths = 6,
    this.emergencyBelowReference = false,
    this.emergencyStatement,
  });

  /// Whether an income figure exists to measure anything against.
  final bool isMeasurable;

  final SurplusState surplusState;

  /// The position in one sentence, in the server's words.
  final String statement;

  final double income;
  final double monthlyOutgo;
  final double surplus;

  /// Null when nothing is recorded as going out, because then the question
  /// "how many months would my savings cover" has no answer. Never rendered
  /// as zero: that would say a buffer is thin when FynnEdge simply has not
  /// been told what the customer spends.
  final double? emergencyMonths;

  /// FynnEdge's existing reference, carried rather than hard-coded here.
  final int emergencyReferenceMonths;

  final bool emergencyBelowReference;

  /// The buffer in one sentence, or null when there is nothing to say.
  final String? emergencyStatement;

  factory FinancialPosition.fromJson(Map<String, dynamic> json) =>
      FinancialPosition(
        isMeasurable: J.boolean(json['is_measurable']),
        surplusState: SurplusState.fromId(J.strOrNull(json['surplus_state'])),
        statement: J.str(json['statement']),
        income: J.dbl(json['income']),
        monthlyOutgo: J.dbl(json['monthly_outgo']),
        surplus: J.dbl(json['surplus']),
        emergencyMonths: J.dblOrNull(json['emergency_months']),
        emergencyReferenceMonths: J.integer(
          json['emergency_reference_months'],
          6,
        ),
        emergencyBelowReference: J.boolean(json['emergency_below_reference']),
        emergencyStatement: J.strOrNull(json['emergency_statement']),
      );
}

/// One FynnScore component, as it stood at each end of a score change.
///
/// Both values were stored when their score was calculated. Nothing here is
/// recomputed from the customer's current profile, which is what keeps a
/// historical explanation still true tomorrow.
class ObservedScoreComponent {
  const ObservedScoreComponent({
    required this.label,
    required this.previousValue,
    required this.currentValue,
    required this.previousScore,
    required this.currentScore,
  });

  final String label;
  final double previousValue;
  final double currentValue;
  final int previousScore;
  final int currentScore;

  factory ObservedScoreComponent.fromJson(Map<String, dynamic> json) =>
      ObservedScoreComponent(
        label: J.str(json['label']),
        previousValue: J.dbl(json['previous_value']),
        currentValue: J.dbl(json['current_value']),
        previousScore: J.integer(json['previous_score']),
        currentScore: J.integer(json['current_score']),
      );
}

/// One figure that actually moved between two things FynnEdge wrote down.
///
/// Both ends are stored observations. Neither is the customer's current
/// state, so nothing here can be a record compared with a live reading.
///
/// The sentences come from the server. The app repeats them rather than
/// composing its own, because a history that phrased a figure differently
/// from the screen it came off would read as a different product's numbers.
class ObservedChange {
  const ObservedChange({
    required this.metric,
    required this.label,
    required this.previousDisplay,
    required this.currentDisplay,
    required this.summary,
    required this.spokenSummary,
    required this.direction,
    required this.source,
    required this.observedAt,
    this.previousBand,
    this.band,
    this.components = const [],
  });

  final String metric;
  final String label;

  /// Already formatted by the server, Indian grouping and sign included.
  final String previousDisplay;
  final String currentDisplay;

  final String summary;

  /// The same fact with the direction as a word, for a screen reader. An
  /// arrow between two numbers is legible and silent.
  final String spokenSummary;

  /// `increased` or `decreased` — a description of two numbers, never a
  /// judgement about which way is better.
  final String direction;

  /// customer_provided or calculated. Never simulated, never a provider's.
  final String source;

  final DateTime observedAt;

  final String? previousBand;
  final String? band;

  /// Present on a FynnScore change only: what each component was worth when
  /// each score was calculated.
  final List<ObservedScoreComponent> components;

  bool get isScore => metric == 'fynn_score';

  bool get bandChanged =>
      previousBand != null && band != null && previousBand != band;

  factory ObservedChange.fromJson(Map<String, dynamic> json) => ObservedChange(
    metric: J.str(json['metric']),
    label: J.str(json['label']),
    previousDisplay: J.str(json['previous_display']),
    currentDisplay: J.str(json['current_display']),
    summary: J.str(json['summary']),
    spokenSummary: J.str(json['spoken_summary']),
    direction: J.str(json['direction']),
    source: J.str(json['source']),
    observedAt: J.date(json['observed_at']) ?? AppClock.now(),
    previousBand: J.strOrNull(json['previous_band']),
    band: J.strOrNull(json['band']),
    components: J.objects(json['components'], ObservedScoreComponent.fromJson),
  );
}

/// The FynnScore, as anything other than the FynnScore screen needs it.
///
/// The figure, the band and the band's own sentence — all decided by
/// App\Domain\Score\FynnScore, which is the only thing that scores anybody.
/// The dimensions, the curves and the recommendations belong to the
/// FynnScore screen and are deliberately absent here.
class ScoreSummary {
  const ScoreSummary({
    this.hasScore = false,
    this.score,
    this.band,
    this.bandLabel,
    this.summary = '',
    this.missing = const [],
  });

  final bool hasScore;
  final int? score;
  final String? band;
  final String? bandLabel;

  /// The band's sentence when there is a score, and the engine's own reason
  /// when there is not. A customer without a score is told why.
  final String summary;

  /// What the engine still needs. Empty once it has enough.
  final List<String> missing;

  factory ScoreSummary.fromJson(Map<String, dynamic> json) => ScoreSummary(
    hasScore: J.boolean(json['has_score']),
    score: J.intOrNull(json['score']),
    band: J.strOrNull(json['band']),
    bandLabel: J.strOrNull(json['band_label']),
    summary: J.str(json['summary']),
    missing: J.strings(json['missing_requirements']),
  );
}

/// What FynnEdge understands about the customer's money.
class FinancialIntelligence {
  const FinancialIntelligence({
    this.position = const FinancialPosition(),
    this.score = const ScoreSummary(),
    this.goals = const [],
    this.goalCount = 0,
    this.nextAction,
    this.plan = const [],
    this.insights = const [],
    this.recentMoments = const [],
    this.observations = 0,
    this.hasComparableHistory = false,
    this.progress = const [],
  });

  /// The factual half of the plan: what the numbers currently show.
  ///
  /// Separate from [nextAction], which is what the customer could do about
  /// it. Both come from one read of one state, so they cannot describe two
  /// different customers.
  final FinancialPosition position;

  /// The score from the same read as everything else here.
  final ScoreSummary score;

  /// The customer's active goals, nearest target date first — the ordering
  /// the Goals module established. None is singled out as the important
  /// one; FynnEdge was never told which that is.
  ///
  /// Bounded by the server. [goalCount] is the true total, so a short list
  /// never reads as the whole of somebody's goals.
  final List<Goal> goals;

  final int goalCount;

  final NextAction? nextAction;

  /// A short plan, in the order the rules produced it.
  ///
  /// The first item is [nextAction] — the same ladder answers both, so the
  /// card on Home and the plan below it cannot disagree. Capped at three by
  /// the server, and allowed to be short or empty: a customer with nothing
  /// pending is told so rather than handed an invented task.
  final List<NextAction> plan;

  final List<FinancialInsight> insights;
  final List<FinancialMoment> recentMoments;

  /// How many times FynnEdge has written down what was true.
  final int observations;

  /// Whether there is enough history to say anything about change.
  ///
  /// False for every customer who has not changed anything since FynnEdge
  /// started observing — which, when this shipped, was all of them. The
  /// screen says so rather than showing a blank where a trend would go.
  final bool hasComparableHistory;

  /// What FynnEdge has actually observed changing, newest first.
  ///
  /// Empty is the ordinary answer and means exactly what it says: nothing
  /// has been observed to change. It is not a chart with no points, and the
  /// screen says so rather than drawing one.
  final List<ObservedChange> progress;

  factory FinancialIntelligence.fromJson(Map<String, dynamic> json) {
    final history = J.map(json['history']);

    final goals = J.map(json['goals']);

    return FinancialIntelligence(
      position: FinancialPosition.fromJson(J.map(json['position'])),
      score: ScoreSummary.fromJson(J.map(json['score'])),
      goals: J.objects(goals['items'], Goal.fromIntelligenceJson),
      goalCount: J.integer(goals['count']),
      nextAction: json['next_action'] is Map<String, dynamic>
          ? NextAction.fromJson(json['next_action'] as Map<String, dynamic>)
          : null,
      plan: (json['plan'] as List? ?? const [])
          .map((e) => NextAction.fromJson(e as Map<String, dynamic>))
          .toList(),
      insights: (json['insights'] as List? ?? const [])
          .map((e) => FinancialInsight.fromJson(e as Map<String, dynamic>))
          .toList(),
      recentMoments: (json['recent_moments'] as List? ?? const [])
          .map((e) => FinancialMoment.fromJson(e as Map<String, dynamic>))
          .toList(),
      observations: J.integer(history['observations']),
      hasComparableHistory: J.boolean(history['has_comparable_history']),
      progress: J.objects(history['items'], ObservedChange.fromJson),
    );
  }
}
