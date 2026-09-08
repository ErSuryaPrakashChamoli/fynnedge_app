import '../../core/utils/clock.dart';
import 'json.dart';

/// What a customer can ask about.
///
/// Ids and labels both come from the API. The app does not keep its own
/// copy of the catalogue: a label spelled differently in two places is two
/// products as far as a customer is concerned.
class SupportCategoryOption {
  const SupportCategoryOption({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;

  factory SupportCategoryOption.fromJson(Map<String, dynamic> json) =>
      SupportCategoryOption(
        id: J.str(json['id']),
        label: J.str(json['label']),
        description: J.str(json['description']),
      );
}

/// Where a request has got to.
///
/// The label and the sentence under it come from the server, not from here.
/// A status the app has its own words for is a status the app can describe
/// differently from the API — and this is the part of the product that has
/// to be believable.
enum SupportCaseStatus {
  open,
  acknowledged,
  inProgress,
  waitingForCustomer,
  resolved,
  closed;

  String get id => switch (this) {
    SupportCaseStatus.inProgress => 'in_progress',
    SupportCaseStatus.waitingForCustomer => 'waiting_for_customer',
    _ => name,
  };

  /// Whether this is the one status where the customer has something to do.
  bool get needsCustomer => this == SupportCaseStatus.waitingForCustomer;
}

/// What a request is about, when it is about something in particular.
class SupportContext {
  const SupportContext({
    required this.type,
    required this.label,
    this.reference,
    this.statusLabel,
    this.productName,
  });

  final String type;
  final String label;

  /// The reference the customer already sees elsewhere, e.g. FE-2026-000042.
  final String? reference;

  /// Module 28's own sentence about that application. Never one written
  /// in the app.
  final String? statusLabel;

  final String? productName;

  factory SupportContext.fromJson(Map<String, dynamic> json) => SupportContext(
    type: J.str(json['type']),
    label: J.str(json['label']),
    reference: J.strOrNull(json['reference']),
    statusLabel: J.strOrNull(json['status_label']),
    productName: J.strOrNull(json['product_name']),
  );
}

/// Something said on a request.
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.fromCustomer,
    required this.body,
    required this.createdAt,
  });

  final String id;

  /// 'you' or 'fynnedge'. Never a person's name — there is nobody to name.
  final bool fromCustomer;

  final String body;
  final DateTime createdAt;

  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
    id: J.str(json['id']),
    fromCustomer: J.strOrNull(json['author']) == 'you',
    body: J.str(json['body']),
    createdAt: J.date(json['created_at']) ?? AppClock.now(),
  );
}

/// One thing that happened to a request.
class SupportEvent {
  const SupportEvent({
    required this.label,
    required this.source,
    required this.occurredAt,
  });

  final String label;
  final String source;
  final DateTime occurredAt;

  factory SupportEvent.fromJson(Map<String, dynamic> json) => SupportEvent(
    label: J.str(json['label']),
    source: J.str(json['source']),
    occurredAt: J.date(json['occurred_at']) ?? AppClock.now(),
  );
}

/// A customer's request for help.
class SupportCase {
  const SupportCase({
    required this.id,
    required this.reference,
    required this.category,
    required this.categoryLabel,
    required this.status,
    required this.statusLabel,
    required this.statusDescription,
    required this.isOpen,
    required this.acceptsMessages,
    required this.priority,
    required this.subject,
    required this.createdAt,
    this.description,
    this.context,
    this.messages = const [],
    this.timeline = const [],
    this.resolvedAt,
    this.closedAt,
  });

  final String id;

  /// What the customer quotes. The identifier they see, everywhere.
  final String reference;

  final String category;
  final String categoryLabel;

  final SupportCaseStatus status;

  /// The server's words for the status, and its sentence under them.
  final String statusLabel;
  final String statusDescription;

  final bool isOpen;
  final bool acceptsMessages;
  final String priority;
  final String subject;

  /// Present on the detail view only. A list does not carry every word of
  /// every request.
  final String? description;

  final SupportContext? context;
  final List<SupportMessage> messages;
  final List<SupportEvent> timeline;

  final DateTime createdAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;

  bool get isHighPriority => priority == 'high';

  factory SupportCase.fromJson(Map<String, dynamic> json) => SupportCase(
    id: J.str(json['id']),
    reference: J.str(json['reference']),
    category: J.str(json['category']),
    categoryLabel: J.str(json['category_label']),
    status: J.enumById(
      SupportCaseStatus.values,
      J.strOrNull(json['status']),
      (s) => s.id,
      // A status this build does not know renders as open rather than
      // failing to render. A newer server must not blank the screen.
      SupportCaseStatus.open,
    ),
    statusLabel: J.str(json['status_label']),
    statusDescription: J.str(json['status_description']),
    isOpen: J.boolean(json['is_open']),
    acceptsMessages: J.boolean(json['accepts_messages']),
    priority: J.str(json['priority']),
    subject: J.str(json['subject']),
    description: J.strOrNull(json['description']),
    context: json['context'] is Map<String, dynamic>
        ? SupportContext.fromJson(json['context'] as Map<String, dynamic>)
        : null,
    messages: (json['messages'] as List? ?? const [])
        .map((e) => SupportMessage.fromJson(e as Map<String, dynamic>))
        .toList(),
    timeline: (json['timeline'] as List? ?? const [])
        .map((e) => SupportEvent.fromJson(e as Map<String, dynamic>))
        .toList(),
    createdAt: J.date(json['created_at']) ?? AppClock.now(),
    resolvedAt: J.date(json['resolved_at']),
    closedAt: J.date(json['closed_at']),
  );
}

/// A request the customer is about to make.
///
/// Carries the context it came from, so support opened from an application
/// already knows which one. Nothing about the screen's state travels beyond
/// the two fields the API allowlists.
class SupportRequestDraft {
  const SupportRequestDraft({
    required this.category,
    required this.subject,
    required this.description,
    this.contextType,
    this.contextId,
    this.idempotencyKey,
  });

  final String category;
  final String subject;
  final String description;
  final String? contextType;
  final String? contextId;

  /// Stable for one attempt, so a double tap is one request.
  final String? idempotencyKey;
}
