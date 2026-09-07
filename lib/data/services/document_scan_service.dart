import '../models/scan.dart';
import 'api_client.dart';
import 'api_config.dart';

/// Asking FynnEdge to read a document, and answering about what it found.
///
/// NO LIVE DOCUMENT PROVIDER IS CONNECTED TO FYNNEDGE. The API's default
/// driver is `none`, and the mock implementation below reports exactly that.
/// When a real provider exists, only the server changes; this interface and
/// everything above it stay as they are.
abstract class DocumentScanService {
  /// What FynnEdge already knows. Never causes a provider call, so opening a
  /// screen cannot cost the customer a charge.
  Future<DocumentScan> statusFor(String documentId);

  /// Asks for a scan, because the customer asked.
  ///
  /// [force] is "scan again" — after a failure, a rejection, or a document
  /// whose file has changed.
  Future<DocumentScan> scan(String documentId, {bool force = false});

  /// The customer's answer about one extracted field.
  ///
  /// [applyToProfile] is a separate act from confirming. Confirming records
  /// that the document was read correctly; applying puts that figure in the
  /// customer's financial profile.
  Future<DocumentScan> review(
    String documentId, {
    required String field,
    required ReviewDecision decision,
    String? value,
    bool applyToProfile = false,
  });
}

/// The wording the API uses, mirrored so mock mode says the same thing.
class ScanUnavailable {
  const ScanUnavailable._();

  static const String reason = 'document_understanding_not_configured';

  static const String message =
      'Your document is stored safely, but FynnEdge is not connected to a '
      'document-reading service. Nothing has been extracted or interpreted.';
}

/// Mock mode has no provider, and says so.
///
/// It deliberately does not simulate an extraction. An invented salary in a
/// demo is indistinguishable, on screen, from a real reading of a real
/// customer's payslip — and there would be no honest way to label it.
class MockDocumentScanService implements DocumentScanService {
  const MockDocumentScanService();

  @override
  Future<DocumentScan> statusFor(String documentId) async {
    await ApiConfig.pauseFast();
    return _unavailable(documentId);
  }

  @override
  Future<DocumentScan> scan(String documentId, {bool force = false}) async {
    await ApiConfig.pause();
    return _unavailable(documentId);
  }

  @override
  Future<DocumentScan> review(
    String documentId, {
    required String field,
    required ReviewDecision decision,
    String? value,
    bool applyToProfile = false,
  }) async {
    await ApiConfig.pauseFast();

    // There is nothing to review: nothing read the document.
    throw CapabilityUnavailableException(
      ScanUnavailable.message,
      reason: ScanUnavailable.reason,
    );
  }

  DocumentScan _unavailable(String documentId) => DocumentScan(
    documentId: documentId,
    status: ScanStatus.unavailable,
    reason: ScanUnavailable.reason,
    message: ScanUnavailable.message,
  );
}

class ApiDocumentScanService implements DocumentScanService {
  ApiDocumentScanService(this._api);
  final ApiClient _api;

  @override
  Future<DocumentScan> statusFor(String documentId) async =>
      DocumentScan.fromJson(
        await _api.get('/documents/$documentId/scan') as Map<String, dynamic>,
      );

  @override
  Future<DocumentScan> scan(String documentId, {bool force = false}) async {
    try {
      // No provider, no scenario, no sample flag: all of that is the
      // server's, and sending it would change nothing.
      return DocumentScan.fromJson(
        await _api.post(
              '/documents/$documentId/scan',
              body: {'force': force},
            )
            as Map<String, dynamic>,
      );
    } on CapabilityUnavailableException catch (e) {
      // 501 is the API saying it cannot do this, which is an answer rather
      // than a failure. The document itself is fine.
      return DocumentScan(
        documentId: documentId,
        status: ScanStatus.unavailable,
        reason: e.reason ?? ScanUnavailable.reason,
        message: e.message,
      );
    }
  }

  @override
  Future<DocumentScan> review(
    String documentId, {
    required String field,
    required ReviewDecision decision,
    String? value,
    bool applyToProfile = false,
  }) async => DocumentScan.fromJson(
    await _api.post(
          '/documents/$documentId/scan/review',
          body: {
            'field': field,
            'decision': decision.id,
            'value': ?value,
            'apply_to_profile': applyToProfile,
          },
        )
        as Map<String, dynamic>,
  );
}
