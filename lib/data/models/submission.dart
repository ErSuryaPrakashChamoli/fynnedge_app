import 'json.dart';

/// What actually happened when FynnEdge tried to send an application.
///
/// A different axis from the application's own status. That one says what
/// the customer did inside FynnEdge; this one says what an external provider
/// did or did not do with it. Collapsing them is the mistake this whole
/// screen exists to prevent.
enum SubmissionOutcome {
  notAttempted('not_attempted', 'Not yet sent'),
  submitting('submitting', 'Sending'),
  acceptedForSubmission('accepted_for_submission', 'Accepted for submission'),

  /// The only outcome that means an external party has the application.
  providerReceived('provider_received', 'Received by the provider'),

  rejectedByGateway('rejected_by_gateway', 'Not accepted for submission'),
  failed('failed', 'Could not be sent'),

  /// The request left and its fate is not known. Never a failure.
  unknown('unknown', 'Delivery not confirmed'),

  unavailable('unavailable', 'Submission not available'),

  /// A simulated attempt. Its own outcome rather than a flag, so no screen
  /// can mistake it for a real one by forgetting to check a boolean.
  simulated('simulated', 'Simulated — not sent to any provider');

  const SubmissionOutcome(this.id, this.label);
  final String id;
  final String label;

  static SubmissionOutcome fromId(String? id) => J.enumById(
    SubmissionOutcome.values,
    id,
    (o) => o.id,

    // An unknown outcome is never taken for a delivery.
    SubmissionOutcome.unavailable,
  );

  bool get isWorking => this == submitting;
}

/// Where an application would go, or went.
class SubmissionDestination {
  const SubmissionDestination({
    this.provider,
    this.displayName,
    this.role = 'none',
    this.isSimulated = false,
  });

  final String? provider;

  /// The name a customer may be shown. Null when there is nothing honest to
  /// display.
  final String? displayName;

  /// Its contractual role. A gateway is not a lender, and the UI says so.
  final String role;

  final bool isSimulated;

  static SubmissionDestination fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return const SubmissionDestination();

    return SubmissionDestination(
      provider: J.strOrNull(raw['provider']),
      displayName: J.strOrNull(raw['display_name']),
      role: J.str(raw['role'], 'none'),
      isSimulated: J.boolean(raw['is_simulated']),
    );
  }
}

/// The application, as FynnEdge holds it.
class SubmissionApplication {
  const SubmissionApplication({
    required this.id,
    required this.reference,
    required this.status,
    required this.statusLabel,
  });

  final String id;

  /// FynnEdge's own reference. Never replaced by a provider's.
  final String reference;

  final String status;
  final String statusLabel;

  static SubmissionApplication fromJson(Object? raw) {
    final map = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};

    return SubmissionApplication(
      id: J.str(map['id']),
      reference: J.str(map['reference']),
      status: J.str(map['status']),
      statusLabel: J.str(map['status_label']),
    );
  }
}

/// What FynnEdge knows about one application's external submission.
class ApplicationSubmission {
  const ApplicationSubmission({
    required this.application,
    required this.outcome,
    required this.destination,
    this.providerReceived = false,
    this.isSimulated = false,
    this.attempt,
    this.attemptedAt,
    this.providerReference,
    this.reason,
    this.message,
    this.rejectionReason,
    this.canRetry = false,
    this.needsReconciliation = false,
    this.disclaimer,
  });

  final SubmissionApplication application;
  final SubmissionOutcome outcome;
  final SubmissionDestination destination;

  /// The single field that means an external party holds this application.
  /// False for every simulated attempt, and for every outcome but one.
  final bool providerReceived;

  /// True when nothing left FynnEdge. Server-owned.
  final bool isSimulated;

  final int? attempt;
  final DateTime? attemptedAt;

  /// The provider's own reference, alongside FynnEdge's rather than instead
  /// of it.
  final String? providerReference;

  final String? reason;
  final String? message;
  final String? rejectionReason;

  /// Whether the customer may safely send it again. False after an unknown
  /// outcome: a provider may already hold a copy.
  final bool canRetry;

  final bool needsReconciliation;
  final String? disclaimer;

  bool get needsConsent => reason == 'submission_consent_required';

  bool get isUnavailable => outcome == SubmissionOutcome.unavailable;

  bool get hasBeenAttempted =>
      outcome != SubmissionOutcome.notAttempted &&
      outcome != SubmissionOutcome.unavailable;

  factory ApplicationSubmission.fromJson(Map<String, dynamic> json) {
    final submission = J.map(json['submission']);

    return ApplicationSubmission(
      application: SubmissionApplication.fromJson(json['application']),
      outcome: SubmissionOutcome.fromId(J.strOrNull(submission['outcome'])),
      destination: SubmissionDestination.fromJson(json['destination']),
      providerReceived: J.boolean(submission['provider_received']),
      isSimulated: J.boolean(submission['is_simulated']),
      attempt: J.intOrNull(submission['attempt']),
      attemptedAt: J.date(submission['attempted_at']),
      providerReference: J.strOrNull(submission['provider_reference']),
      reason: J.strOrNull(submission['reason']),
      message: J.strOrNull(submission['message']),
      rejectionReason: J.strOrNull(submission['rejection_reason']),
      canRetry: J.boolean(submission['can_retry']),
      needsReconciliation: J.boolean(submission['needs_reconciliation']),
      disclaimer: J.strOrNull(json['disclaimer']),
    );
  }
}
