import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/app/routes.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/document.dart';
import 'package:fynnedge/data/models/scan.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/document_picker.dart';
import 'package:fynnedge/data/services/document_scan_service.dart';
import 'package:fynnedge/data/services/document_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/vault/add_document_controller.dart';
import 'package:fynnedge/features/vault/fynn_scan_screen.dart';
import 'package:fynnedge/features/vault/sample_document.dart';
import 'package:fynnedge/features/vault/scan_screen.dart';
import 'package:fynnedge/features/vault/vault_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_picker.dart';
import 'support/harness.dart';

Future<ProviderContainer> containerWith({
  DocumentPicker? picker,
  DocumentService? documents,
  DocumentScanService? scans,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      if (picker != null) documentPickerProvider.overrideWithValue(picker),
      if (documents != null)
        documentServiceProvider.overrideWithValue(documents),
      if (scans != null) documentScanServiceProvider.overrideWithValue(scans),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

/// A vault service that can be made to fail.
class FailingDocumentService implements DocumentService {
  FailingDocumentService(this.error);
  final Object error;

  @override
  Future<List<VaultDocument>> getDocuments() async => const [];

  @override
  Future<VaultDocument> getDocument(String id) async => throw error;

  @override
  Future<VaultLimits> getLimits() async => const VaultLimits();

  @override
  Future<VaultDocument> upload(DocumentUpload upload) async => throw error;

  @override
  Future<Uint8List> download(String id) async => throw error;

  @override
  Future<void> delete(String id) async => throw error;
}

/// A scan service that can be made to fail, for the states a real provider
/// will eventually produce.
class ScriptedScanService implements DocumentScanService {
  ScriptedScanService({this.result, this.error});

  DocumentScan? result;
  Object? error;
  int scanCalls = 0;

  @override
  Future<DocumentScan> statusFor(String documentId) async {
    if (error != null) throw error!;
    return result ?? const MockDocumentScanService().statusFor(documentId);
  }

  @override
  Future<DocumentScan> scan(String documentId, {bool force = false}) async {
    scanCalls++;
    if (error != null) throw error!;
    return result ?? const MockDocumentScanService().scan(documentId);
  }

  @override
  Future<DocumentScan> review(
    String documentId, {
    required String field,
    required ReviewDecision decision,
    String? value,
    bool applyToProfile = false,
  }) async {
    if (error != null) throw error!;
    return result ?? const MockDocumentScanService().statusFor(documentId);
  }
}

void main() {
  setUpAll(initTestEnvironment);
  setUp(MockStore.instance.reset);

  // --- The scan foundation -------------------------------------------------

  group('scanning', () {
    test('mock mode reports that nothing can read a document', () async {
      final scan = await const MockDocumentScanService().scan('doc_1');

      expect(scan.status, ScanStatus.unavailable);
      expect(scan.reason, 'document_understanding_not_configured');
      expect(scan.message, contains('stored safely'));
      expect(scan.message, contains('Nothing has been extracted'));
    });

    test('mock mode invents no extraction at all', () async {
      for (final scan in [
        await const MockDocumentScanService().scan('doc_1'),
        await const MockDocumentScanService().statusFor('doc_1'),
      ]) {
        // Null, not empty. An empty extraction reads as a scan that ran and
        // found nothing.
        expect(scan.extraction, isNull);
        expect(scan.reviews, isEmpty);
        expect(scan.isSample, isFalse);

        // An invented salary in a demo is indistinguishable, on screen,
        // from a real reading of a real customer's payslip.
        final text = '${scan.message} ${scan.reason} ${scan.provider}'
            .toLowerCase();
        for (final fabricated in const [
          'pan',
          'aadhaar',
          'account_number',
          'person_name',
          'balance',
          'salary',
          'ifsc',
        ]) {
          expect(text, isNot(contains(fabricated)));
        }
      }
    });

    test('mock mode refuses a review rather than pretending to record one',
        () async {
      await expectLater(
        const MockDocumentScanService().review(
          'doc_1',
          field: 'net_income',
          decision: ReviewDecision.confirmed,
        ),
        throwsA(isA<CapabilityUnavailableException>()),
      );
    });

    test('no status a provider would have to report is reachable', () async {
      final scan = await const MockDocumentScanService().scan('doc_1');

      expect(scan.status.requiresProvider, isFalse);
      expect(scan.provider, isNull);
      expect(scan.startedAt, isNull);
      expect(scan.processedAt, isNull);
    });

    test('an unknown status is never taken for a completed one', () {
      final scan = DocumentScan.fromJson(const {
        'document_id': '1',
        'status': 'read_by_our_ai',
      });

      expect(scan.status, ScanStatus.unavailable);
      expect(scan.extraction, isNull);
    });

    test('a malformed extraction never becomes a rendered value', () {
      final scan = DocumentScan.fromJson(const {
        'document_id': '1',
        'status': 'completed',
        // Not the shape the API returns. The server is authoritative about
        // extraction, so anything else parses to nothing rather than being
        // coerced into a field.
        'extraction': {'person_name': 'Sample Person', 'pan': 'AAAAA0000A'},
      });

      expect(scan.extraction, isEmpty);
    });

    test('an extraction is displayed exactly as the server reported it', () {
      // No parsing on this side: the amount, the confidence and the review
      // flag are all the server's answers.
      final scan = DocumentScan.fromJson(const {
        'document_id': '1',
        'status': 'needs_review',
        'is_sample': true,
        'extraction': [
          {
            'key': 'net_income',
            'label': 'Net pay',
            'value': '75000.00',
            'value_type': 'money',
            'amount': 75000,
            'confidence': 'low',
            'needs_review': true,
            'review_reason': 'Please check this value.',
            'evidence': {'page': 1, 'section': 'Net Pay'},
          },
        ],
      });

      final field = scan.extraction!.single;
      expect(field.amount, 75000);
      expect(field.confidence, ConfidenceLevel.low);
      expect(field.needsReview, isTrue);
      expect(field.evidence!.description, contains('Net Pay'));
      expect(scan.fieldsToCheck, hasLength(1));
      expect(scan.isSample, isTrue);
    });
  });

  // --- Choosing a file -----------------------------------------------------

  group('choosing a file', () {
    test('a chosen file moves the flow to review', () async {
      final picker = FakeDocumentPicker();
      final container = await containerWith(picker: picker);
      final controller = container.read(addDocumentProvider.notifier);

      await controller.choose();

      final state = container.read(addDocumentProvider);
      expect(state.step, AddDocumentStep.review);
      expect(state.picked!.fileName, 'March statement.pdf');
      expect(state.error, isNull);

      // The picker is filtered to what the vault accepts.
      expect(picker.lastExtensions, contains('pdf'));
      expect(picker.lastExtensions, isNot(contains('exe')));
    });

    test('cancelling leaves no error and no file', () async {
      final container = await containerWith(
        picker: FakeDocumentPicker()..failure = PickerFailure.cancelled,
      );
      final controller = container.read(addDocumentProvider.notifier);

      await controller.choose();

      final state = container.read(addDocumentProvider);
      expect(state.step, AddDocumentStep.choose);
      expect(state.picked, isNull);
      // Changing your mind is not a failure to report.
      expect(state.error, isNull);
    });

    test('an unreadable file says so', () async {
      final container = await containerWith(
        picker: FakeDocumentPicker()..failure = PickerFailure.unreadable,
      );

      await container.read(addDocumentProvider.notifier).choose();

      expect(
        container.read(addDocumentProvider).error,
        contains('could not be read'),
      );
    });

    test('a device with no picker says so', () async {
      final container = await containerWith(
        picker: const UnavailableDocumentPicker(),
      );

      await container.read(addDocumentProvider.notifier).choose();

      expect(
        container.read(addDocumentProvider).error,
        contains('did not offer a file picker'),
      );
    });

    test('an unsupported file is refused before it is uploaded', () async {
      final container = await containerWith(
        picker: FakeDocumentPicker(
          fileName: 'sneaky.php',
          mimeType: 'application/x-php',
          bytes: Uint8List.fromList(utf8.encode('<?php echo 1; ?>')),
        ),
      );

      await container.read(addDocumentProvider.notifier).choose();

      final state = container.read(addDocumentProvider);
      expect(state.step, AddDocumentStep.choose);
      expect(state.error, contains('PDFs and photos'));
      expect(MockStore.instance.documents, isEmpty);
    });

    test('an oversized file is refused before it is uploaded', () async {
      final container = await containerWith(
        picker: FakeDocumentPicker(bytes: Uint8List(11 * 1024 * 1024)),
      );

      await container.read(addDocumentProvider.notifier).choose();

      final state = container.read(addDocumentProvider);
      expect(state.step, AddDocumentStep.choose);
      expect(state.error, contains('over the'));
      expect(MockStore.instance.documents, isEmpty);
    });
  });

  // --- Storing -------------------------------------------------------------

  group('storing', () {
    test('it stores through FynnVault, with the chosen type', () async {
      final container = await containerWith(picker: FakeDocumentPicker());
      final controller = container.read(addDocumentProvider.notifier);

      await controller.choose();
      controller.setType(DocumentCategory.income);
      final stored = await controller.store(name: 'Salary slip');

      expect(stored, isNotNull);
      expect(stored!.category, DocumentCategory.income);
      expect(stored.name, 'Salary slip');
      expect(stored.status, DocumentStatus.uploaded);
      // Stored is not read, verified or shared.
      expect(stored.isVerified, isFalse);
      expect(stored.isShared, isFalse);

      // One vault, one storage path: the document is in MockStore like any
      // other, with its bytes.
      expect(MockStore.instance.documents.single.id, stored.id);
      expect(MockStore.instance.documentBytes(stored.id), isNotNull);
      expect(container.read(addDocumentProvider).step, AddDocumentStep.stored);
    });

    test('a failed upload keeps the file so it can be retried', () async {
      final container = await containerWith(
        picker: FakeDocumentPicker(),
        documents: FailingDocumentService(NetworkException()),
      );
      final controller = container.read(addDocumentProvider.notifier);

      await controller.choose();
      expect(await controller.store(), isNull);

      final state = container.read(addDocumentProvider);
      expect(state.error, contains('Could not reach FynnEdge'));
      // Still on review, still holding the file: nothing to choose again.
      expect(state.step, AddDocumentStep.review);
      expect(state.picked, isNotNull);
      expect(state.uploading, isFalse);
    });

    test('an expired session is not reported as a generic failure', () async {
      final container = await containerWith(
        picker: FakeDocumentPicker(),
        documents: FailingDocumentService(UnauthorizedException()),
      );
      final controller = container.read(addDocumentProvider.notifier);

      await controller.choose();
      await controller.store();

      expect(
        container.read(addDocumentProvider).error,
        contains('sign in again'),
      );
    });

    test('offline, nothing is ever shown as stored', () async {
      final container = await containerWith(
        picker: FakeDocumentPicker(),
        documents: FailingDocumentService(NetworkException()),
      );
      final controller = container.read(addDocumentProvider.notifier);

      // Choosing works offline; storing does not, and does not claim to.
      await controller.choose();
      expect(container.read(addDocumentProvider).picked, isNotNull);

      await controller.store();

      final state = container.read(addDocumentProvider);
      expect(state.step, isNot(AddDocumentStep.stored));
      expect(state.stored, isNull);
      expect(MockStore.instance.documents, isEmpty);
    });
  });

  // --- Screens -------------------------------------------------------------

  group('screens', () {
    testWidgets('the add screen offers a real source and defers the camera', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ScanScreen(),
        size: const Size(420, 1200),
        overrides: [
          documentPickerProvider.overrideWithValue(FakeDocumentPicker()),
        ],
      );
      await settle(tester);

      expect(find.text('Choose from device'), findsOneWidget);
      // Present, visibly unavailable, and not tappable.
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Camera capture — coming soon'), findsOneWidget);
    });

    testWidgets('the whole flow runs: choose, review, store', (tester) async {
      final picker = FakeDocumentPicker();

      await pumpScreen(
        tester,
        const ScanScreen(),
        size: const Size(420, 1600),
        overrides: [documentPickerProvider.overrideWithValue(picker)],
      );
      await settle(tester);

      await tester.tap(find.text('Choose from device'));
      await settle(tester);

      // Review shows the file, not an interpretation of it.
      expect(find.text('Check this over'), findsOneWidget);
      expect(find.text('March statement.pdf'), findsWidgets);
      expect(find.text('PDF'), findsOneWidget);

      await tester.tap(find.text('Store in FynnVault'));
      await settle(tester);

      expect(find.text('Document stored securely'), findsOneWidget);
      expect(find.text('Try FynnScan'), findsOneWidget);
      expect(MockStore.instance.documents, hasLength(1));
    });

    testWidgets('a cancelled picker leaves the screen as it was', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ScanScreen(),
        size: const Size(420, 1200),
        overrides: [
          documentPickerProvider.overrideWithValue(
            FakeDocumentPicker()..failure = PickerFailure.cancelled,
          ),
        ],
      );
      await settle(tester);

      await tester.tap(find.text('Choose from device'));
      await settle(tester);

      expect(find.text('What would you like to add?'), findsOneWidget);
      expect(find.text('Check this over'), findsNothing);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    });

    testWidgets('FynnScan says it is not connected, and shows nothing else', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const FynnScanScreen(documentId: 'doc_1'),
        size: const Size(420, 1400),
      );
      await settle(tester);

      expect(find.text("FynnScan isn't connected yet"), findsOneWidget);
      expect(
        find.textContaining('Nothing has been extracted or interpreted'),
        findsOneWidget,
      );
      expect(
        find.textContaining('has not been read, verified or shared'),
        findsOneWidget,
      );
      expect(find.text('Back to vault'), findsOneWidget);

      // Nothing that would pass for a reading of the document.
      for (final fabricated in const [
        'confidence',
        '%',
        'ABCDE',
        'Extracted',
        'Account number',
        'Name:',
      ]) {
        expect(
          find.textContaining(fabricated),
          findsNothing,
          reason: 'FynnScan showed "$fabricated"',
        );
      }
    });

    testWidgets('a scan lookup failure offers a retry', (tester) async {
      final service = ScriptedScanService(error: NetworkException());

      await pumpScreen(
        tester,
        const FynnScanScreen(documentId: 'doc_1'),
        overrides: [documentScanServiceProvider.overrideWithValue(service)],
      );
      await settle(tester);

      expect(find.textContaining('Could not reach FynnEdge'), findsOneWidget);

      service.error = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);

      expect(find.text("FynnScan isn't connected yet"), findsOneWidget);
    });

    testWidgets('golden: the review step', (tester) async {
      await pumpScreen(
        tester,
        const ScanScreen(),
        overrides: [
          documentPickerProvider.overrideWithValue(FakeDocumentPicker()),
        ],
      );
      await settle(tester);

      await tester.tap(find.text('Choose from device'));
      await settle(tester);

      await golden(tester, ScanScreen, '22a_add_document_review');
    });

    testWidgets('golden: FynnScan not connected', (tester) async {
      await pumpScreen(tester, const FynnScanScreen(documentId: 'doc_1'));
      await settle(tester);

      await golden(tester, FynnScanScreen, '22b_fynn_scan');
    });

    testWidgets('the vault offers FynnScan on a stored document', (
      tester,
    ) async {
      final document = await MockDocumentService().upload(
        DocumentUpload(
          bytes: SampleDocument.bytes(),
          fileName: 'statement.pdf',
          mimeType: 'application/pdf',
          category: DocumentCategory.bank,
        ),
      );

      await pumpScreen(tester, const VaultScreen());
      await settle(tester);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);

      expect(find.text('FynnScan'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // And the destination is addressed by the route constant, never a
      // literal typed into a widget.
      expect(Routes.documentScan(document.id), '/scan/${document.id}');
    });
  });
}
