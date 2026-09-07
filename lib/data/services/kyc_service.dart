import '../models/kyc.dart';
import 'api_client.dart';
import 'api_config.dart';

/// Asking FynnEdge to have an identity document checked.
///
/// NO LIVE KYC PROVIDER IS CONNECTED TO FYNNEDGE. The API's default driver
/// is `none`, and the mock implementation below reports exactly that. When a
/// real provider exists, only the server changes; this interface and
/// everything above it stay as they are.
abstract class KycService {
  /// What FynnEdge already knows. Never causes a provider call, so opening a
  /// screen cannot cost the customer a charge.
  Future<KycVerification> statusFor(String documentId);

  /// Asks for a check, because the customer asked.
  Future<KycVerification> verify(String documentId, {bool force = false});

  /// What the customer decided about a difference.
  Future<KycVerification> resolve(
    String documentId, {
    required String field,
    required ResolutionDecision decision,
  });
}

/// The wording the API uses, mirrored so mock mode says the same thing.
class VerificationUnavailable {
  const VerificationUnavailable._();

  static const String reason = 'verification_not_configured';

  static const String message =
      'Identity verification is not available yet. FynnEdge is not connected '
      'to a verification service, so nothing about your document has been '
      'checked.';
}

/// Mock mode has no verification service, and says so.
///
/// It deliberately does not simulate a pass. A synthetic "verified" on a
/// customer's screen is indistinguishable from a real one, and a
/// verification is precisely the kind of claim that must never be invented.
class MockKycService implements KycService {
  const MockKycService();

  @override
  Future<KycVerification> statusFor(String documentId) async {
    await ApiConfig.pauseFast();
    return _unavailable(documentId);
  }

  @override
  Future<KycVerification> verify(String documentId, {bool force = false}) async {
    await ApiConfig.pause();
    return _unavailable(documentId);
  }

  @override
  Future<KycVerification> resolve(
    String documentId, {
    required String field,
    required ResolutionDecision decision,
  }) async {
    await ApiConfig.pauseFast();

    // There is nothing to resolve: nothing checked the document.
    throw CapabilityUnavailableException(
      VerificationUnavailable.message,
      reason: VerificationUnavailable.reason,
    );
  }

  KycVerification _unavailable(String documentId) => KycVerification(
    documentId: documentId,
    status: VerificationStatus.unavailable,
    reason: VerificationUnavailable.reason,
    message: VerificationUnavailable.message,
  );
}

class ApiKycService implements KycService {
  ApiKycService(this._api);
  final ApiClient _api;

  @override
  Future<KycVerification> statusFor(String documentId) async =>
      KycVerification.fromJson(
        await _api.get('/documents/$documentId/kyc') as Map<String, dynamic>,
      );

  @override
  Future<KycVerification> verify(
    String documentId, {
    bool force = false,
  }) async {
    try {
      // No provider, no scenario, no outcome, no sample flag: all of that
      // is the server's, and sending it would change nothing.
      return KycVerification.fromJson(
        await _api.post(
              '/documents/$documentId/kyc',
              body: {'force': force},
            )
            as Map<String, dynamic>,
      );
    } on CapabilityUnavailableException catch (e) {
      // 501 is the API saying it cannot do this, which is an answer rather
      // than a failure — and specifically not a finding about the customer.
      return KycVerification(
        documentId: documentId,
        status: VerificationStatus.unavailable,
        reason: e.reason ?? VerificationUnavailable.reason,
        message: e.message,
      );
    }
  }

  @override
  Future<KycVerification> resolve(
    String documentId, {
    required String field,
    required ResolutionDecision decision,
  }) async => KycVerification.fromJson(
    await _api.post(
          '/documents/$documentId/kyc/resolve',
          body: {'field': field, 'decision': decision.id},
        )
        as Map<String, dynamic>,
  );
}
