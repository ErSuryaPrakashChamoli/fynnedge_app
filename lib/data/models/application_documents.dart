import 'json.dart';

/// Where one required document stands for one application.
///
/// Deliberately not a boolean. None of these states says anything about a
/// lender: a document can be [ready] and have been seen by nobody outside
/// FynnEdge, which is exactly the situation today.
enum RequirementStatus {
  missing('missing', 'Not added yet'),

  /// Chosen, and not yet confirmed by the customer.
  available('available', 'Needs your confirmation'),

  /// Something changed and the customer needs to look again.
  needsReview('needs_review', 'Needs your review'),

  /// The customer has confirmed this is the document to use.
  ready('ready', 'Ready for your application'),

  /// The customer looked and said this one will not do.
  notSuitable('not_suitable', 'Marked as unsuitable');

  const RequirementStatus(this.id, this.label);
  final String id;
  final String label;

  static RequirementStatus fromId(String? id) => J.enumById(
    RequirementStatus.values,
    id,
    (s) => s.id,

    // An unknown status is never taken for a ready one.
    RequirementStatus.missing,
  );

  bool get isReady => this == ready;
  bool get needsAttention => this != ready;
}

/// The document a customer chose, by the facts they recognise it by.
///
/// No storage key, no path, no URL. The id is here because reading the file
/// goes through FynnVault's own authenticated route, which remains the only
/// way to open one.
class ChosenDocument {
  const ChosenDocument({
    required this.id,
    required this.name,
    required this.type,
    this.sizeBytes,
    this.storedAt,
  });

  final String id;
  final String name;
  final String type;
  final int? sizeBytes;
  final DateTime? storedAt;

  static ChosenDocument? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;

    return ChosenDocument(
      id: J.str(raw['id']),
      name: J.str(raw['name']),
      type: J.str(raw['type']),
      sizeBytes: J.intOrNull(raw['size_bytes']),
      storedAt: J.date(raw['stored_at']),
    );
  }
}

/// One requirement, and whatever the customer put in it.
class ChecklistItem {
  const ChecklistItem({
    required this.code,
    required this.title,
    required this.description,
    required this.documentType,
    required this.documentTypeLabel,
    required this.required,
    required this.multiple,
    required this.status,
    required this.blocksReadiness,
    this.action,
    this.document,
    this.confirmedAt,
    this.notice,
  });

  final String code;
  final String title;
  final String description;

  /// Which vault type fills it, so the picker offers the right documents
  /// rather than everything the customer owns.
  final String documentType;
  final String documentTypeLabel;

  final bool required;
  final bool multiple;

  final RequirementStatus status;

  /// Whether this requirement blocks the application. Stated by the server,
  /// never worked out here from `required` and `status`.
  final bool blocksReadiness;

  final String? action;
  final ChosenDocument? document;
  final DateTime? confirmedAt;

  /// Why the customer is being asked to look again — a document that is
  /// gone, or one whose contents changed after they confirmed it.
  final String? notice;

  static ChecklistItem fromJson(Map<String, dynamic> json) => ChecklistItem(
    code: J.str(json['code']),
    title: J.str(json['title']),
    description: J.str(json['description']),
    documentType: J.str(json['document_type']),
    documentTypeLabel: J.str(json['document_type_label']),
    required: J.boolean(json['required']),
    multiple: J.boolean(json['multiple']),
    status: RequirementStatus.fromId(J.strOrNull(json['status'])),
    blocksReadiness: J.boolean(json['blocks_readiness']),
    action: J.strOrNull(json['action']),
    document: ChosenDocument.fromJson(json['document']),
    confirmedAt: J.date(json['confirmed_at']),
    notice: J.strOrNull(json['notice']),
  );
}

/// Every requirement for one application, and whether it is ready.
class DocumentChecklist {
  const DocumentChecklist({
    required this.applicationReference,
    required this.ready,
    required this.requiredCount,
    required this.readyCount,
    required this.outstandingCount,
    required this.items,
    this.summary,
    this.disclaimer,
  });

  final String applicationReference;

  /// The server's answer, and the only authoritative one. This class mirrors
  /// nothing and recomputes nothing.
  final bool ready;

  final int requiredCount;
  final int readyCount;
  final int outstandingCount;

  final List<ChecklistItem> items;
  final String? summary;
  final String? disclaimer;

  List<ChecklistItem> get outstanding =>
      items.where((i) => i.blocksReadiness).toList();

  List<ChecklistItem> get optional => items.where((i) => !i.required).toList();

  static DocumentChecklist fromJson(Map<String, dynamic> json) =>
      DocumentChecklist(
        applicationReference: J.str(json['application_reference']),
        ready: J.boolean(json['ready']),
        requiredCount: J.integer(json['required_count']),
        readyCount: J.integer(json['ready_count']),
        outstandingCount: J.integer(json['outstanding_count']),
        items: J.objects(json['items'], ChecklistItem.fromJson),
        summary: J.strOrNull(json['summary']),
        disclaimer: J.strOrNull(json['disclaimer']),
      );
}

/// What the customer decided about a document they chose for an application.
///
/// Named apart from FynnScan's ReviewDecision on purpose: one is a judgement
/// about an extracted value, the other about which file to use.
enum ApplicationReviewDecision {
  accepted('accepted'),
  rejected('rejected');

  const ApplicationReviewDecision(this.id);
  final String id;
}
