import 'json.dart';

/// A weighted factor behind a **FynnTrust** score (Module 13), not FynnScore.
///
/// FynnScore v1 uses [ScoreDimension], which carries the metric it reads and
/// the anchors it is measured against. This simpler shape is kept because the
/// FynnTrust breakdown still uses it.
class ScoreFactor {
  const ScoreFactor({
    required this.label,
    required this.value,
    required this.explanation,
    this.weight = 1,
  });

  final String label;
  final int value; // 0..100
  final String explanation;
  final double weight;

  factory ScoreFactor.fromJson(Map<String, dynamic> json) => ScoreFactor(
    label: J.str(json['label']),
    value: J.integer(json['value']),
    explanation: J.str(json['explanation']),
    weight: J.dbl(json['weight'], 1),
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'value': value,
    'explanation': explanation,
    'weight': weight,
  };
}

/// FynnScore bands, on the product's colour breakpoints (75/55/40).
enum ScoreBand {
  strong('strong', 'Strong'),
  good('good', 'Good'),
  needsAttention('needs_attention', 'Needs Attention'),
  atRisk('at_risk', 'At Risk');

  const ScoreBand(this.id, this.label);

  final String id;
  final String label;

  static ScoreBand? fromId(String? id) {
    if (id == null) return null;
    for (final b in ScoreBand.values) {
      if (b.id == id) return b;
    }
    return null;
  }

  static ScoreBand forScore(int score) => switch (score) {
    >= 75 => ScoreBand.strong,
    >= 55 => ScoreBand.good,
    >= 40 => ScoreBand.needsAttention,
    _ => ScoreBand.atRisk,
  };
}

/// One scored dimension, with everything needed to explain it.
class ScoreDimension {
  const ScoreDimension({
    required this.key,
    required this.name,
    required this.score,
    required this.weight,
    required this.metric,
    required this.metricValue,
    required this.metricUnit,
    required this.fullMarksAt,
    required this.zeroAt,
    required this.explanation,
    required this.isHelping,
  });

  final String key;
  final String name;

  /// 0..100.
  final int score;
  final double weight;

  /// The FinancialEngine metric this reads, e.g. `emi_ratio`.
  final String metric;
  final double metricValue;
  final String metricUnit;

  /// Metric values scoring 100 and 0 — the anchors, so the UI can show the
  /// customer what "good" is without hardcoding a threshold.
  final double fullMarksAt;
  final double zeroAt;

  final String explanation;

  /// True when this dimension sits at or above the overall score.
  final bool isHelping;

  factory ScoreDimension.fromJson(Map<String, dynamic> json) => ScoreDimension(
    key: J.str(json['key']),
    name: J.str(json['name']),
    score: J.integer(json['score']),
    weight: J.dbl(json['weight']),
    metric: J.str(json['metric']),
    metricValue: J.dbl(json['metric_value']),
    metricUnit: J.str(json['metric_unit']),
    fullMarksAt: J.dbl(json['full_marks_at']),
    zeroAt: J.dbl(json['zero_at']),
    explanation: J.str(json['explanation']),
    isHelping: J.boolean(json['is_helping']),
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'score': score,
    'weight': weight,
    'metric': metric,
    'metric_value': metricValue,
    'metric_unit': metricUnit,
    'full_marks_at': fullMarksAt,
    'zero_at': zeroAt,
    'explanation': explanation,
    'is_helping': isHelping,
  };
}

/// An improvement with a reproducible impact: the score recalculated with one
/// metric at its full-marks anchor, minus the current score.
class ScoreRecommendation {
  const ScoreRecommendation({
    required this.dimension,
    required this.title,
    required this.detail,
    required this.metric,
    required this.currentValue,
    required this.targetValue,
    required this.currentScore,
    required this.projectedScore,
    required this.delta,
  });

  final String dimension;
  final String title;
  final String detail;
  final String metric;
  final double currentValue;
  final double targetValue;
  final int currentScore;
  final int projectedScore;

