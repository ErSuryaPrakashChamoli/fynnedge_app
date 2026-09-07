import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/models/scan.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/document_scan_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/vault/fynn_scan_screen.dart';
import 'package:fynnedge/features/vault/scan_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// FynnScan on the customer's side.
///
/// NO LIVE DOCUMENT PROVIDER IS CONNECTED. Every value here is synthetic and
/// no real document, person or payslip is involved.
class ScriptedScanService implements DocumentScanService {
  ScriptedScanService(this.state);

  DocumentScan state;
  Object? failScan;
  Object? failReview;

  int statusCalls = 0;
  int scanCalls = 0;
  int reviewCalls = 0;

  String? lastField;
  ReviewDecision? lastDecision;
  String? lastValue;
  bool lastApply = false;
  bool lastForce = false;

  @override
  Future<DocumentScan> statusFor(String documentId) async {
    statusCalls++;
    return state;
  }

  @override
  Future<DocumentScan> scan(String documentId, {bool force = false}) async {
    scanCalls++;
    lastForce = force;
    if (failScan != null) throw failScan!;
    return state;
  }

  @override
  Future<DocumentScan> review(
    String documentId, {
    required String field,
    required ReviewDecision decision,
    String? value,
    bool applyToProfile = false,
  }) async {
    reviewCalls++;
    lastField = field;
    lastDecision = decision;
    lastValue = value;
    lastApply = applyToProfile;
    if (failReview != null) throw failReview!;
    return state;
  }
}

DocumentScan read({
  ScanStatus status = ScanStatus.completed,
  bool needsReview = false,
  bool isStale = false,
  bool mismatch = false,
  List<Map<String, dynamic>>? reviews,
}) => DocumentScan.fromJson({
  'document_id': 'doc_1',
  'scan_id': 'scan_1',
  'status': status.id,
  'is_supported': true,
  'is_sample': true,
  'is_stale': isStale,
  'classification_mismatch': mismatch,
  'schema_version': 'income_v1',
  'document_period': '2026-08',
  'extraction': [
    {
      'key': 'net_income',
      'label': 'Net pay',
      'value': '75000.00',
      'value_type': 'money',
      'amount': 75000,
      'confidence': needsReview ? 'low' : 'high',
      'needs_review': needsReview,
      'review_reason': needsReview ? 'Please check this value.' : null,
      'evidence': {'page': 1, 'section': 'Net Pay', 'snippet': '75,000.00'},
    },
    {
      'key': 'gross_income',
      'label': 'Gross pay',
      'value': '85000.00',
      'value_type': 'money',
      'amount': 85000,
      'confidence': 'high',
      'needs_review': false,
    },
  ],
  'reviews': reviews ?? const [],
  'disclaimer': 'FynnScan reads what a document appears to contain. It does '
      'not verify your document, and nothing here is saved to your profile '
      'until you confirm it.',
});

Future<ProviderContainer> containerWith(DocumentScanService service) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      documentScanServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

