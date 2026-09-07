import '../../core/utils/clock.dart';
import 'json.dart';

/// Where an application stands.
///
/// The first five are FynnEdge's own. The rest describe what a provider
/// decided, and nothing in this app may set them — they arrive only from a
/// backend relaying a real provider response.
enum ApplicationStatus {
  started('started', 'Started'),
  submitted('submitted', 'Submitted'),
  underReview('under_review', 'Under Review'),
  actionNeeded('action_needed', 'Action Needed'),
  cancelled('cancelled', 'Cancelled'),
  approved('approved', 'Approved'),
  declined('declined', 'Declined'),
  disbursed('disbursed', 'Disbursed');

  const ApplicationStatus(this.id, this.label);
  final String id;
  final String label;

  static ApplicationStatus fromId(String? id) => J.enumById(
    ApplicationStatus.values,
    id,
    (s) => s.id,
    ApplicationStatus.started,
  );

  /// True where the status reports a provider's decision, not FynnEdge's.
  bool get isProviderDecision =>
      this == underReview ||
      this == actionNeeded ||
      this == approved ||
      this == declined ||
      this == disbursed;

  bool get isTerminal =>
      this == approved ||
      this == declined ||
      this == disbursed ||
      this == cancelled;
}

/// Who is speaking in an application's history.
enum EventSource {
  /// FynnEdge, about something FynnEdge did.
  fynnedge('fynnedge'),

  /// A gateway that received the application but sent it nowhere.
  simulated('simulated'),

  /// A provider, about something they actually did.
  provider('provider');

  const EventSource(this.id);
  final String id;

  static EventSource fromId(String? id) =>
      J.enumById(EventSource.values, id, (s) => s.id, EventSource.fynnedge);
}

/// One thing that happened to an application.
class ApplicationEvent {
  const ApplicationEvent({
    required this.label,
    required this.source,
    this.detail = '',
    this.at,
  });

  final String label;
  final EventSource source;
  final String detail;
  final DateTime? at;

  bool get isSimulated => source == EventSource.simulated;

  factory ApplicationEvent.fromJson(Map<String, dynamic> json) =>
      ApplicationEvent(
        label: J.str(json['label']),
        source: EventSource.fromId(J.strOrNull(json['source'])),
        detail: J.str(json['detail']),
        at: J.date(json['at']),
      );

  Map<String, dynamic> toJson() => {
    'label': label,
    'source': source.id,
    'detail': detail,
    'at': at?.toIso8601String(),
  };
}

/// What the customer is asking a provider for.
///
/// The amount, tenure and product are exactly what they chose. The pricing is
/// what they were shown when they chose it, so a later rate change cannot
/// rewrite the offer they acted on.
/// The one sentence a customer is shown about where their application
/// stands.
///
/// Derived on the server from the two states that are actually true — the
/// application's own status and its submission outcome — and rendered here
/// verbatim. Deliberately not computed on this side: two surfaces deriving
/// it independently would eventually disagree about what a lender had said.
class CustomerStatus {
  const CustomerStatus({
    required this.code,
    required this.label,
    required this.description,
  });

  final String code;
  final String label;
  final String description;

  /// FynnEdge could not confirm whether the provider received the
  /// application. Not a failure, and never shown as one.
  bool get isUnconfirmed => code == 'submission_unconfirmed';

  /// A provider has actually said something about this application.
  bool get isFromProvider => const {
    'provider_received',
    'under_review',
    'action_needed',
    'approved',
    'declined',
    'disbursed',
    'rejected_by_gateway',
  }.contains(code);

  static const CustomerStatus unknown = CustomerStatus(
    code: 'started',
    label: 'Application started',
    description: '',
  );

  static CustomerStatus fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return unknown;

    return CustomerStatus(
      code: J.str(raw['code'], 'started'),
      label: J.str(raw['label']),
      description: J.str(raw['description']),
    );
  }
}

class LoanApplication {
  const LoanApplication({
    required this.id,
    required this.reference,
    required this.productId,
    required this.productName,
    required this.lender,
    required this.amount,
    required this.tenureMonths,
    required this.status,
    required this.createdAt,
    this.productCategory = '',
    this.interestRate = 0,
    this.emi = 0,
    this.totalInterest = 0,
    this.totalPayable = 0,
    this.processingFee = 0,
    this.projectedEmiRatio,
    this.matchCategory = '',
    this.statusLabel = '',
    this.nextAction = '',
    this.customerStatus = CustomerStatus.unknown,
    this.canSubmit = false,
    this.canCancel = false,
    this.isEditable = false,
    this.isSimulated = false,
    this.gateway,
    this.providerReference,
    this.acknowledgedAt,
    this.acknowledgements = const [],
    this.submittedAt,
    this.cancelledAt,
    this.updatedAt,
    this.events = const [],
  });

  final String id;
  final String reference;

  final String productId;
  final String productName;
  final String lender;
  final String productCategory;

  final double amount;
  final int tenureMonths;
  final double interestRate;

  final double emi;
  final double totalInterest;
  final double totalPayable;
  final double processingFee;
  final double? projectedEmiRatio;
  final String matchCategory;

  final ApplicationStatus status;
  final String statusLabel;
  final String nextAction;
  final bool canSubmit;
  final bool canCancel;
  final bool isEditable;

  /// True when nothing actually left FynnEdge.
  final bool isSimulated;
  final String? gateway;
  final String? providerReference;

  final DateTime? acknowledgedAt;
  final List<String> acknowledgements;

