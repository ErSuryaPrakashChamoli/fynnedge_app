import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/models/application_documents.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/application_documents_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/applications/documents/application_documents_card.dart';
import 'package:fynnedge/features/applications/documents/application_documents_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// Preparing an application's documents, on the customer's side.
///
/// Nothing here sends anything anywhere. LIVE LENDER DOCUMENT TRANSMISSION:
/// NO, and no state on this screen may suggest otherwise.
class ScriptedDocumentsService implements ApplicationDocumentsService {
  ScriptedDocumentsService(this.checklist);

  DocumentChecklist checklist;
  Object? failAction;

  int loadCalls = 0;
  int attachCalls = 0;
  int reviewCalls = 0;

  String? lastCode;
  String? lastDocumentId;
  ApplicationReviewDecision? lastDecision;

  @override
  Future<DocumentChecklist> checklistFor(String applicationId) async {
    loadCalls++;
    return checklist;
  }

  @override
  Future<DocumentChecklist> attach(
    String applicationId, {
    required String requirementCode,
    required String documentId,
  }) async {
    attachCalls++;
    lastCode = requirementCode;
    lastDocumentId = documentId;
    if (failAction != null) throw failAction!;
    return checklist;
  }

  @override
  Future<DocumentChecklist> detach(
    String applicationId, {
    required String requirementCode,
  }) async {
    lastCode = requirementCode;
    if (failAction != null) throw failAction!;
    return checklist;
  }

  @override
  Future<DocumentChecklist> review(
    String applicationId, {
    required String requirementCode,
    required ApplicationReviewDecision decision,
  }) async {
    reviewCalls++;
    lastCode = requirementCode;
    lastDecision = decision;
    if (failAction != null) throw failAction!;
    return checklist;
  }
}

Map<String, dynamic> requirement({
  required String code,
  required String title,
  String status = 'missing',
  bool required_ = true,
  String? documentName,
  String? notice,
  String? action,
}) => {
  'code': code,
  'title': title,
  'description': 'A requirement.',
  'document_type': code,
  'document_type_label': title,
  'required': required_,
  'multiple': false,
  'status': status,
  'blocks_readiness': required_ && status != 'ready',
  'action': action,
  'document': documentName == null
      ? null
      : {'id': 'doc_$code', 'name': documentName, 'type': code},
  'confirmed_at': status == 'ready' ? '2026-09-07T10:00:00+05:30' : null,
  'notice': notice,
};

DocumentChecklist built({
  bool ready = false,
  List<Map<String, dynamic>>? items,
}) => DocumentChecklist.fromJson({
  'application_reference': 'FE-2026-000123',
  'ready': ready,
  'required_count': 3,
  'ready_count': ready ? 3 : 1,
  'outstanding_count': ready ? 0 : 2,
  'items': items ??
      [
        requirement(
          code: 'identity',
          title: 'Identity document',
          status: 'ready',
          documentName: 'Sample PAN Card.pdf',
        ),
        requirement(
          code: 'income',
          title: 'Income proof',
          status: 'available',
          documentName: 'Sample Salary Slip.pdf',
          action: 'Confirm this document',
        ),
        requirement(
          code: 'bank',
          title: 'Bank statement',
          action: 'Add from FynnVault',
        ),
        requirement(
          code: 'existing_loan',
          title: 'Existing loan statement',
          required_: false,
          action: 'Add from FynnVault',
        ),
      ],
  'summary': ready
      ? 'Your documents are ready for this application. Nothing has been '
            'sent anywhere yet.'
      : 'Some documents still need your attention before this application '
            'is ready.',
  'disclaimer':
      'Choosing and confirming documents prepares your application inside '
      'FynnEdge. It does not send them to any lender or provider, and no one '
      'outside FynnEdge has seen them.',
});

Future<ProviderContainer> containerWith(
  ApplicationDocumentsService service,
) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      applicationDocumentsServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

