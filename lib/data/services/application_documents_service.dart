import '../models/application_documents.dart';
import 'api_client.dart';
import 'api_config.dart';

/// Preparing an application's documents.
///
/// Nothing in this seam sends anything to anybody. Choosing and confirming
/// documents happens entirely inside FynnEdge; external submission is
/// Module 26's boundary, with its own consent.
abstract class ApplicationDocumentsService {
  Future<DocumentChecklist> checklistFor(String applicationId);

  /// Chooses one of the customer's vault documents for a requirement.
  /// Choosing is not confirming.
  Future<DocumentChecklist> attach(
    String applicationId, {
    required String requirementCode,
    required String documentId,
  });

  /// Removes the choice. The document itself stays in the vault.
  Future<DocumentChecklist> detach(
    String applicationId, {
    required String requirementCode,
  });

  /// The customer's decision: this is the document to use, or it is not.
  Future<DocumentChecklist> review(
    String applicationId, {
    required String requirementCode,
    required ApplicationReviewDecision decision,
  });
}

/// Mock mode, exercising every state a customer can reach.
///
/// Deliberately fictional and deliberately not all-green: a demo where
/// everything is ready would never show the states that matter — a document
/// that went missing, one whose contents changed, one the customer rejected.
///
/// Nothing here represents a lender. Readiness in mock mode means exactly
/// what it means everywhere else: the customer has what an application of
/// this kind needs, and nobody outside FynnEdge has seen any of it.
class MockApplicationDocumentsService implements ApplicationDocumentsService {
  MockApplicationDocumentsService();

  /// requirement code → current status, mutated by the mock actions so the
  /// flow can actually be walked in a demo.
  final Map<String, RequirementStatus> _states = {
    'identity': RequirementStatus.ready,
    'income': RequirementStatus.available,
    'bank': RequirementStatus.missing,
    'existing_loan': RequirementStatus.missing,
  };

  final Map<String, String> _names = {
    'identity': 'Sample PAN Card.pdf',
    'income': 'Sample Salary Slip.pdf',
  };

  @override
  Future<DocumentChecklist> checklistFor(String applicationId) async {
    await ApiConfig.pauseFast();
    return _build();
  }

  @override
  Future<DocumentChecklist> attach(
    String applicationId, {
    required String requirementCode,
    required String documentId,
  }) async {
    await ApiConfig.pauseFast();

    // Chosen, not confirmed — the same rule the API applies.
    _states[requirementCode] = RequirementStatus.available;
    _names[requirementCode] = 'Sample Document.pdf';

    return _build();
  }

  @override
  Future<DocumentChecklist> detach(
    String applicationId, {
    required String requirementCode,
  }) async {
    await ApiConfig.pauseFast();
    _states[requirementCode] = RequirementStatus.missing;
    _names.remove(requirementCode);

    return _build();
  }

  @override
  Future<DocumentChecklist> review(
    String applicationId, {
    required String requirementCode,
    required ApplicationReviewDecision decision,
  }) async {
    await ApiConfig.pauseFast();

    _states[requirementCode] = decision == ApplicationReviewDecision.accepted
        ? RequirementStatus.ready
        : RequirementStatus.notSuitable;

    return _build();
  }

  DocumentChecklist _build() {
    final specs = [
      ('identity', 'Identity document', 'identity', true),
      ('income', 'Income proof', 'income', true),
      ('bank', 'Bank statement', 'bank', true),
      ('existing_loan', 'Existing loan statement', 'loan', false),
    ];

    final items = <ChecklistItem>[];
    var ready = 0;
    var requiredCount = 0;

    for (final (code, title, type, isRequired) in specs) {
      final status = _states[code] ?? RequirementStatus.missing;
      final blocks = isRequired && !status.isReady;

      if (isRequired) {
        requiredCount++;
        if (status.isReady) ready++;
      }

      items.add(
        ChecklistItem(
          code: code,
          title: title,
          description: 'A sample requirement.',
          documentType: type,
          documentTypeLabel: type,
          required: isRequired,
          multiple: false,
          status: status,
          blocksReadiness: blocks,
          action: switch (status) {
            RequirementStatus.missing => 'Add from FynnVault',
            RequirementStatus.available => 'Confirm this document',
            RequirementStatus.needsReview => 'Check this document again',
            RequirementStatus.notSuitable => 'Choose another document',
            RequirementStatus.ready => null,
          },
          document: _names.containsKey(code)
              ? ChosenDocument(
                  id: 'mock_$code',
                  name: _names[code]!,
                  type: type,
                )
              : null,
        ),
      );
    }

    final allReady = items.every((i) => !i.blocksReadiness);

    return DocumentChecklist(
      applicationReference: 'FE-2026-000001',
      ready: allReady,
      requiredCount: requiredCount,
      readyCount: ready,
      outstandingCount: items.where((i) => i.blocksReadiness).length,
      items: items,
      summary: allReady
          ? 'Your documents are ready for this application. Nothing has been '
                'sent anywhere yet.'
          : 'Some documents still need your attention before this '
                'application is ready.',
      disclaimer:
          'Choosing and confirming documents prepares your application '
          'inside FynnEdge. It does not send them to any lender or provider, '
          'and no one outside FynnEdge has seen them.',
    );
  }
}

class ApiApplicationDocumentsService implements ApplicationDocumentsService {
  ApiApplicationDocumentsService(this._api);
  final ApiClient _api;

  @override
  Future<DocumentChecklist> checklistFor(String applicationId) async =>
      DocumentChecklist.fromJson(
        await _api.get('/applications/$applicationId/documents')
            as Map<String, dynamic>,
      );

  @override
  Future<DocumentChecklist> attach(
    String applicationId, {
    required String requirementCode,
    required String documentId,
  }) async => DocumentChecklist.fromJson(
    // No customer identity in the body: whose application and whose
    // document both come from the session.
    await _api.post(
          '/applications/$applicationId/documents',
          body: {
            'requirement_code': requirementCode,
            'document_id': documentId,
          },
        )
        as Map<String, dynamic>,
  );

  @override
  Future<DocumentChecklist> detach(
    String applicationId, {
    required String requirementCode,
  }) async => DocumentChecklist.fromJson(
    await _api.delete('/applications/$applicationId/documents/$requirementCode')
        as Map<String, dynamic>,
  );

  @override
  Future<DocumentChecklist> review(
    String applicationId, {
    required String requirementCode,
    required ApplicationReviewDecision decision,
  }) async => DocumentChecklist.fromJson(
    await _api.post(
          '/applications/$applicationId/documents/$requirementCode/review',
          body: {'decision': decision.id},
        )
        as Map<String, dynamic>,
  );
}
