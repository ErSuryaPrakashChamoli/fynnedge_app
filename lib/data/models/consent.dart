import 'json.dart';

/// Every consent FynnEdge knows about.
///
/// A type existing here does not mean it can be granted: [ConsentItem.isAvailable]
/// says whether the capability behind it exists yet. The server is the
/// authority on that, and refuses to record consent for anything it cannot do.
enum ConsentType {
  serviceTerms('service_terms'),
  privacyNotice('privacy_notice'),
  aiMemory('ai_memory'),
  creditBureauCheck('credit_bureau_check'),
  documentProcessing('document_processing'),
  identityVerification('identity_verification'),
  lenderDataSharing('lender_data_sharing'),
  aiTraining('ai_training'),
  marketingMessages('marketing_messages'),

  /// A type this build does not know. Never grantable.
  unknown('unknown');

  const ConsentType(this.id);
  final String id;

  static ConsentType fromId(String? id) =>
      J.enumById(ConsentType.values, id, (t) => t.id, ConsentType.unknown);
}

enum ConsentStatus {
  granted('granted', 'Granted'),
  withdrawn('withdrawn', 'Withdrawn');

  const ConsentStatus(this.id, this.label);
  final String id;
  final String label;

  static ConsentStatus? fromId(String? id) => id == null
      ? null
      : ConsentStatus.values.where((s) => s.id == id).firstOrNull;
}

/// One consent, and where this customer stands on it.
class ConsentItem {
  const ConsentItem({
    required this.type,
    required this.label,
    required this.description,
    required this.isRequired,
    required this.isAvailable,
    required this.isGranted,
    this.unavailableReason,
    this.currentVersion,
    this.grantedVersion,
    this.status,
    this.needsReconfirmation = false,
    this.decidedAt,
  });

  final ConsentType type;
  final String label;
  final String description;

  /// Part of using FynnEdge at all. Cannot be withdrawn from this screen.
  final bool isRequired;

  /// False where the capability behind it does not exist yet.
  final bool isAvailable;
  final String? unavailableReason;

  final bool isGranted;
  final String? currentVersion;

  /// The version they actually agreed to, which may be an older one.
  final String? grantedVersion;
  final ConsentStatus? status;

  /// Granted, but under wording that has since been replaced.
  final bool needsReconfirmation;

  final DateTime? decidedAt;

  /// The switch can be moved: available, and not a required one already on.
  bool get isChangeable => isAvailable && !(isRequired && isGranted);

  factory ConsentItem.fromJson(Map<String, dynamic> json) => ConsentItem(
    type: ConsentType.fromId(J.strOrNull(json['type'])),
    label: J.str(json['label']),
    description: J.str(json['description']),
    isRequired: J.boolean(json['is_required']),
    isAvailable: J.boolean(json['is_available']),
    unavailableReason: J.strOrNull(json['unavailable_reason']),
    isGranted: J.boolean(json['is_granted']),
    currentVersion: J.strOrNull(json['current_version']),
    grantedVersion: J.strOrNull(json['granted_version']),
    status: ConsentStatus.fromId(J.strOrNull(json['status'])),
    needsReconfirmation: J.boolean(json['needs_reconfirmation']),
    decidedAt: J.date(json['decided_at']),
  );

  Map<String, dynamic> toJson() => {
    'type': type.id,
    'label': label,
    'description': description,
    'is_required': isRequired,
    'is_available': isAvailable,
    'unavailable_reason': unavailableReason,
    'is_granted': isGranted,
    'current_version': currentVersion,
    'granted_version': grantedVersion,
    'status': status?.id,
    'needs_reconfirmation': needsReconfirmation,
    'decided_at': decidedAt?.toIso8601String(),
  };

  ConsentItem copyWith({
    bool? isGranted,
    ConsentStatus? status,
    String? grantedVersion,
    bool? needsReconfirmation,
    DateTime? decidedAt,
  }) => ConsentItem(
    type: type,
    label: label,
    description: description,
    isRequired: isRequired,
    isAvailable: isAvailable,
    unavailableReason: unavailableReason,
    isGranted: isGranted ?? this.isGranted,
    currentVersion: currentVersion,
    grantedVersion: grantedVersion ?? this.grantedVersion,
    status: status ?? this.status,
    needsReconfirmation: needsReconfirmation ?? this.needsReconfirmation,
    decidedAt: decidedAt ?? this.decidedAt,
  );
}

/// The catalogue plus what the customer still has to decide.
class ConsentState {
  const ConsentState({this.consents = const [], this.outstandingRequired = const []});

  final List<ConsentItem> consents;

  /// Required consents not yet granted under the current wording.
  final List<ConsentType> outstandingRequired;

  List<ConsentItem> get available =>
      consents.where((c) => c.isAvailable).toList(growable: false);

  List<ConsentItem> get unavailable =>
      consents.where((c) => !c.isAvailable).toList(growable: false);

  ConsentItem? byType(ConsentType type) {
    for (final consent in consents) {
      if (consent.type == type) return consent;
    }
    return null;
  }

  bool isGranted(ConsentType type) => byType(type)?.isGranted ?? false;

  factory ConsentState.fromJson(Map<String, dynamic> json) => ConsentState(
    consents: J.objects(json['consents'], ConsentItem.fromJson),
    outstandingRequired: J
        .strings(json['outstanding_required'])
        .map(ConsentType.fromId)
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'consents': consents.map((c) => c.toJson()).toList(),
    'outstanding_required': outstandingRequired.map((t) => t.id).toList(),
  };
}

/// One decision, as it appears in the customer's history.
///
/// Carries no database identifier: an internal key is not something the
/// customer needs, and it is not stable vocabulary.
class ConsentRecord {
  const ConsentRecord({
    required this.type,
    required this.label,
    required this.version,
    required this.status,
    required this.source,
    this.at,
  });

  final ConsentType type;
  final String label;
  final String version;
  final ConsentStatus status;
  final String source;
  final DateTime? at;

  factory ConsentRecord.fromJson(Map<String, dynamic> json) => ConsentRecord(
    type: ConsentType.fromId(J.strOrNull(json['type'])),
    label: J.str(json['label']),
    version: J.str(json['version']),
    status: ConsentStatus.fromId(J.strOrNull(json['status'])) ??
        ConsentStatus.withdrawn,
    source: J.str(json['source']),
    at: J.date(json['at']),
  );

  Map<String, dynamic> toJson() => {
    'type': type.id,
    'label': label,
    'version': version,
    'status': status.id,
    'status_label': status.label,
    'source': source,
    'at': at?.toIso8601String(),
  };
}
