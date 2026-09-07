import 'json.dart';

/// How far a document's understanding has got.
///
/// Which of these are reachable depends on what the server is connected to.
/// With no provider — the default — only [notStarted] and [unavailable]
/// occur.
///
/// The distinction that matters is [completed] against [needsReview]. A scan
/// is completed only when every field was read cleanly; anything partly
/// missing, uncertain or ambiguous is needsReview, so a customer is never
/// shown "read" over an extraction that is nothing of the kind.
enum ScanStatus {
  notStarted('not_started', 'Not scanned'),
  unavailable('unavailable', 'Not connected'),
  consentRequired('consent_required', 'Your permission needed'),
  queued('queued', 'Waiting to be read'),
  processing('processing', 'Reading'),
  completed('completed', 'Read'),
  needsReview('needs_review', 'Please check what we found'),
  failed('failed', 'Could not be read');

  const ScanStatus(this.id, this.label);
  final String id;
  final String label;

  static ScanStatus fromId(String? id) =>
      J.enumById(ScanStatus.values, id, (s) => s.id, ScanStatus.unavailable);

  /// True where a provider must have reported it.
  bool get requiresProvider =>
      this == queued ||
      this == processing ||
      this == completed ||
      this == needsReview ||
      this == failed;

  /// Whether there is an extraction to show.
  bool get hasExtraction => this == completed || this == needsReview;

  /// Whether the provider is still working.
  bool get isWorking => this == queued || this == processing;
}

/// How sure the provider was, on FynnEdge's own scale.
///
/// Deliberately not a number. A provider's 0.97 means whatever that
/// provider's model defines it to mean, and rendering it as "97%" would
/// invent both a precision and an interpretation nobody measured.
enum ConfidenceLevel {
  high('high', 'High confidence'),
  medium('medium', 'Worth checking'),
  low('low', 'Please check this'),

  /// The provider said nothing about how sure it was. Not the same as low.
  unavailable('unavailable', 'Confidence unknown');

  const ConfidenceLevel(this.id, this.label);
  final String id;
  final String label;

  static ConfidenceLevel fromId(String? id) => J.enumById(
    ConfidenceLevel.values,
    id,
    (c) => c.id,
    ConfidenceLevel.unavailable,
  );
}

/// What the customer said about an extracted value.
enum ReviewDecision {
  confirmed('confirmed', 'Confirmed by you'),
  edited('edited', 'Corrected by you'),
  rejected('rejected', 'Rejected by you');

  const ReviewDecision(this.id, this.label);
  final String id;
  final String label;

  static ReviewDecision? fromId(String? id) =>
      ReviewDecision.values.where((d) => d.id == id).firstOrNull;
}

/// Where in the document a value came from.
class FieldEvidence {
  const FieldEvidence({this.page, this.snippet, this.section});

  final int? page;
  final String? snippet;
  final String? section;

  bool get isEmpty => page == null && snippet == null && section == null;

  /// A sentence a customer can act on: where to look on their own copy.
  String get description {
    final parts = <String>[
      ?section,
      if (page != null) 'page $page',
    ];
    return parts.isEmpty ? 'In your document' : 'Found in ${parts.join(', ')}';
  }

  static FieldEvidence? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;

    final evidence = FieldEvidence(
      page: J.intOrNull(raw['page']),
      snippet: J.strOrNull(raw['snippet']),
      section: J.strOrNull(raw['section']),
    );

    return evidence.isEmpty ? null : evidence;
  }
}

/// One value FynnScan believes it found.
///
/// "Believes it found" is the point. A field carries what was read, how sure
/// the provider was, and where it came from — and nothing about whether it
/// is true. Whether it is true is the customer's answer, in [DocumentScan.reviews].
class ExtractedField {
  const ExtractedField({
    required this.key,
    required this.label,
    required this.value,
    required this.valueType,
    required this.confidence,
    required this.needsReview,
    this.amount,
    this.reviewReason,
    this.evidence,
  });

  final String key;
  final String label;

  /// As read. Null when the document did not show it.
  final String? value;

  /// money | text | period.
  final String valueType;

  /// In rupees, when this is money. Parsed by the server, never here.
  final num? amount;

  final ConfidenceLevel confidence;
  final bool needsReview;
  final String? reviewReason;
  final FieldEvidence? evidence;

  bool get isMoney => valueType == 'money';
  bool get isPresent => value != null;

  static ExtractedField fromJson(Map<String, dynamic> json) => ExtractedField(
    key: J.str(json['key']),
    label: J.str(json['label']),
    value: J.strOrNull(json['value']),
    valueType: J.str(json['value_type'], 'text'),
    amount: J.dblOrNull(json['amount']),
    confidence: ConfidenceLevel.fromId(J.strOrNull(json['confidence'])),
    needsReview: J.boolean(json['needs_review']),
    reviewReason: J.strOrNull(json['review_reason']),
    evidence: FieldEvidence.fromJson(json['evidence']),
  );
}

