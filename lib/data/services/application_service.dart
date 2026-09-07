import '../../core/utils/clock.dart';
import '../match/fynn_match_engine.dart';
import '../mock/mock_store.dart';
import '../models/application.dart';
import '../models/match.dart';
import 'api_client.dart';
import 'api_config.dart';

/// What the customer is starting an application for.
///
/// Carried as one value so no layer between the screen and the service can
/// substitute a default for the amount, the tenure or the product.
class ApplicationDraft {
  const ApplicationDraft({
    required this.productId,
    required this.amount,
    required this.tenureMonths,
  });

  final String productId;
  final double amount;
  final int tenureMonths;

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'amount': amount,
    'tenure_months': tenureMonths,
  };
}

/// The application lifecycle, from the app's side.
///
/// `idempotencyKey` is how a repeated tap is recognised as the same
/// intention. The busy state on a button is not enough on its own: a dropped
/// response, a retry or a second device would each create another
/// application without it.
abstract class ApplicationService {
  Future<List<LoanApplication>> getApplications();
  Future<LoanApplication> getApplication(String id);

  Future<LoanApplication> create(
    ApplicationDraft draft, {
    required String idempotencyKey,
  });

  Future<LoanApplication> update(
    String id, {
    double? amount,
    int? tenureMonths,
  });

  Future<LoanApplication> submit(String id);

  Future<LoanApplication> cancel(String id);
}

/// Mock mode's submission boundary, mirroring the backend's.
///
/// It acknowledges receipt and stops. It does not move an application to
/// Under Review, and it never approves or declines one: those are a
/// provider's to report, no provider has seen this, and a simulated decision
/// is indistinguishable from a real one to the person reading the screen.
class MockSubmissionGateway {
  const MockSubmissionGateway();

  static const String name = 'mock';

  static const String detail =
      'Recorded by FynnEdge. No provider has received this application: '
      'lender submission is not connected yet.';

  ApplicationEvent acknowledge() => ApplicationEvent(
    label: 'Submitted',
    source: EventSource.simulated,
    detail: detail,
    at: AppClock.now(),
  );
}

class MockApplicationService implements ApplicationService {
  MockApplicationService([MockStore? store])
    : _store = store ?? MockStore.instance;

  final MockStore _store;
  static const _gateway = MockSubmissionGateway();

  /// The wording acknowledged at submission. Kept identical to the backend's.
  static const List<String> acknowledgements = [
    'The information I have given FynnEdge is accurate to the best of my '
        'knowledge.',
    'I understand the provider decides whether to offer this loan, on their '
        'own terms, and that FynnEdge does not control that decision.',
  ];

  @override
  Future<List<LoanApplication>> getApplications() async {
    await ApiConfig.pause();
    return _store.applications;
  }

  @override
  Future<LoanApplication> getApplication(String id) async {
    await ApiConfig.pauseFast();
    return _find(id);
  }

  @override
  Future<LoanApplication> create(
    ApplicationDraft draft, {
    required String idempotencyKey,
  }) async {
    await ApiConfig.pause();

    // The same operation twice is one application, exactly as the API
    // behaves. A double tap must not create two.
    final existing = _store.applicationForKey(idempotencyKey);
    if (existing != null) return existing;

    final product = _store.productById(draft.productId);
    if (product == null) {
      throw ApiException('That product is no longer available.');
    }

    // Priced by the same engine the customer saw, at exactly what they chose.
    final match = fynnMatchEngine.evaluate(
      product: product,
      request: MatchRequest(
        amount: draft.amount,
        tenureMonths: draft.tenureMonths,
        purpose: FynnMatchEngine.purposeForCategory(product.category),
      ),
      financials: _store.snapshot,
      customerAge: _store.profile.age,
    );

    final now = AppClock.now();
    final application = LoanApplication(
      id: _store.nextApplicationId(),
      reference: _store.nextApplicationReference(),
      productId: product.id,
      productName: product.name,
      lender: product.lender,
      productCategory: product.category.id,
      amount: draft.amount,
      tenureMonths: draft.tenureMonths,
      interestRate: product.interestRate,
      emi: match.pricing.emi,
      totalInterest: match.pricing.totalInterest,
      totalPayable: match.pricing.totalPayable,
      processingFee: match.pricing.processingFee,
      projectedEmiRatio: match.pricing.projectedEmiRatio,
      matchCategory: match.category.id,
      status: ApplicationStatus.started,
      statusLabel: ApplicationStatus.started.label,

      // Mock mode has no server to derive this, so it is stated here
      // alongside the other fictional fields — and states the truth about
      // mock mode: nothing has been sent anywhere.
      customerStatus: const CustomerStatus(
        code: 'started',
        label: 'Application started',
        description: 'Your application is saved here and has not been sent '
            'to a provider.',
      ),

      nextAction: 'Review the details and submit when you are ready.',
      canSubmit: true,
      canCancel: true,
      isEditable: true,
      acknowledgements: acknowledgements,
      createdAt: now,
      updatedAt: now,
      events: [
        ApplicationEvent(
          label: 'Started',
          source: EventSource.fynnedge,
          detail: 'Application created from a matched product.',
          at: now,
        ),
      ],
    );

    _store.addApplication(application, idempotencyKey);
    return application;
  }

