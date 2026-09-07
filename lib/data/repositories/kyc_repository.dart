import '../models/kyc.dart';
import '../services/kyc_service.dart';

/// The one place the app asks about identity verification.
///
/// Thin on purpose. The server's canonical result is authoritative: there is
/// no name comparison, no outcome derivation and no masking here, because a
/// second implementation of any of those would be a second answer to whether
/// a customer's identity was established.
class KycRepository {
  KycRepository(this._service);
  final KycService _service;

  /// What FynnEdge already holds. Asks no provider.
  Future<KycVerification> status(String documentId) =>
      _service.statusFor(documentId);

  /// A check, because the customer asked. Only ever called from an explicit
  /// action — never on screen load or refresh.
  Future<KycVerification> verify(String documentId, {bool force = false}) =>
      _service.verify(documentId, force: force);

  /// The customer keeps what is on their profile.
  Future<KycVerification> keepProfile(String documentId, String field) =>
      _service.resolve(
        documentId,
        field: field,
        decision: ResolutionDecision.keepProfile,
      );

  /// The customer corrects their profile to match the document.
  Future<KycVerification> updateProfile(String documentId, String field) =>
      _service.resolve(
        documentId,
        field: field,
        decision: ResolutionDecision.updateProfile,
      );
}
