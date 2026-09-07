import 'json.dart';

/// Where one identity verification stands.
///
/// The distinction this enum exists to hold is between [unavailable] and
/// [notVerified]. "FynnEdge cannot check identity" and "we checked, and
/// could not establish it" are different facts about different things — the
/// first about the product, the second about the customer — and a customer
/// told the second when the first is true has been accused of something.
enum VerificationStatus {
  notStarted('not_started', 'Not checked'),
  unavailable('unavailable', 'Not available'),
  consentRequired('consent_required', 'Your permission needed'),
  processing('processing', 'Checking'),
  verified('verified', 'Verification passed'),
  notVerified('not_verified', 'Could not be established'),
  needsReview('needs_review', 'Please review a difference'),
  failed('failed', 'Check did not complete'),

  /// A previous result is no longer current. Never a synonym for failed.
  expired('expired', 'No longer current');

  const VerificationStatus(this.id, this.label);
  final String id;
  final String label;

  static VerificationStatus fromId(String? id) => J.enumById(
    VerificationStatus.values,
    id,
    (s) => s.id,

    // An unknown status is never taken for a pass.
    VerificationStatus.unavailable,
  );

  bool get hasResult =>
      this == verified ||
      this == notVerified ||
      this == needsReview ||
      this == expired;

  bool get isWorking => this == processing;
}

/// The result of one check, on its own.
///
/// A verification carries two of these and never merges them: a document can
/// pass a service's own checks while the identity on it does not match the
/// customer's profile.
enum CheckOutcome {
  passed('passed', 'Passed'),
  failed('failed', 'Did not pass'),
  inconclusive('inconclusive', 'Could not be established'),
  notPerformed('not_performed', 'Not checked');

  const CheckOutcome(this.id, this.label);
  final String id;
  final String label;

  static CheckOutcome? fromId(String? id) =>
      CheckOutcome.values.where((o) => o.id == id).firstOrNull;
}

/// How one identity field compared with the customer's profile.
enum MatchStatus {
  matched('matched', 'Matched'),
  mismatched('mismatched', 'Did not match'),

  /// FynnEdge holds nothing to compare against. Not a mismatch.
  unableToCompare('unable_to_compare', 'Could not be compared');

  const MatchStatus(this.id, this.label);
  final String id;
  final String label;

  static MatchStatus fromId(String? id) => J.enumById(
    MatchStatus.values,
    id,
    (s) => s.id,
    MatchStatus.unableToCompare,
  );
}

/// One field comparison.
///
/// Values arrive only where the customer has a difference to resolve. A
/// matched field carries none: they already know what is on their profile.
class FieldMatch {
  const FieldMatch({
    required this.field,
    required this.label,
    required this.status,
    this.reason,
    this.profileValue,
    this.verifiedValue,
  });

  final String field;
  final String label;
  final MatchStatus status;
  final String? reason;

  final String? profileValue;
  final String? verifiedValue;

  bool get isDifference =>
      status == MatchStatus.mismatched &&
      profileValue != null &&
      verifiedValue != null;

  static FieldMatch fromJson(Map<String, dynamic> json) => FieldMatch(
    field: J.str(json['field']),
    label: J.str(json['label']),
    status: MatchStatus.fromId(J.strOrNull(json['status'])),
    reason: J.strOrNull(json['reason']),
    profileValue: J.strOrNull(json['profile_value']),
    verifiedValue: J.strOrNull(json['verified_value']),
  );
}

/// What FynnEdge knows about verifying one document.
class KycVerification {
  const KycVerification({
    required this.documentId,
    required this.status,
    this.verificationId,
    this.provider,
    this.reason,
    this.message,
    this.verificationType,
    this.isSupported = false,
    this.method,
    this.isSample = false,
    this.isStale = false,
    this.documentResult,
    this.identityResult,
    this.maskedReference,
    this.checkedAt,
    this.expiresAt,
    this.fieldMatches,
    this.disclaimer,
  });

  final String documentId;
  final String? verificationId;
  final VerificationStatus status;
  final String? provider;
  final String? reason;
  final String? message;

  final String? verificationType;
  final bool isSupported;

  /// What was actually done, in words. A status without its method is a
  /// badge rather than a finding.
  final String? method;

  /// True when a fictional service produced this. Server-owned.
  final bool isSample;

  /// True when the file behind the document changed since it was checked.
  final bool isStale;

  /// The two findings, apart.
  final CheckOutcome? documentResult;
  final CheckOutcome? identityResult;

  /// A masked tail, so the customer can tell which document was checked.
  final String? maskedReference;

  final DateTime? checkedAt;

  /// Always null today: no provider or policy defines an expiry.
  final DateTime? expiresAt;

  /// Null when nothing has been checked. Never an empty list, which would
  /// read as a check that ran and found nothing to disagree with.
  final List<FieldMatch>? fieldMatches;

  final String? disclaimer;

  bool get needsConsent => status == VerificationStatus.consentRequired;

  bool get canVerify =>
      isSupported &&
      (status == VerificationStatus.notStarted ||
          status == VerificationStatus.failed ||
          status.hasResult);

  List<FieldMatch> get differences =>
      fieldMatches?.where((m) => m.isDifference).toList() ?? const [];

  factory KycVerification.fromJson(Map<String, dynamic> json) =>
      KycVerification(
        documentId: J.str(json['document_id']),
        verificationId: J.strOrNull(json['verification_id']),
        status: VerificationStatus.fromId(J.strOrNull(json['status'])),
        provider: J.strOrNull(json['provider']),
        reason: J.strOrNull(json['reason']),
        message: J.strOrNull(json['message']),
        verificationType: J.strOrNull(json['verification_type']),
        isSupported: J.boolean(json['is_supported']),
        method: J.strOrNull(json['method']),
        isSample: J.boolean(json['is_sample']),
        isStale: J.boolean(json['is_stale']),
        documentResult: CheckOutcome.fromId(J.strOrNull(json['document_result'])),
        identityResult: CheckOutcome.fromId(J.strOrNull(json['identity_result'])),
        maskedReference: J.strOrNull(json['masked_reference']),
        checkedAt: J.date(json['checked_at']),
        expiresAt: J.date(json['expires_at']),

        // Null and empty are different answers, so the distinction is kept.
        fieldMatches: json['field_matches'] == null
            ? null
            : J.objects(json['field_matches'], FieldMatch.fromJson),

        disclaimer: J.strOrNull(json['disclaimer']),
      );
}

/// What the customer decided about a difference.
enum ResolutionDecision {
  keepProfile('keep_profile'),
  updateProfile('update_profile');

  const ResolutionDecision(this.id);
  final String id;
}