void main() {
  setUpAll(initTestEnvironment);

  // --- Reading a scan ------------------------------------------------------

  group('the server is authoritative about what a document says', () {
    test('a field is displayed exactly as reported', () {
      final field = read().extraction!.first;

      // No parsing here: the amount, the confidence and the review flag are
      // all the server's answers.
      expect(field.amount, 75000);
      expect(field.confidence, ConfidenceLevel.high);
      expect(field.needsReview, isFalse);
      expect(field.evidence!.page, 1);
    });

    test('null and empty extraction are different answers', () {
      final nothing = DocumentScan.fromJson(const {
        'document_id': '1',
        'status': 'not_started',
      });
      expect(nothing.extraction, isNull);

      final ranAndFoundNothing = DocumentScan.fromJson(const {
        'document_id': '1',
        'status': 'completed',
        'extraction': [],
      });
      expect(ranAndFoundNothing.extraction, isEmpty);
    });

    test('an unknown status is never taken for a completed one', () {
      final scan = DocumentScan.fromJson(const {
        'document_id': '1',
        'status': 'read_by_our_ai',
      });

      expect(scan.status, ScanStatus.unavailable);
      expect(scan.status.hasExtraction, isFalse);
      expect(scan.canScan, isFalse);
    });

    test('an unknown confidence is unavailable, not high', () {
      final field = ExtractedField.fromJson(const {
        'key': 'net_income',
        'label': 'Net pay',
        'value': '75000.00',
        'value_type': 'money',
        'confidence': 'very_sure_indeed',
        'needs_review': true,
      });

      expect(field.confidence, ConfidenceLevel.unavailable);
    });

    test('a correction keeps both facts', () {
      final scan = read(reviews: [
        {
          'field_key': 'net_income',
          'decision': 'edited',
          'extracted_value': '75000.00',
          'customer_value': '72000.00',
          'applied_to_profile': true,
        },
      ]);

      final review = scan.reviewFor('net_income')!;
      expect(review.extractedValue, '75000.00');
      expect(review.customerValue, '72000.00');
      expect(review.wasCorrected, isTrue);
    });
  });

  // --- Mock mode -----------------------------------------------------------

  group('mock mode has no provider and says so', () {
    test('the status is unavailable', () async {
      final scan = await const MockDocumentScanService().statusFor('doc_1');

      expect(scan.status, ScanStatus.unavailable);
      expect(scan.extraction, isNull);
      expect(scan.canScan, isFalse);
    });

    test('a review refuses rather than pretending to record one', () async {
      await expectLater(
        const MockDocumentScanService().review(
          'doc_1',
          field: 'net_income',
          decision: ReviewDecision.confirmed,
        ),
        throwsA(isA<CapabilityUnavailableException>()),
      );
    });
  });

  // --- A document is sent only when the customer asks ----------------------

  group('nothing is sent unasked', () {
    test('opening the screen reads state and sends nothing', () async {
      final service = ScriptedScanService(read(status: ScanStatus.notStarted));
      final container = await containerWith(service);

      container.read(scanControllerProvider('doc_1'));
      await pumpEventQueue();

      expect(service.statusCalls, 1);
      expect(
        service.scanCalls,
        0,
        reason: 'opening a screen must never send a document anywhere',
      );
    });

    test('a tap sends it exactly once', () async {
      final service = ScriptedScanService(read(status: ScanStatus.notStarted));
      final container = await containerWith(service);

      container.read(scanControllerProvider('doc_1'));
      await pumpEventQueue();

      final controller =
          container.read(scanControllerProvider('doc_1').notifier);
      await Future.wait([controller.scan(), controller.scan()]);

      expect(service.scanCalls, 1);
    });
  });

  // --- Failures produce no reading -----------------------------------------

  group('a failed reading invents nothing', () {
    Future<ScanScreenState> after(Object error) async {
      final service = ScriptedScanService(read(status: ScanStatus.notStarted))
        ..failScan = error;
      final container = await containerWith(service);

      container.read(scanControllerProvider('doc_1'));
      await pumpEventQueue();
      await container.read(scanControllerProvider('doc_1').notifier).scan();

      return container.read(scanControllerProvider('doc_1'));
    }

    test('an unreachable provider is its own state', () async {
      final state = await after(UpstreamUnavailableException('down'));
      expect(state.failure, ScanFailure.providerUnavailable);
    });

    test('missing consent is its own state, not a signed-out session',
        () async {
      final state = await after(
        PermissionRequiredException('needs consent', reason: 'consent_required'),
      );
      expect(state.failure, ScanFailure.consentRequired);
    });

    test('an unsupported family is distinct from no provider', () async {
      expect(
        (await after(CapabilityUnavailableException(
          'not read',
          reason: 'document_family_not_supported',
        ))).failure,
        ScanFailure.unsupportedDocument,
      );

      expect(
        (await after(CapabilityUnavailableException(
          'no provider',
          reason: 'document_understanding_not_configured',
        ))).failure,
        ScanFailure.notConfigured,
      );
    });

    test('too many readings is its own state', () async {
      final state = await after(RateLimitedException('slow down'));
      expect(state.failure, ScanFailure.tooManyScans);
    });
  });

  // --- Confirming is not saving --------------------------------------------

  group('the customer decides', () {
    test('confirming without saving does not ask for a profile update',
        () async {
      final service = ScriptedScanService(read());
      final container = await containerWith(service);

      container.read(scanControllerProvider('doc_1'));
      await pumpEventQueue();

      await container
          .read(scanControllerProvider('doc_1').notifier)
          .confirm('gross_income');

      expect(service.lastDecision, ReviewDecision.confirmed);
      expect(
        service.lastApply,
        isFalse,
        reason: 'confirming a reading is not saving it',
      );
    });

    test('saving is a separate, explicit flag', () async {
      final service = ScriptedScanService(read());
      final container = await containerWith(service);

      container.read(scanControllerProvider('doc_1'));
      await pumpEventQueue();

      await container
          .read(scanControllerProvider('doc_1').notifier)
          .confirm('net_income', save: true);

      expect(service.lastApply, isTrue);
    });

    test('a correction sends the customer value, not the read one', () async {
      final service = ScriptedScanService(read());
      final container = await containerWith(service);

      container.read(scanControllerProvider('doc_1'));
      await pumpEventQueue();

      await container
          .read(scanControllerProvider('doc_1').notifier)
          .correct('net_income', '72000', save: true);

      expect(service.lastDecision, ReviewDecision.edited);
      expect(service.lastValue, '72000');
    });

    test('rejecting sends no value at all', () async {
      final service = ScriptedScanService(read());
      final container = await containerWith(service);

      container.read(scanControllerProvider('doc_1'));
      await pumpEventQueue();

      await container
          .read(scanControllerProvider('doc_1').notifier)
          .reject('net_income');

      expect(service.lastDecision, ReviewDecision.rejected);
      expect(service.lastValue, isNull);
      expect(service.lastApply, isFalse);
    });

    test('a second decision while one is in flight is ignored', () async {
      final service = ScriptedScanService(read());
      final container = await containerWith(service);

      container.read(scanControllerProvider('doc_1'));
      await pumpEventQueue();

      final controller =
          container.read(scanControllerProvider('doc_1').notifier);
      await Future.wait([
        controller.confirm('net_income', save: true),
        controller.confirm('net_income', save: true),
      ]);

      expect(service.reviewCalls, 1);
    });
  });

  // --- What the screen says -------------------------------------------------

  group('the screen distinguishes found from confirmed', () {
    Future<void> pumpWith(WidgetTester tester, DocumentScan scan) async {
      await pumpScreen(
        tester,
        const FynnScanScreen(documentId: 'doc_1'),
        overrides: [
          documentScanServiceProvider.overrideWithValue(
            ScriptedScanService(scan),
          ),
        ],
      );
      await settle(tester);
    }

    testWidgets('a reading is labelled as found, never as the customer\'s',
        (tester) async {
      await pumpWith(tester, read());

      expect(find.text('Found in your document'), findsOneWidget);
      expect(find.text('₹75,000'), findsOneWidget);

      // A fictional reading is labelled as one.
      expect(find.text('Sample data'), findsOneWidget);

      await golden(tester, FynnScanScreen, 'scan/completed');
    });

    testWidgets('a value needing a look says so in words, not only colour',
        (tester) async {
      await pumpWith(tester, read(status: ScanStatus.needsReview, needsReview: true));

      expect(find.text('Please check what we found'), findsOneWidget);
      expect(find.text('Please check this'), findsOneWidget);
      expect(find.text('Please check this value.'), findsOneWidget);

      await golden(tester, FynnScanScreen, 'scan/needs_review');
    });

    testWidgets('a confirmed field is shown as the customer\'s answer',
        (tester) async {
      await pumpWith(tester, read(reviews: [
        {
          'field_key': 'net_income',
          'decision': 'edited',
          'extracted_value': '75000.00',
          'customer_value': '72000.00',
          'applied_to_profile': true,
        },
      ]));

      expect(find.text('Corrected by you'), findsOneWidget);
      expect(find.text('Saved to your financial profile.'), findsOneWidget);
      expect(
        find.text('We read ₹75,000. You said ₹72,000.'),
        findsOneWidget,
      );

      await golden(tester, FynnScanScreen, 'scan/confirmed');
    });

    testWidgets('nothing read yet', (tester) async {
      await pumpWith(tester, read(status: ScanStatus.notStarted));

      expect(find.text('Nothing read yet'), findsOneWidget);
      expect(find.text('Read this document'), findsOneWidget);

      await golden(tester, FynnScanScreen, 'scan/not_started');
    });

    testWidgets('consent required offers the way to grant it', (tester) async {
      await pumpWith(tester, read(status: ScanStatus.consentRequired));

      expect(find.text('Your permission comes first'), findsOneWidget);
      expect(find.text('Privacy & Consent'), findsOneWidget);

      // Nothing to read until permission exists.
      expect(find.text('Read this document'), findsNothing);

      await golden(tester, FynnScanScreen, 'scan/consent_required');
    });

    testWidgets('a failed reading shows no values at all', (tester) async {
      await pumpWith(tester, read(status: ScanStatus.failed));

      expect(find.text('We could not read this document'), findsOneWidget);

      // Nothing invented, and no figure standing in for one.
      expect(find.text('₹75,000'), findsNothing);
      expect(find.text('Found in your document'), findsNothing);

      await golden(tester, FynnScanScreen, 'scan/failed');
    });

    testWidgets('a stale reading says it describes a previous file',
        (tester) async {
      await pumpWith(tester, read(isStale: true));

      expect(
        find.textContaining('describes the previous file'),
        findsOneWidget,
      );
    });

    testWidgets('a disagreement about the type does not refile anything',
        (tester) async {
      await pumpWith(tester, read(status: ScanStatus.needsReview, mismatch: true));

      expect(
        find.textContaining('has not changed how it is filed'),
        findsOneWidget,
      );
    });

    testWidgets('no state promises verification or an approval',
        (tester) async {
      for (final scan in [
        read(),
        read(status: ScanStatus.needsReview, needsReview: true),
        read(status: ScanStatus.notStarted),
        read(status: ScanStatus.consentRequired),
        read(status: ScanStatus.failed),
        read(status: ScanStatus.unavailable),
      ]) {
        await pumpWith(tester, scan);

        final text = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join(' ')
            .toLowerCase();

        for (final claim in [
          // FynnScan reads a document. It does not check one.
          'verified', 'authentic', 'genuine', 'validated identity',
          'we have confirmed', 'proof of',
          // No benchmark exists, so no accuracy claim is made.
          '% accurate', 'accuracy', '98%', '97%',
          // Approval is a lender's decision.
          'approved', 'pre-approved', 'you qualify',
          // FynnScan reads income documents, and says which.
          'any financial document', 'any document',
        ]) {
          expect(
            text.contains(claim),
            isFalse,
            reason: '${scan.status.id} said: $claim',
          );
        }
      }
    });

    testWidgets('no progress percentage is invented while reading',
        (tester) async {
      await pumpWith(tester, read(status: ScanStatus.processing));

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');

      expect(text, contains('Reading your document'));
      for (final fake in ['37%', '68%', '91%', '%']) {
        expect(text.contains(fake), isFalse, reason: fake);
      }

      await golden(tester, FynnScanScreen, 'scan/processing');
    });
  });
}