  @override
  Future<LoanApplication> update(
    String id, {
    double? amount,
    int? tenureMonths,
  }) async {
    await ApiConfig.pauseFast();
    final application = _find(id);

    if (!application.isEditable) {
      throw ApiException(
        'This application has been submitted and can no longer be changed.',
      );
    }

    final product = _store.productById(application.productId);
    if (product == null) {
      throw ApiException('That product is no longer available.');
    }

    final match = fynnMatchEngine.evaluate(
      product: product,
      request: MatchRequest(
        amount: amount ?? application.amount,
        tenureMonths: tenureMonths ?? application.tenureMonths,
        purpose: FynnMatchEngine.purposeForCategory(product.category),
      ),
      financials: _store.snapshot,
      customerAge: _store.profile.age,
    );

    final updated = application.copyWith(
      amount: amount ?? application.amount,
      tenureMonths: tenureMonths ?? application.tenureMonths,
      emi: match.pricing.emi,
      totalInterest: match.pricing.totalInterest,
      totalPayable: match.pricing.totalPayable,
      processingFee: match.pricing.processingFee,
      projectedEmiRatio: match.pricing.projectedEmiRatio,
      matchCategory: match.category.id,
      updatedAt: AppClock.now(),
    );

    _store.replaceApplication(updated);
    return updated;
  }

  @override
  Future<LoanApplication> submit(String id) async {
    await ApiConfig.pause();
    final application = _find(id);

    // Already sent: return it untouched rather than submitting again.
    if (application.status == ApplicationStatus.submitted) {
      return application;
    }

    if (!application.canSubmit) {
      throw ApiException('This application cannot be submitted.');
    }

    final now = AppClock.now();
    final submitted = application.copyWith(
      status: ApplicationStatus.submitted,
      statusLabel: ApplicationStatus.submitted.label,

      // Kept in step with the status, the way the server keeps it. A mock
      // whose headline sentence lags behind the application would show a
      // customer one thing and the record another.
      customerStatus: const CustomerStatus(
        code: 'ready_in_fynnedge',
        label: 'Ready in FynnEdge',
        description: 'Your application is complete here. It has not been '
            'sent to a provider.',
      ),
      nextAction:
          'Nothing to do. We will tell you when the provider responds.',
      canSubmit: false,
      canCancel: true,
      isEditable: false,
      isSimulated: true,
      gateway: MockSubmissionGateway.name,
      acknowledgedAt: now,
      submittedAt: now,
      updatedAt: now,
      events: [...application.events, _gateway.acknowledge()],
    );

    _store.replaceApplication(submitted);
    return submitted;
  }

  @override
  Future<LoanApplication> cancel(String id) async {
    await ApiConfig.pauseFast();
    final application = _find(id);

    if (!application.canCancel) {
      throw ApiException('This application can no longer be cancelled.');
    }

    final now = AppClock.now();
    final cancelled = application.copyWith(
      status: ApplicationStatus.cancelled,
      statusLabel: ApplicationStatus.cancelled.label,
      customerStatus: const CustomerStatus(
        code: 'cancelled',
        label: 'Application cancelled',
        description: 'You cancelled this application.',
      ),
      nextAction:
          'This application was cancelled. You can start a new one at any '
          'time.',
      canSubmit: false,
      canCancel: false,
      isEditable: false,
      cancelledAt: now,
      updatedAt: now,
      events: [
        ...application.events,
        ApplicationEvent(
          label: 'Cancelled',
          source: EventSource.fynnedge,
          detail: 'You withdrew this application.',
          at: now,
        ),
      ],
    );

    _store.replaceApplication(cancelled);
    return cancelled;
  }

  LoanApplication _find(String id) {
    final match = _store.applications.where((a) => a.id == id);
    if (match.isEmpty) {
      throw ApiException('That application could not be found.', statusCode: 404);
    }
    return match.first;
  }
}

class ApiApplicationService implements ApplicationService {
  ApiApplicationService(this._api);
  final ApiClient _api;

  @override
  Future<List<LoanApplication>> getApplications() async =>
      (await _api.get('/applications') as List)
          .map((e) => LoanApplication.fromJson(e as Map<String, dynamic>))
          .toList();

  @override
  Future<LoanApplication> getApplication(String id) async =>
      LoanApplication.fromJson(
        await _api.get('/applications/$id') as Map<String, dynamic>,
      );

  @override
  Future<LoanApplication> create(
    ApplicationDraft draft, {
    required String idempotencyKey,
  }) async => LoanApplication.fromJson(
    await _api.post(
          '/applications',
          body: draft.toJson(),
          headers: {'Idempotency-Key': idempotencyKey},
        )
        as Map<String, dynamic>,
  );

  @override
  Future<LoanApplication> update(
    String id, {
    double? amount,
    int? tenureMonths,
  }) async => LoanApplication.fromJson(
    await _api.put('/applications/$id', body: {
      'amount': ?amount,
      'tenure_months': ?tenureMonths,
    }) as Map<String, dynamic>,
  );

  @override
  Future<LoanApplication> submit(String id) async => LoanApplication.fromJson(
    await _api.post('/applications/$id/submit', body: {'acknowledged': true})
        as Map<String, dynamic>,
  );

  @override
  Future<LoanApplication> cancel(String id) async => LoanApplication.fromJson(
    await _api.post('/applications/$id/cancel') as Map<String, dynamic>,
  );
}