/// The customer's standing answer about one field.
class FieldReview {
  const FieldReview({
    required this.fieldKey,
    required this.decision,
    required this.appliedToProfile,
    this.extractedValue,
    this.customerValue,
    this.decidedAt,
  });

  final String fieldKey;
  final ReviewDecision decision;
  final bool appliedToProfile;

  /// Both survive. What the document appeared to say and what the customer
  /// says it is are two facts, not one correcting the other.
  final String? extractedValue;
  final String? customerValue;

  final DateTime? decidedAt;

  bool get wasCorrected =>
      decision == ReviewDecision.edited && extractedValue != customerValue;

  static FieldReview? fromJson(Map<String, dynamic> json) {
    final decision = ReviewDecision.fromId(J.strOrNull(json['decision']));
    if (decision == null) return null;

    return FieldReview(
      fieldKey: J.str(json['field_key']),
      decision: decision,
      appliedToProfile: J.boolean(json['applied_to_profile']),
      extractedValue: J.strOrNull(json['extracted_value']),
      customerValue: J.strOrNull(json['customer_value']),
      decidedAt: J.date(json['decided_at']),
    );
  }
}

/// What FynnEdge knows about reading one document.
class DocumentScan {
  const DocumentScan({
    required this.documentId,
    required this.status,
    this.scanId,
    this.provider,
    this.reason,
    this.message,
    this.family,
    this.isSupported = false,
    this.schemaVersion,
    this.isSample = false,
    this.isStale = false,
    this.classificationMismatch = false,
    this.documentPeriod,
    this.startedAt,
    this.processedAt,
    this.extraction,
    this.reviews = const [],
    this.disclaimer,
  });

  final String documentId;
  final String? scanId;
  final ScanStatus status;
  final String? provider;
  final String? reason;
  final String? message;

  /// Which family this document belongs to, and whether FynnScan reads it.
  /// Stated by the server rather than inferred from an empty result.
  final String? family;
  final bool isSupported;
  final String? schemaVersion;

  /// True when a fictional provider produced this. Server-owned, and never
  /// something this app can change.
  final bool isSample;

  /// True when the file behind the document has changed since it was read.
  final bool isStale;

  /// True when the provider thought this was a different kind of document
  /// from the one the customer filed it as.
  final bool classificationMismatch;

  /// The period the document covers. Not when it was read.
  final String? documentPeriod;

  final DateTime? startedAt;
  final DateTime? processedAt;

  /// Null when nothing has been read. Never an empty list, which would read
  /// as a scan that ran and found nothing.
  final List<ExtractedField>? extraction;

  final List<FieldReview> reviews;
  final String? disclaimer;

  bool get isAvailable => status != ScanStatus.unavailable;
  bool get needsConsent => status == ScanStatus.consentRequired;

  bool get canScan =>
      isSupported &&
      (status == ScanStatus.notStarted ||
          status == ScanStatus.failed ||
          status == ScanStatus.completed ||
          status == ScanStatus.needsReview);

  List<ExtractedField> get fieldsToCheck =>
      extraction?.where((f) => f.needsReview).toList() ?? const [];

  FieldReview? reviewFor(String fieldKey) =>
      reviews.where((r) => r.fieldKey == fieldKey).firstOrNull;

  factory DocumentScan.fromJson(Map<String, dynamic> json) => DocumentScan(
    documentId: J.str(json['document_id']),
    scanId: J.strOrNull(json['scan_id']),
    status: ScanStatus.fromId(J.strOrNull(json['status'])),
    provider: J.strOrNull(json['provider']),
    reason: J.strOrNull(json['reason']),
    message: J.strOrNull(json['message']),
    family: J.strOrNull(json['family']),
    isSupported: J.boolean(json['is_supported']),
    schemaVersion: J.strOrNull(json['schema_version']),
    isSample: J.boolean(json['is_sample']),
    isStale: J.boolean(json['is_stale']),
    classificationMismatch: J.boolean(json['classification_mismatch']),
    documentPeriod: J.strOrNull(json['document_period']),
    startedAt: J.date(json['started_at']),
    processedAt: J.date(json['processed_at']),

    // Null and empty are different answers, so the distinction is kept.
    extraction: json['extraction'] == null
        ? null
        : J.objects(json['extraction'], ExtractedField.fromJson),

    reviews: J
        .list(json['reviews'])
        .map((e) => e is Map<String, dynamic> ? FieldReview.fromJson(e) : null)
        .whereType<FieldReview>()
        .toList(),

    disclaimer: J.strOrNull(json['disclaimer']),
  );
}