  /// projectedScore - currentScore. Never an estimate.
  final int delta;

  factory ScoreRecommendation.fromJson(Map<String, dynamic> json) =>
      ScoreRecommendation(
        dimension: J.str(json['dimension']),
        title: J.str(json['title']),
        detail: J.str(json['detail']),
        metric: J.str(json['metric']),
        currentValue: J.dbl(json['current_value']),
        targetValue: J.dbl(json['target_value']),
        currentScore: J.integer(json['current_score']),
        projectedScore: J.integer(json['projected_score']),
        delta: J.integer(json['delta']),
      );

  Map<String, dynamic> toJson() => {
    'dimension': dimension,
    'title': title,
    'detail': detail,
    'metric': metric,
    'current_value': currentValue,
    'target_value': targetValue,
    'current_score': currentScore,
    'projected_score': projectedScore,
    'delta': delta,
  };
}

/// The customer's FynnScore, or an explicit statement that there is not yet
/// enough information to calculate one.
///
/// There is no third state, and never a fabricated number.
class FynnScore {
  const FynnScore({
    required this.hasScore,
    this.score,
    this.band,
    this.summary = '',
    this.modelVersion = '',
    this.dimensions = const [],
    this.recommendations = const [],
    this.helping = const [],
    this.needsAttention = const [],
    this.metrics = const {},
    this.missingRequirements = const [],
    this.inputsUpdatedAt,
    this.disclaimer = '',
  });

  final bool hasScore;

  /// Null when [hasScore] is false.
  final int? score;
  final ScoreBand? band;

  final String summary;
  final String modelVersion;

  final List<ScoreDimension> dimensions;
  final List<ScoreRecommendation> recommendations;

  /// Dimension names, split around the overall score.
  final List<String> helping;
  final List<String> needsAttention;

  /// The FinancialEngine figures the score read.
  final Map<String, double> metrics;

  /// What the customer still needs to provide, when there is no score.
  final List<String> missingRequirements;

  /// When the figures behind the score last changed — not when it was
  /// calculated, because the score itself is time-independent.
  final DateTime? inputsUpdatedAt;

  final String disclaimer;

  factory FynnScore.fromJson(Map<String, dynamic> json) {
    // Both conditions, not either: a malformed payload that omits `status`
    // must not claim to carry a score it does not have. The screen unwraps
    // `score!` on the strength of this flag.
    final value = J.intOrNull(json['score']);
    final hasScore = J.str(json['status'], 'ok') == 'ok' && value != null;

    return FynnScore(
      hasScore: hasScore,
      score: hasScore ? value : null,
      band: ScoreBand.fromId(J.strOrNull(json['band'])),
      summary: J.str(json['summary']),
      modelVersion: J.str(json['model_version']),
      dimensions: J.objects(json['dimensions'], ScoreDimension.fromJson),
      recommendations: J.objects(
        json['recommendations'],
        ScoreRecommendation.fromJson,
      ),
      helping: J.strings(json['helping']),
      needsAttention: J.strings(json['needs_attention']),
      metrics: _metrics(json['metrics']),
      missingRequirements: J.strings(json['missing_requirements']),
      inputsUpdatedAt: J.date(json['inputs_updated_at']),
      disclaimer: J.str(json['disclaimer']),
    );
  }

  Map<String, dynamic> toJson() => {
    'status': hasScore ? 'ok' : 'insufficient_data',
    'model_version': modelVersion,
    'score': score,
    'band': band?.id,
    'band_label': band?.label,
    'summary': summary,
    'dimensions': dimensions.map((d) => d.toJson()).toList(),
    'recommendations': recommendations.map((r) => r.toJson()).toList(),
    'helping': helping,
    'needs_attention': needsAttention,
    'metrics': metrics,
    'missing_requirements': missingRequirements,
    'inputs_updated_at': inputsUpdatedAt?.toIso8601String(),
    'disclaimer': disclaimer,
  };

  static Map<String, double> _metrics(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries) entry.key.toString(): J.dbl(entry.value),
    };
  }
}