  final DateTime createdAt;
  final DateTime? submittedAt;
  final DateTime? cancelledAt;
  final DateTime? updatedAt;

  final List<ApplicationEvent> events;

  /// The server's one sentence about where this stands.
  final CustomerStatus customerStatus;

  String get label => statusLabel.isEmpty ? status.label : statusLabel;

  /// True once anything a provider said is on the record.
  bool get hasProviderEvents =>
      events.any((e) => e.source == EventSource.provider);

  factory LoanApplication.fromJson(Map<String, dynamic> json) =>
      LoanApplication(
        id: J.str(json['id']),
        reference: J.str(json['reference']),
        productId: J.str(json['product_id']),
        productName: J.str(json['product_name']),
        lender: J.str(json['lender']),
        productCategory: J.str(json['product_category']),
        amount: J.dbl(json['amount']),
        tenureMonths: J.integer(json['tenure_months']),
        interestRate: J.dbl(json['interest_rate']),
        emi: J.dbl(json['emi']),
        totalInterest: J.dbl(json['total_interest']),
        totalPayable: J.dbl(json['total_payable']),
        processingFee: J.dbl(json['processing_fee']),
        projectedEmiRatio: J.dblOrNull(json['projected_emi_ratio']),
        matchCategory: J.str(json['match_category']),
        status: ApplicationStatus.fromId(J.strOrNull(json['status'])),
        statusLabel: J.str(json['status_label']),
        nextAction: J.str(json['next_action']),
        customerStatus: CustomerStatus.fromJson(json['customer_status']),
        canSubmit: J.boolean(json['can_submit']),
        canCancel: J.boolean(json['can_cancel']),
        isEditable: J.boolean(json['is_editable']),
        isSimulated: J.boolean(json['is_simulated']),
        gateway: J.strOrNull(json['gateway']),
        providerReference: J.strOrNull(json['provider_reference']),
        acknowledgedAt: J.date(json['acknowledged_at']),
        acknowledgements: J.strings(json['acknowledgements']),
        createdAt: J.date(json['created_at']) ?? AppClock.now(),
        submittedAt: J.date(json['submitted_at']),
        cancelledAt: J.date(json['cancelled_at']),
        updatedAt: J.date(json['updated_at']),
        events: J.objects(json['events'], ApplicationEvent.fromJson),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'reference': reference,
    'product_id': productId,
    'product_name': productName,
    'lender': lender,
    'product_category': productCategory,
    'amount': amount,
    'tenure_months': tenureMonths,
    'interest_rate': interestRate,
    'emi': emi,
    'total_interest': totalInterest,
    'total_payable': totalPayable,
    'processing_fee': processingFee,
    'projected_emi_ratio': projectedEmiRatio,
    'match_category': matchCategory,
    'status': status.id,
    'status_label': statusLabel,
    'next_action': nextAction,
    'customer_status': {
      'code': customerStatus.code,
      'label': customerStatus.label,
      'description': customerStatus.description,
    },
    'can_submit': canSubmit,
    'can_cancel': canCancel,
    'is_editable': isEditable,
    'is_simulated': isSimulated,
    'gateway': gateway,
    'provider_reference': providerReference,
    'acknowledged_at': acknowledgedAt?.toIso8601String(),
    'acknowledgements': acknowledgements,
    'created_at': createdAt.toIso8601String(),
    'submitted_at': submittedAt?.toIso8601String(),
    'cancelled_at': cancelledAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'events': events.map((e) => e.toJson()).toList(),
  };

  LoanApplication copyWith({
    ApplicationStatus? status,
    CustomerStatus? customerStatus,
    String? statusLabel,
    String? nextAction,
    bool? canSubmit,
    bool? canCancel,
    bool? isEditable,
    bool? isSimulated,
    String? gateway,
    DateTime? acknowledgedAt,
    DateTime? submittedAt,
    DateTime? cancelledAt,
    DateTime? updatedAt,
    double? amount,
    int? tenureMonths,
    double? emi,
    double? totalInterest,
    double? totalPayable,
    double? processingFee,
    double? projectedEmiRatio,
    String? matchCategory,
    List<ApplicationEvent>? events,
  }) => LoanApplication(
    id: id,
    reference: reference,
    productId: productId,
    productName: productName,
    lender: lender,
    productCategory: productCategory,
    amount: amount ?? this.amount,
    tenureMonths: tenureMonths ?? this.tenureMonths,
    interestRate: interestRate,
    emi: emi ?? this.emi,
    totalInterest: totalInterest ?? this.totalInterest,
    totalPayable: totalPayable ?? this.totalPayable,
    processingFee: processingFee ?? this.processingFee,
    projectedEmiRatio: projectedEmiRatio ?? this.projectedEmiRatio,
    matchCategory: matchCategory ?? this.matchCategory,
    status: status ?? this.status,
    customerStatus: customerStatus ?? this.customerStatus,
    statusLabel: statusLabel ?? this.statusLabel,
    nextAction: nextAction ?? this.nextAction,
    canSubmit: canSubmit ?? this.canSubmit,
    canCancel: canCancel ?? this.canCancel,
    isEditable: isEditable ?? this.isEditable,
    isSimulated: isSimulated ?? this.isSimulated,
    gateway: gateway ?? this.gateway,
    providerReference: providerReference,
    acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
    acknowledgements: acknowledgements,
    createdAt: createdAt,
    submittedAt: submittedAt ?? this.submittedAt,
    cancelledAt: cancelledAt ?? this.cancelledAt,
    updatedAt: updatedAt ?? this.updatedAt,
    events: events ?? this.events,
  );
}