void main() {
  setUpAll(initTestEnvironment);

  // --- The server owns readiness -------------------------------------------

  group('readiness is the server\'s answer', () {
    test('the checklist is rendered as it came', () {
      final checklist = built();

      expect(checklist.ready, isFalse);
      expect(checklist.requiredCount, 3);
      expect(checklist.readyCount, 1);
      expect(checklist.items, hasLength(4));
    });

    test('an optional requirement never blocks', () {
      final optional = built().items.last;

      expect(optional.required, isFalse);
      expect(optional.status, RequirementStatus.missing);
      expect(
        optional.blocksReadiness,
        isFalse,
        reason: 'an optional document blocked the application',
      );
    });

    test('blocking is the server\'s field, not a local calculation', () {
      // A server that says ready while an item is missing is still
      // authoritative here: this class recomputes nothing.
      final checklist = DocumentChecklist.fromJson({
        'application_reference': 'FE-2026-000123',
        'ready': true,
        'required_count': 1,
        'ready_count': 1,
        'outstanding_count': 0,
        'items': [requirement(code: 'identity', title: 'Identity')],
      });

      expect(checklist.ready, isTrue);
    });

    test('an unknown status is never taken for ready', () {
      final item = ChecklistItem.fromJson(
        requirement(code: 'identity', title: 'Identity', status: 'all_good'),
      );

      expect(item.status, RequirementStatus.missing);
      expect(item.status.isReady, isFalse);
    });
  });

  // --- Mock mode -----------------------------------------------------------

  group('mock mode exercises the real states', () {
    test('it is not all green', () async {
      final checklist =
          await MockApplicationDocumentsService().checklistFor('app_1');

      final statuses = checklist.items.map((i) => i.status).toSet();

      // A demo where everything is ready never shows the states that
      // matter.
      expect(statuses, contains(RequirementStatus.ready));
      expect(statuses, contains(RequirementStatus.available));
      expect(statuses, contains(RequirementStatus.missing));
      expect(checklist.ready, isFalse);
    });

    test('confirming in mock mode makes a slot ready, and never a lender claim',
        () async {
      final service = MockApplicationDocumentsService();

      final after = await service.review(
        'app_1',
        requirementCode: 'income',
        decision: ApplicationReviewDecision.accepted,
      );

      final income = after.items.firstWhere((i) => i.code == 'income');
      expect(income.status, RequirementStatus.ready);

      // Nothing in mock mode impersonates a lender.
      final text = '${after.summary} ${after.disclaimer}'.toLowerCase();
      expect(text.contains('lender accepted'), isFalse);
      expect(text.contains('verified'), isFalse);
      expect(text, contains('no one outside fynnedge has seen'));
    });
  });

  // --- The controller ------------------------------------------------------

  group('actions go through the repository and return the server state', () {
    test('opening the screen loads once', () async {
      final service = ScriptedDocumentsService(built());
      final container = await containerWith(service);

      container.read(applicationDocumentsProvider('app_1'));
      await pumpEventQueue();

      expect(service.loadCalls, 1);
      expect(service.attachCalls, 0);
      expect(service.reviewCalls, 0);
    });

    test('confirming sends the decision for that requirement', () async {
      final service = ScriptedDocumentsService(built());
      final container = await containerWith(service);

      container.read(applicationDocumentsProvider('app_1'));
      await pumpEventQueue();

      await container
          .read(applicationDocumentsProvider('app_1').notifier)
          .confirm('income');

      expect(service.lastCode, 'income');
      expect(service.lastDecision, ApplicationReviewDecision.accepted);
    });

    test('rejecting sends the other decision', () async {
      final service = ScriptedDocumentsService(built());
      final container = await containerWith(service);

      container.read(applicationDocumentsProvider('app_1'));
      await pumpEventQueue();

      await container
          .read(applicationDocumentsProvider('app_1').notifier)
          .reject('income');

      expect(service.lastDecision, ApplicationReviewDecision.rejected);
    });

    test('a second action while one is in flight is ignored', () async {
      final service = ScriptedDocumentsService(built());
      final container = await containerWith(service);

      container.read(applicationDocumentsProvider('app_1'));
      await pumpEventQueue();

      final controller =
          container.read(applicationDocumentsProvider('app_1').notifier);
      await Future.wait([
        controller.confirm('income'),
        controller.confirm('income'),
      ]);

      expect(service.reviewCalls, 1);
    });

    test('a gone document is its own failure state', () async {
      final service = ScriptedDocumentsService(built())
        ..failAction = ApiException('gone', statusCode: 409);
      final container = await containerWith(service);

      container.read(applicationDocumentsProvider('app_1'));
      await pumpEventQueue();

      await container
          .read(applicationDocumentsProvider('app_1').notifier)
          .confirm('income');

      expect(
        container.read(applicationDocumentsProvider('app_1')).failure,
        DocumentActionFailure.unavailable,
      );
    });
  });

  // --- What the card says --------------------------------------------------

  group('the card never implies a lender has anything', () {
    Future<void> pumpWith(
      WidgetTester tester,
      DocumentChecklist checklist, {
      Size size = const Size(390, 1400),
    }) async {
      await pumpScreen(
        tester,
        const Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: ApplicationDocumentsCard(applicationId: 'app_1'),
            ),
          ),
        ),
        size: size,
        overrides: [
          applicationDocumentsServiceProvider.overrideWithValue(
            ScriptedDocumentsService(checklist),
          ),
        ],
      );
      await settle(tester);
    }

    testWidgets('an incomplete checklist shows every state', (tester) async {
      await pumpWith(tester, built());

      expect(find.text('1 of 3 ready'), findsOneWidget);
      expect(find.text('Ready for your application'), findsOneWidget);
      expect(find.text('Needs your confirmation'), findsOneWidget);
      expect(find.text('Not added yet'), findsNWidgets(2));
      expect(find.text('Optional'), findsOneWidget);
      expect(find.text('Use this document'), findsOneWidget);

      await golden(tester, ApplicationDocumentsCard, 'app_docs/incomplete');
    });

    testWidgets('all ready says so, and says what it does not mean',
        (tester) async {
      await pumpWith(
        tester,
        built(ready: true, items: [
          requirement(
            code: 'identity',
            title: 'Identity document',
            status: 'ready',
            documentName: 'Sample PAN Card.pdf',
          ),
          requirement(
            code: 'income',
            title: 'Income proof',
            status: 'ready',
            documentName: 'Sample Salary Slip.pdf',
          ),
          requirement(
            code: 'bank',
            title: 'Bank statement',
            status: 'ready',
            documentName: 'Sample Statement.pdf',
          ),
        ]),
      );

      expect(find.text('Your documents are ready'), findsOneWidget);
      expect(
        find.textContaining('Nothing has been sent to any lender'),
        findsOneWidget,
      );

      await golden(tester, ApplicationDocumentsCard, 'app_docs/ready');
    });

    testWidgets('a deleted document is missing with the reason',
        (tester) async {
      await pumpWith(
        tester,
        built(items: [
          requirement(
            code: 'income',
            title: 'Income proof',
            notice: 'The document you chose is no longer in FynnVault. '
                'Please choose another one.',
            action: 'Add from FynnVault',
          ),
        ]),
      );

      expect(find.text('Not added yet'), findsOneWidget);
      expect(
        find.textContaining('no longer in FynnVault'),
        findsOneWidget,
      );

      await golden(tester, ApplicationDocumentsCard, 'app_docs/unavailable');
    });

    testWidgets('a changed file asks the customer to look again',
        (tester) async {
      await pumpWith(
        tester,
        built(items: [
          requirement(
            code: 'income',
            title: 'Income proof',
            status: 'needs_review',
            documentName: 'Sample Salary Slip.pdf',
            notice: 'This document has changed since you confirmed it. '
                'Please check it again.',
          ),
        ]),
      );

      expect(find.text('Needs your review'), findsOneWidget);
      expect(find.textContaining('has changed since you confirmed'), findsOneWidget);

      await golden(tester, ApplicationDocumentsCard, 'app_docs/needs_review');
    });

    testWidgets('a rejected document says the customer rejected it',
        (tester) async {
      await pumpWith(
        tester,
        built(items: [
          requirement(
            code: 'income',
            title: 'Income proof',
            status: 'not_suitable',
            documentName: 'Sample Salary Slip.pdf',
            action: 'Choose another document',
          ),
        ]),
      );

      expect(find.text('Marked as unsuitable'), findsOneWidget);
      expect(find.text('Choose another document'), findsOneWidget);

      await golden(tester, ApplicationDocumentsCard, 'app_docs/not_suitable');
    });

    testWidgets('no state claims verification, approval or a lender',
        (tester) async {
      for (final checklist in [
        built(),
        built(ready: true, items: [
          requirement(
            code: 'identity',
            title: 'Identity document',
            status: 'ready',
            documentName: 'Sample PAN Card.pdf',
          ),
        ]),
        built(items: [
          requirement(
            code: 'income',
            title: 'Income proof',
            status: 'needs_review',
            documentName: 'x.pdf',
            notice: 'Changed.',
          ),
        ]),
      ]) {
        await pumpWith(tester, checklist);

        // The honest negations are stripped first, so the sweep catches
        // claims rather than the copy that denies them.
        final text = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join(' ')
            .toLowerCase()
            .replaceAll('nothing has been sent to any lender', '')
            .replaceAll(
              'it does not send them to any lender or provider',
              '',
            )
            .replaceAll('no one outside fynnedge has seen them', '')
            .replaceAll('nothing has been sent anywhere yet', '');

        for (final claim in [
          'verified', 'approved', 'guaranteed', 'lender accepted',
          'accepted by', 'kyc complete', 'loan confirmed', 'eligible',
          'sent to', 'received by', 'transmitted', 'under review by',
        ]) {
          expect(text.contains(claim), isFalse, reason: 'said: $claim');
        }
      }
    });

    testWidgets('it fits every supported width', (tester) async {
      for (final width in [360.0, 390.0, 420.0, 430.0]) {
        await pumpWith(tester, built(), size: Size(width, 1600));
        expect(tester.takeException(), isNull, reason: '$width');
      }
    });
  });
}
