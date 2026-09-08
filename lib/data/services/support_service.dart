import '../../core/utils/clock.dart';
import '../models/support.dart';
import 'api_client.dart';
import 'api_config.dart';

abstract class SupportService {
  Future<List<SupportCategoryOption>> getCategories();
  Future<List<SupportCase>> getCases();
  Future<SupportCase> getCase(String id);
  Future<SupportCase> createCase(SupportRequestDraft draft);
  Future<SupportCase> addMessage(String id, String body);
  Future<SupportCase> closeCase(String id);
}

/// Mock mode keeps its own small store of requests.
///
/// A customer in mock mode can raise a request and see it, because that is
/// the journey the screen exists for. What it never does is answer them:
/// there is no fabricated advisor reply and no case that walks itself to
/// "in progress", because NO ADVISOR SYSTEM IS CONNECTED and a mock that
/// pretended otherwise would be showing a customer something the product
/// cannot do.
class MockSupportService implements SupportService {
  MockSupportService();

  final List<SupportCase> _cases = [];
  int _next = 1;

  static const List<SupportCategoryOption> _categories = [
    SupportCategoryOption(
      id: 'submission_status',
      label: 'Application status',
      description: 'Where an application has got to, and what happens next.',
    ),
    SupportCategoryOption(
      id: 'application',
      label: 'Application help',
      description: 'Something about an application you started.',
    ),
    SupportCategoryOption(
      id: 'documents',
      label: 'Document help',
      description: 'A document that will not upload, or was not accepted.',
    ),
    SupportCategoryOption(
      id: 'financial_guidance',
      label: 'Financial guidance',
      description: 'Whether borrowing makes sense for you right now.',
    ),
    SupportCategoryOption(
      id: 'account',
      label: 'Account help',
      description: 'Signing in, your details, or closing your account.',
    ),
    SupportCategoryOption(
      id: 'technical',
      label: 'Technical issue',
      description: 'Something in the app is not working.',
    ),
    SupportCategoryOption(
      id: 'general',
      label: 'Something else',
      description: 'Anything that does not fit the rest.',
    ),
  ];

  @override
  Future<List<SupportCategoryOption>> getCategories() async {
    await ApiConfig.pauseFast();
    return _categories;
  }

  @override
  Future<List<SupportCase>> getCases() async {
    await ApiConfig.pause();
    return List.unmodifiable(_cases.reversed);
  }

  @override
  Future<SupportCase> getCase(String id) async {
    await ApiConfig.pauseFast();
    return _cases.firstWhere((c) => c.id == id);
  }

  @override
  Future<SupportCase> createCase(SupportRequestDraft draft) async {
    await ApiConfig.pause();

    final id = '${_next++}';
    final label = _categories
        .firstWhere(
          (c) => c.id == draft.category,
          orElse: () => _categories.last,
        )
        .label;

    final created = SupportCase(
      id: id,
      reference: 'FE-SUP-${AppClock.now().year}-${id.padLeft(6, '0')}',
      category: draft.category,
      categoryLabel: label,
      status: SupportCaseStatus.open,
      statusLabel: 'Open',
      statusDescription:
          'Your request has been recorded. We will come back to you.',
      isOpen: true,
      acceptsMessages: true,
      priority: 'normal',
      subject: draft.subject,
      description: draft.description,
      createdAt: AppClock.now(),
      timeline: [
        SupportEvent(
          label: 'Request created',
          source: 'customer',
          occurredAt: AppClock.now(),
        ),
      ],
    );

    _cases.add(created);
    return created;
  }

  @override
  Future<SupportCase> addMessage(String id, String body) async {
    await ApiConfig.pauseFast();
    return getCase(id);
  }

  @override
  Future<SupportCase> closeCase(String id) async {
    await ApiConfig.pauseFast();
    return getCase(id);
  }
}

class ApiSupportService implements SupportService {
  ApiSupportService(this._api);
  final ApiClient _api;

  @override
  Future<List<SupportCategoryOption>> getCategories() async =>
      (await _api.get('/support/categories') as List)
          .map((e) => SupportCategoryOption.fromJson(e as Map<String, dynamic>))
          .toList();

  @override
  Future<List<SupportCase>> getCases() async =>
      (await _api.get('/support/cases') as List)
          .map((e) => SupportCase.fromJson(e as Map<String, dynamic>))
          .toList();

  @override
  Future<SupportCase> getCase(String id) async => SupportCase.fromJson(
    await _api.get('/support/cases/$id') as Map<String, dynamic>,
  );

  @override
  Future<SupportCase> createCase(SupportRequestDraft draft) async =>
      SupportCase.fromJson(
        await _api.post(
              '/support/cases',
              body: <String, dynamic>{
                'category': draft.category,
                'subject': draft.subject,
                'description': draft.description,
                'context_type': ?draft.contextType,
                'context_id': ?draft.contextId,
              },
              // A double tap is one request. The server decides that, from
              // this header and a unique index.
              headers: draft.idempotencyKey == null
                  ? null
                  : {'Idempotency-Key': draft.idempotencyKey!},
            )
            as Map<String, dynamic>,
      );

  @override
  Future<SupportCase> addMessage(String id, String body) async =>
      SupportCase.fromJson(
        await _api.post('/support/cases/$id/messages', body: {'body': body})
            as Map<String, dynamic>,
      );

  @override
  Future<SupportCase> closeCase(String id) async => SupportCase.fromJson(
    await _api.post('/support/cases/$id/close') as Map<String, dynamic>,
  );
}
