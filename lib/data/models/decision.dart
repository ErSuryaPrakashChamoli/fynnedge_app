import '../../core/utils/clock.dart';
import 'json.dart';

/// Where a figure in an explanation came from.
///
/// Carried on every number the customer is shown, so a rate they read can
/// be seen to have been published by a lender rather than invented by
/// FynnEdge.
class ExplanationFactor {
  const ExplanationFactor({
    required this.label,
    required this.value,
    required this.source,
    required this.sourceLabel,
    this.note,
  });

  final String label;
  final String value;
  final String source;
  final String sourceLabel;
  final String? note;

  factory ExplanationFactor.fromJson(Map<String, dynamic> json) =>
      ExplanationFactor(
        label: J.str(json['label']),
        value: J.str(json['value']),
        source: J.str(json['source']),
        sourceLabel: J.str(json['source_label']),
        note: J.strOrNull(json['note']),
      );
}

/// Why FynnEdge showed what it showed.
class DecisionExplanation {
  const DecisionExplanation({
    required this.title,
    required this.rule,
    required this.factors,
    this.result,
    this.notAssessed = const [],
  });

  final String title;

  /// The rule that joined the figures, in the customer's terms.
  final String rule;

  final List<ExplanationFactor> factors;
  final ExplanationFactor? result;

  /// What FynnEdge could not work out.
  ///
  /// Shown rather than omitted: a gap where approval would be is a gap a
  /// customer reads as a pass.
  final List<String> notAssessed;

  factory DecisionExplanation.fromJson(Map<String, dynamic> json) =>
      DecisionExplanation(
        title: J.str(json['title']),
        rule: J.str(json['rule']),
        factors: (json['factors'] as List? ?? const [])
            .map((e) => ExplanationFactor.fromJson(e as Map<String, dynamic>))
            .toList(),
        result: json['result'] is Map<String, dynamic>
            ? ExplanationFactor.fromJson(json['result'] as Map<String, dynamic>)
            : null,
        notAssessed: (json['not_assessed'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

/// The product a decision was about.
class DecisionProduct {
  const DecisionProduct({required this.code, this.name, this.version});

  final String code;
  final String? name;

  /// The catalogue version that produced what was shown. It is what makes
  /// an old decision stable when the catalogue moves.
  final int? version;

  factory DecisionProduct.fromJson(Map<String, dynamic> json) =>
      DecisionProduct(
        code: J.str(json['code']),
        name: J.strOrNull(json['name']),
        version: json['version'] is num ? (json['version'] as num).toInt() : null,
      );
}

/// One thing the customer explored.
///
/// Never a claim about what they wanted, preferred or chose — running a
/// simulation is running a simulation.
class Decision {
  const Decision({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.occurredAt,
    required this.isSimulated,
    this.product,
    this.reference,
    this.explanation = const [],
  });

  final String id;
  final String type;
  final String title;
  final String description;
  final DateTime occurredAt;

  /// True of nothing that has happened. Shown wherever the decision is.
  final bool isSimulated;

  final DecisionProduct? product;

  /// The customer-facing reference, when the entry has one.
  final String? reference;

  /// Present on the detail view only.
  final List<DecisionExplanation> explanation;

  factory Decision.fromJson(Map<String, dynamic> json) => Decision(
    id: J.str(json['id']),
    type: J.str(json['type']),
    title: J.str(json['title']),
    description: J.str(json['description']),
    occurredAt: J.date(json['occurred_at']) ?? AppClock.now(),
    isSimulated: J.boolean(json['is_simulated']),
    product: json['product'] is Map<String, dynamic>
        ? DecisionProduct.fromJson(json['product'] as Map<String, dynamic>)
        : null,
    reference: J.strOrNull(json['reference']),
    explanation: (json['explanation'] as List? ?? const [])
        .map((e) => DecisionExplanation.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
