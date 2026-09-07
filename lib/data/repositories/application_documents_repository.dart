import '../models/application_documents.dart';
import '../services/application_documents_service.dart';

/// The one place the app asks about an application's documents.
///
/// Thin on purpose. Readiness is the server's answer and is never recomputed
/// here — a second implementation of the rule would eventually disagree, and
/// a customer shown two answers to "am I ready?" stops believing either.
class ApplicationDocumentsRepository {
  ApplicationDocumentsRepository(this._service);
  final ApplicationDocumentsService _service;

  Future<DocumentChecklist> checklist(String applicationId) =>
      _service.checklistFor(applicationId);

  /// Chooses a vault document for a requirement. Choosing is not confirming.
  Future<DocumentChecklist> attach(
    String applicationId,
    String requirementCode,
    String documentId,
  ) => _service.attach(
    applicationId,
    requirementCode: requirementCode,
    documentId: documentId,
  );

  Future<DocumentChecklist> detach(
    String applicationId,
    String requirementCode,
  ) => _service.detach(applicationId, requirementCode: requirementCode);

  /// The customer confirming this is the document to use.
  Future<DocumentChecklist> confirm(
    String applicationId,
    String requirementCode,
  ) => _service.review(
    applicationId,
    requirementCode: requirementCode,
    decision: ApplicationReviewDecision.accepted,
  );

  /// The customer saying this document will not do.
  Future<DocumentChecklist> reject(
    String applicationId,
    String requirementCode,
  ) => _service.review(
    applicationId,
    requirementCode: requirementCode,
    decision: ApplicationReviewDecision.rejected,
  );
}
