import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/app/routes.dart';
import 'package:fynnedge/data/models/support.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/deep_links.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/data/services/support_service.dart';
import 'package:fynnedge/features/support/support_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';
import 'support/support_fixtures.dart';

/// Asking FynnEdge for help, as the app sees it.
///
/// NO ADVISOR SYSTEM OR CHAT PROVIDER IS CONNECTED. Nothing here reaches a
/// network and nothing replies; what is under test is what the app does
/// with what the API returns, including when it returns nothing.
class ScriptedSupportService implements SupportService {
  ScriptedSupportService();

  List<SupportCase> cases = [];
  Object? failList;
  Object? failCreate;

  int listCalls = 0;
  final List<SupportRequestDraft> created = [];
  final List<(String, String)> messages = [];
  final List<String> closed = [];

  @override
  Future<List<SupportCategoryOption>> getCategories() async {
    if (failList != null) throw failList!;
    return supportCategories;
  }

  @override
  Future<List<SupportCase>> getCases() async {
    listCalls++;
    if (failList != null) throw failList!;
    return cases;
  }

  @override
  Future<SupportCase> getCase(String id) async =>
      cases.firstWhere((c) => c.id == id);

  @override
  Future<SupportCase> createCase(SupportRequestDraft draft) async {
    if (failCreate != null) throw failCreate!;
    created.add(draft);

    final made = supportCase(
      id: '${cases.length + 1}',
      category: draft.category,
      subject: draft.subject,
    );
    cases = [made, ...cases];
    return made;
  }

  @override
  Future<SupportCase> addMessage(String id, String body) async {
    messages.add((id, body));
    return getCase(id);
  }

  @override
  Future<SupportCase> closeCase(String id) async {
    closed.add(id);
    return getCase(id);
  }
}

Future<ProviderContainer> containerWith(SupportService service) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      supportServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

Future<SupportHomeState> settled(ProviderContainer c) async {
  c.read(supportControllerProvider);
  await Future<void>.delayed(Duration.zero);
  return c.read(supportControllerProvider);
}

