import '../models/scan.dart';
import '../services/document_scan_service.dart';

/// The one place the app asks about reading a document.
///
/// Thin on purpose. The server's canonical extraction is authoritative:
/// there is no parsing, no amount interpretation and no confidence
/// arithmetic here, because a second implementation of any of those would be
/// a second answer to what a document says.
class ScanRepository {
  ScanRepository(this._service);
  final DocumentScanService _service;

  /// What FynnEdge already holds. Safe on any screen: it asks no provider,
  /// so it can never cost the customer a charge.
  Future<DocumentScan> status(String documentId) =>
      _service.statusFor(documentId);

  /// A reading, because the customer asked for one. Only ever called from an
  /// explicit action — never on screen load or refresh.
  Future<DocumentScan> scan(String documentId, {bool force = false}) =>
      _service.scan(documentId, force: force);

  Future<DocumentScan> confirm(
    String documentId,
    String field, {
    bool applyToProfile = false,
  }) => _service.review(
    documentId,
    field: field,
    decision: ReviewDecision.confirmed,
    applyToProfile: applyToProfile,
  );

  Future<DocumentScan> correct(
    String documentId,
    String field,
    String value, {
    bool applyToProfile = false,
  }) => _service.review(
    documentId,
    field: field,
    decision: ReviewDecision.edited,
    value: value,
    applyToProfile: applyToProfile,
  );

  Future<DocumentScan> reject(String documentId, String field) =>
      _service.review(
        documentId,
        field: field,
        decision: ReviewDecision.rejected,
      );
}
