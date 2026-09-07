import 'json.dart';

/// Where this customer stands with credit information.
///
/// Every state is truthful about what FynnEdge does and does not know. There
/// is deliberately no state that means "assume it is fine".
enum CreditReportStatus {
  /// No bureau is connected to this deployment. The capability does not
  /// exist, so it is not offered.
  notConfigured('not_configured'),

  /// A bureau exists, and the customer has not permitted a check.
  consentRequired('consent_required'),

  /// Permitted, never asked. Consent is permission to ask, not an
  /// instruction to.
  notRequested('not_requested'),

  /// FynnEdge holds credit information for this customer.
  available('available'),

  /// The last attempt did not produce information. Nothing is assumed in
  /// its place.
  failed('failed'),

  /// A state this build does not know.
  unknown('unknown');

  const CreditReportStatus(this.id);
  final String id;

  bool get hasReport => this == CreditReportStatus.available;

  static CreditReportStatus fromId(String? id) => J.enumById(
    CreditReportStatus.values,
    id,
    (s) => s.id,
    CreditReportStatus.unknown,
  );
}

/// A credit bureau's score for this customer.
///
/// This is NOT a FynnScore. A FynnScore is FynnEdge's own view of financial
/// health, computed from figures the customer entered. A bureau score is a
/// third party's view of credit history, on its own scale, by its own
/// method. Nothing in FynnEdge converts one into the other, and this class
/// deliberately offers no arithmetic that would let it.
class CreditProfile {
  const CreditProfile({
    required this.score,
    required this.scoreModel,
    required this.scoreMin,
    required this.scoreMax,
    required this.bureau,
    required this.bureauLabel,
    required this.isSample,
    required this.obtainedAt,
  });

  final int score;

  /// The scoring model the bureau used. A score means nothing without it:
  /// two bureaus' numbers are not comparable and must never be shown as if
  /// they were.
  final String scoreModel;

  final int scoreMin;
  final int scoreMax;

  final String bureau;
  final String bureauLabel;

  /// True when this came from a fictional bureau. A sample score must never
  /// be presented as a real one.
  final bool isSample;

  final DateTime? obtainedAt;

  /// Where the score sits on its own scale, 0..1. For a gauge only — it is
  /// not a percentage, a probability, or a quality rating.
  double get positionOnScale {
    if (scoreMax <= scoreMin) return 0;
    final clamped = score.clamp(scoreMin, scoreMax);
    return (clamped - scoreMin) / (scoreMax - scoreMin);
  }

  /// The scale, written out. Always shown with the score, never apart from
  /// it.
  String get scaleLabel => '$scoreMin–$scoreMax';

  static CreditProfile? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;

    final score = J.intOrNull(raw['score']);
    final model = J.strOrNull(raw['score_model']);
    final scale = J.map(raw['scale']);
    final min = J.intOrNull(scale['min']);
    final max = J.intOrNull(scale['max']);

    // A score with no model or no scale cannot be compared against anything
    // and cannot be drawn on a gauge. Refuse it rather than render a number
    // with invented context.
    if (score == null || model == null || min == null || max == null) {
      return null;
    }

    return CreditProfile(
      score: score,
      scoreModel: model,
      scoreMin: min,
      scoreMax: max,
      bureau: J.str(raw['bureau']),
      bureauLabel: J.str(raw['bureau_label'], 'Credit bureau'),
      isSample: J.boolean(raw['is_sample']),
      obtainedAt: J.date(raw['obtained_at']),
    );
  }
}

/// The whole credit picture: the state, and the report if there is one.
class CreditState {
  const CreditState({required this.status, this.profile});

  final CreditReportStatus status;

  /// Present only when [status] is available. Never a zero standing in for
  /// "we do not know" — a nought would be read as a score.
  final CreditProfile? profile;

  bool get hasReport => profile != null;

  /// Whether the customer can ask for a check right now.
  bool get canCheck =>
      status == CreditReportStatus.notRequested ||
      status == CreditReportStatus.failed ||
      status == CreditReportStatus.available;

  bool get needsConsent => status == CreditReportStatus.consentRequired;

  bool get isUnavailable => status == CreditReportStatus.notConfigured;

  static const CreditState unknown = CreditState(
    status: CreditReportStatus.unknown,
  );

  static CreditState fromJson(Map<String, dynamic> json) {
    final data = json.containsKey('data') ? J.map(json['data']) : json;

    return CreditState(
      status: CreditReportStatus.fromId(J.strOrNull(data['status'])),
      profile: CreditProfile.fromJson(data['profile']),
    );
  }
}