void main() {
  setUpAll(initUnitTestEnvironment);

  group('the support home', () {
    test('a customer who has asked nothing is not shown an error', () async {
      final state = await settled(await containerWith(ScriptedSupportService()));

      expect(state.loading, isFalse);
      expect(state.isEmpty, isTrue);
      expect(state.loadError, isNull);

      // And the categories are still offered — the screen's whole purpose
      // is asking, which does not depend on having asked before.
      expect(state.categories, isNotEmpty);
    });

    test('requests are listed as the server ordered them', () async {
      final service = ScriptedSupportService()
        ..cases = [
          supportCase(id: '2', reference: 'FE-SUP-2026-000002'),
          supportCase(id: '1', reference: 'FE-SUP-2026-000001'),
        ];

      final state = await settled(await containerWith(service));

      expect(
        state.cases.map((c) => c.reference),
        ['FE-SUP-2026-000002', 'FE-SUP-2026-000001'],
      );
    });

    test('a failure is an error with a retry, and the session survives', () async {
      final service = ScriptedSupportService()..failList = NetworkException();
      final c = await containerWith(service);

      final state = await settled(c);

      expect(state.loadError, isNotNull);
      expect(state.loading, isFalse);

      // Offline is not signed out. Nothing here clears a token.
      service.failList = null;
      service.cases = [supportCase()];

      await c.read(supportControllerProvider.notifier).load();

      expect(c.read(supportControllerProvider).loadError, isNull);
      expect(c.read(supportControllerProvider).cases, hasLength(1));
    });
  });

  group('raising a request', () {
    test('the context travels with it', () async {
      final service = ScriptedSupportService();
      final c = await containerWith(service);
      await settled(c);

      await c.read(supportControllerProvider.notifier).create(
        const SupportRequestDraft(
          category: 'submission_status',
          subject: 'Help with application submission status',
          description: 'I am not sure whether my application was received.',
          contextType: 'application',
          contextId: '42',
          idempotencyKey: 'one-attempt',
        ),
      );

      final draft = service.created.single;

      // What the server checks ownership of. Nothing about the screen's
      // state travels beyond these two fields.
      expect(draft.contextType, 'application');
      expect(draft.contextId, '42');
      expect(draft.idempotencyKey, 'one-attempt');
    });

    test('the list refreshes so the new request is there', () async {
      final service = ScriptedSupportService();
      final c = await containerWith(service);
      await settled(c);

      await c.read(supportControllerProvider.notifier).create(
        const SupportRequestDraft(
          category: 'general',
          subject: 'A question about my account',
          description: 'I would like to understand how this works.',
        ),
      );

      expect(c.read(supportControllerProvider).cases, hasLength(1));
    });

    test('a request that could not be sent returns nothing, not a crash', () async {
      final service = ScriptedSupportService()..failCreate = NetworkException();
      final c = await containerWith(service);
      await settled(c);

      final made = await c.read(supportControllerProvider.notifier).create(
        const SupportRequestDraft(
          category: 'general',
          subject: 'A question about my account',
          description: 'I would like to understand how this works.',
        ),
      );

      expect(made, isNull);
      expect(c.read(supportControllerProvider).cases, isEmpty);
    });
  });

  group('failures the customer is told apart', () {
    test('each API failure maps to its own thing to say', () {
      expect(
        SupportFailure.from(RateLimitedException('slow down')),
        SupportFailure.tooMany,
      );
      expect(SupportFailure.from(NetworkException()), SupportFailure.offline);
      expect(
        SupportFailure.from(ApiException('closed', statusCode: 409)),
        SupportFailure.caseClosed,
      );
      expect(
        SupportFailure.from(ApiException('invalid', statusCode: 422)),
        SupportFailure.invalid,
      );
      expect(
        SupportFailure.from(ApiException('boom', statusCode: 500)),
        SupportFailure.other,
      );
    });
  });

  group('deep links', () {
    test('a support case link resolves to the case', () {
      expect(
        DeepLinks.routeFor('fynnedge://support/cases/7'),
        Routes.supportCase('7'),
      );
      expect(DeepLinks.routeFor('fynnedge://support'), Routes.support);
    });

    test('a link to nowhere opens nothing', () {
      for (final link in [
        'fynnedge://support/cases/abc',
        'fynnedge://support/cases',
        'fynnedge://support/cases/0',
        'fynnedge://support/cases/1/close',
        'fynnedge://support/../admin',
      ]) {
        expect(DeepLinks.routeFor(link), isNull, reason: link);
      }
    });
  });

  group('routes carry context', () {
    test('the request form knows what it was opened from', () {
      expect(
        Routes.supportNew(
          category: 'submission_status',
          contextType: 'application',
          contextId: '42',
        ),
        '/support/new?category=submission_status&context_type=application&context_id=42',
      );

      // And with nothing to attach, it is just the form.
      expect(Routes.supportNew(), '/support/new');
    });
  });

  group('mock mode', () {
    test('a request can be raised and read back', () async {
      final service = MockSupportService();

      expect(await service.getCases(), isEmpty);

      final made = await service.createCase(
        const SupportRequestDraft(
          category: 'general',
          subject: 'A question about my account',
          description: 'I would like to understand how this works.',
        ),
      );

      expect(made.reference, startsWith('FE-SUP-'));
      expect(await service.getCases(), hasLength(1));
    });

    test('nothing ever replies', () async {
      final service = MockSupportService();

      final made = await service.createCase(
        const SupportRequestDraft(
          category: 'general',
          subject: 'A question about my account',
          description: 'I would like to understand how this works.',
        ),
      );

      /*
       * NO ADVISOR SYSTEM IS CONNECTED. A mock that fabricated a reply
       * would be showing a customer something the product cannot do — and
       * a fabricated reply about their money is the worst kind.
       */
      expect(made.messages, isEmpty);
      expect(made.status, SupportCaseStatus.open);

      final later = await service.getCase(made.id);
      expect(later.messages, isEmpty);
      expect(later.status, SupportCaseStatus.open);
    });
  });
}
