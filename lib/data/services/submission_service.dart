import '../models/submission.dart';
import 'api_client.dart';
import 'api_config.dart';

/// Sending an application to an external provider.
///
/// NO LIVE LENDER SUBMISSION PROVIDER IS CONNECTED TO FYNNEDGE. The API's
/// default driver is `none`, and the mock implementation below reports
/// exactly that. When a real provider exists, only the server changes.
abstract class SubmissionService {
  /// Where the external submission stands. Never sends anything, so opening
  /// a screen cannot submit an application.
  Future<ApplicationSubmission> statusFor(String applicationId);

  /// Sends it, because the customer asked.
  Future<ApplicationSubmission> submit(String applicationId);
}

/// The wording the API uses, mirrored so mock mode says the same thing.
class SubmissionUnavailable {
  const SubmissionUnavailable._();

  static const String reason = 'lender_provider_unavailable';

  static const String message =
      'FynnEdge is not connected to an application provider yet, so this '
      'application has not been sent anywhere. It is saved here and nothing '
      'about it has failed.';
}

/// Mock mode has no submission provider, and says so.
///
/// It deliberately does not simulate a successful submission. A customer
/// shown a delivered application that was never sent is the exact harm this
/// module exists to prevent, and a demo build is where that mistake would
/// first be made.
class MockSubmissionService implements SubmissionService {
  const MockSubmissionService();

  @override
  Future<ApplicationSubmission> statusFor(String applicationId) async {
    await ApiConfig.pauseFast();
    return _unavailable(applicationId);
  }

  @override
  Future<ApplicationSubmission> submit(String applicationId) async {
    await ApiConfig.pause();
    return _unavailable(applicationId);
  }

  ApplicationSubmission _unavailable(String applicationId) =>
      ApplicationSubmission(
        application: SubmissionApplication(
          id: applicationId,
          reference: '',
          status: '',
          statusLabel: '',
        ),
        outcome: SubmissionOutcome.unavailable,
        destination: const SubmissionDestination(),
        reason: SubmissionUnavailable.reason,
        message: SubmissionUnavailable.message,
      );
}

class ApiSubmissionService implements SubmissionService {
  ApiSubmissionService(this._api);
  final ApiClient _api;

  @override
  Future<ApplicationSubmission> statusFor(String applicationId) async =>
      ApplicationSubmission.fromJson(
        await _api.get('/applications/$applicationId/submission')
            as Map<String, dynamic>,
      );

  @override
  Future<ApplicationSubmission> submit(String applicationId) async {
    try {
      // No body at all. The provider, the outcome and the simulated flag
      // are server- and provider-owned; sending them would change nothing.
      return ApplicationSubmission.fromJson(
        await _api.post('/applications/$applicationId/submission')
            as Map<String, dynamic>,
      );
    } on CapabilityUnavailableException catch (e) {
      // 501 is the API saying it cannot do this. An answer, not a failure,
      // and specifically not a failure of the customer's application.
      return ApplicationSubmission(
        application: SubmissionApplication(
          id: applicationId,
          reference: '',
          status: '',
          statusLabel: '',
        ),
        outcome: SubmissionOutcome.unavailable,
        destination: const SubmissionDestination(),
        reason: e.reason ?? SubmissionUnavailable.reason,
        message: e.message,
      );
    }
  }
}
