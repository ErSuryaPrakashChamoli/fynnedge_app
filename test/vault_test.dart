import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/document.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/document_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/vault/sample_document.dart';
import 'package:fynnedge/features/vault/scan_screen.dart';
import 'package:fynnedge/features/vault/vault_controller.dart';
import 'package:fynnedge/features/vault/vault_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_picker.dart';
import 'support/harness.dart';

/// A vault service that can be made to fail, wrapping the real mock one.
class FlakyDocumentService implements DocumentService {
  FlakyDocumentService([MockDocumentService? inner])
    : _inner = inner ?? MockDocumentService();

  final MockDocumentService _inner;
  Object? failList;
  Object? failUpload;
  Object? failDelete;
  Object? failDownload;
  int listCalls = 0;
  int uploadCalls = 0;

  @override
  Future<List<VaultDocument>> getDocuments() async {
    listCalls++;
    if (failList != null) throw failList!;
    return _inner.getDocuments();
  }

  @override
  Future<VaultDocument> getDocument(String id) => _inner.getDocument(id);

  @override
  Future<VaultLimits> getLimits() => _inner.getLimits();

  @override
  Future<VaultDocument> upload(DocumentUpload upload) async {
    uploadCalls++;
    if (failUpload != null) throw failUpload!;
    return _inner.upload(upload);
  }

  @override
  Future<Uint8List> download(String id) async {
    if (failDownload != null) throw failDownload!;
    return _inner.download(id);
  }

  @override
  Future<void> delete(String id) async {
    if (failDelete != null) throw failDelete!;
    return _inner.delete(id);
  }
}

Future<ProviderContainer> containerWith(DocumentService service) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      documentServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

DocumentUpload sampleUpload({
  DocumentCategory category = DocumentCategory.bank,
  String? name,
}) => DocumentUpload(
  bytes: SampleDocument.bytes(),
  fileName: SampleDocument.fileName,
  mimeType: SampleDocument.mimeType,
  category: category,
  name: name,
);

void main() {
  setUpAll(initTestEnvironment);
  setUp(MockStore.instance.reset);

  // --- The vault -----------------------------------------------------------

  group('vault', () {
    test('it starts empty', () async {
      expect(await MockDocumentService().getDocuments(), isEmpty);
      expect(MockStore.instance.documents, isEmpty);
    });

    test('storing a document records what it is', () async {
      final service = MockDocumentService();
      final document = await service.upload(
        sampleUpload(name: 'March statement'),
      );

      expect(document.name, 'March statement');
      expect(document.category, DocumentCategory.bank);
      expect(document.mimeType, 'application/pdf');
      expect(document.sizeBytes, greaterThan(0));
      expect(document.status, DocumentStatus.uploaded);
      expect(document.originalFilename, SampleDocument.fileName);
    });

    test('a stored document is not a verified one', () async {
      final document = await MockDocumentService().upload(sampleUpload());

      // Upload success means the bytes arrived. Nothing else.
      expect(document.isVerified, isFalse);
      expect(document.isShared, isFalse);
      expect(document.status.label, 'Stored');
      expect(DocumentStatus.values.map((s) => s.id), ['uploaded', 'failed']);
    });

    test('the name falls back to the filename', () async {
      final document = await MockDocumentService().upload(sampleUpload());
      expect(document.name, 'FynnEdge sample document');
    });

    test('the list is newest first', () async {
      final service = MockDocumentService();
      final first = await service.upload(sampleUpload(name: 'One'));
      final second = await service.upload(sampleUpload(name: 'Two'));

      expect((await service.getDocuments()).map((d) => d.id), [
        second.id,
        first.id,
      ]);
    });

    test('the bytes come back exactly as they went in', () async {
      final service = MockDocumentService();
      final bytes = SampleDocument.bytes();
      final document = await service.upload(
        DocumentUpload(
          bytes: bytes,
          fileName: SampleDocument.fileName,
          mimeType: SampleDocument.mimeType,
          category: DocumentCategory.identity,
        ),
      );

      expect(await service.download(document.id), bytes);
    });

    test('deleting removes the document and its bytes', () async {
      final service = MockDocumentService();
      final document = await service.upload(sampleUpload());

      await service.delete(document.id);

      expect(await service.getDocuments(), isEmpty);
      expect(MockStore.instance.documentBytes(document.id), isNull);
      await expectLater(
        service.download(document.id),
        throwsA(isA<ApiException>()),
      );
    });

    test('a missing document is a 404, not an empty one', () async {
      await expectLater(
        MockDocumentService().getDocument('doc_nope'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('mock state survives within the session', () async {
      await MockDocumentService().upload(sampleUpload(name: 'Kept'));

      final later = await MockDocumentService().getDocuments();
      expect(later.single.name, 'Kept');
    });
  });

  // --- What it refuses -----------------------------------------------------

  group('what the vault refuses', () {
    test('a file type it does not take', () async {
      await expectLater(
        MockDocumentService().upload(
          DocumentUpload(
            bytes: Uint8List.fromList(utf8.encode('<?php echo 1; ?>')),
            fileName: 'sneaky.php',
            mimeType: 'application/x-php',
            category: DocumentCategory.other,
          ),
        ),
        throwsA(isA<ApiException>()),
      );

      expect(MockStore.instance.documents, isEmpty);
    });

    test('an oversized file', () async {
      await expectLater(
        MockDocumentService().upload(
          DocumentUpload(
            bytes: Uint8List(11 * 1024 * 1024),
            fileName: 'huge.pdf',
            mimeType: 'application/pdf',
            category: DocumentCategory.other,
          ),
        ),
        throwsA(isA<ApiException>()),
      );

      expect(MockStore.instance.documents, isEmpty);
    });

    test('an empty file', () async {
      await expectLater(
        MockDocumentService().upload(
          DocumentUpload(
            bytes: Uint8List(0),
            fileName: 'nothing.pdf',
            mimeType: 'application/pdf',
            category: DocumentCategory.other,
          ),
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('a filename that is really a path is kept as a name only', () async {
      final document = await MockDocumentService().upload(
        DocumentUpload(
          bytes: SampleDocument.bytes(),
          fileName: '../../../../etc/passwd.pdf',
          mimeType: 'application/pdf',
          category: DocumentCategory.other,
        ),
      );

      expect(document.originalFilename, 'passwd.pdf');
      expect(document.name, 'passwd');
      expect(document.originalFilename, isNot(contains('..')));
    });
  });

  // --- Serialization -------------------------------------------------------

  group('serialization', () {
    test('a document survives a round trip', () async {
      final original = await MockDocumentService().upload(
        sampleUpload(name: 'March statement'),
      );
      final restored = VaultDocument.fromJson(original.toJson());

      expect(restored.toJson(), original.toJson());
      expect(restored.name, original.name);
      expect(restored.sizeBytes, original.sizeBytes);
      expect(restored.category, original.category);
    });

    test('nothing serialised points at storage', () async {
      final document = await MockDocumentService().upload(sampleUpload());
      final json = jsonEncode(document.toJson());

      expect(json, isNot(contains('storage')));
      expect(json, isNot(contains('/u1/')));
    });

    test('limits round-trip', () {
      const original = VaultLimits();
      final restored = VaultLimits.fromJson(original.toJson());

      expect(restored.maxBytes, original.maxBytes);
      expect(restored.mimeTypes, original.mimeTypes);
      expect(restored.accepts('application/pdf'), isTrue);
      expect(restored.accepts('application/x-php'), isFalse);
    });
  });

  // --- The controller ------------------------------------------------------

  group('controller', () {
    test('uploading refreshes the vault', () async {
      final container = await containerWith(MockDocumentService());
      final controller = container.read(vaultControllerProvider.notifier);

      expect(await container.read(documentsProvider.future), isEmpty);
      expect(await controller.upload(sampleUpload()), isNotNull);

      expect(await container.read(documentsProvider.future), hasLength(1));
      expect(container.read(vaultControllerProvider).uploading, isFalse);
    });

    test('a failed upload stores nothing and says why', () async {
      final service = FlakyDocumentService()..failUpload = NetworkException();
      final container = await containerWith(service);
      final controller = container.read(vaultControllerProvider.notifier);

      expect(await controller.upload(sampleUpload()), isNull);

      final state = container.read(vaultControllerProvider);
      expect(state.error, contains('Could not reach FynnEdge'));
      expect(state.uploading, isFalse);
      expect(MockStore.instance.documents, isEmpty);
    });

    test('a retry after a failure works', () async {
      final service = FlakyDocumentService()..failUpload = NetworkException();
      final container = await containerWith(service);
      final controller = container.read(vaultControllerProvider.notifier);

      await controller.upload(sampleUpload());
      service.failUpload = null;

      expect(await controller.upload(sampleUpload()), isNotNull);
      expect(container.read(vaultControllerProvider).error, isNull);
      expect(service.uploadCalls, 2);
    });

    test('an expired session surfaces as an error', () async {
      final service = FlakyDocumentService()
        ..failUpload = UnauthorizedException();
      final container = await containerWith(service);

      await container
          .read(vaultControllerProvider.notifier)
          .upload(sampleUpload());

      expect(
        container.read(vaultControllerProvider).error,
        contains('sign in again'),
      );
    });

    test('deleting refreshes the vault', () async {
      final container = await containerWith(MockDocumentService());
      final controller = container.read(vaultControllerProvider.notifier);

      final document = await controller.upload(sampleUpload());
      expect(await controller.delete(document!.id), isTrue);

      expect(await container.read(documentsProvider.future), isEmpty);
    });

    test('a failed delete keeps the document', () async {
      final service = FlakyDocumentService();
      final container = await containerWith(service);
      final controller = container.read(vaultControllerProvider.notifier);

      final document = await controller.upload(sampleUpload());
      service.failDelete = ServerException();

      expect(await controller.delete(document!.id), isFalse);
      expect(await container.read(documentsProvider.future), hasLength(1));
      expect(container.read(vaultControllerProvider).error, isNotNull);
    });

    test('opening returns the bytes, and reports a failure', () async {
      final service = FlakyDocumentService();
      final container = await containerWith(service);
      final controller = container.read(vaultControllerProvider.notifier);

      final document = await controller.upload(sampleUpload());
      expect(await controller.open(document!.id), isNotNull);

      service.failDownload = NetworkException();
      expect(await controller.open(document.id), isNull);
      expect(container.read(vaultControllerProvider).error, isNotNull);
    });
  });

  // --- The screens ---------------------------------------------------------

  group('screens', () {
    testWidgets('an empty vault says so', (tester) async {
      await pumpScreen(tester, const VaultScreen());
      await settle(tester);

      expect(find.text('Your vault is empty'), findsOneWidget);
      expect(find.text('Upload a document'), findsOneWidget);
    });

    testWidgets('a stored document is listed with what it is', (tester) async {
      await MockDocumentService().upload(sampleUpload(name: 'March statement'));

      await pumpScreen(tester, const VaultScreen());
      await settle(tester);

      expect(find.text('March statement'), findsOneWidget);
      expect(find.textContaining('Bank ·'), findsOneWidget);
      expect(find.textContaining('Stored '), findsOneWidget);
      // Never a verification badge: nothing has verified it.
      expect(find.byIcon(Icons.verified_rounded), findsNothing);
    });

    testWidgets('a load failure offers a retry', (tester) async {
      final service = FlakyDocumentService()..failList = NetworkException();

      await pumpScreen(
        tester,
        const VaultScreen(),
        overrides: [documentServiceProvider.overrideWithValue(service)],
      );
      await settle(tester);

      expect(find.textContaining('Could not reach FynnEdge'), findsOneWidget);
      expect(find.textContaining('ApiException'), findsNothing);

      service.failList = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);

      expect(find.text('Your vault is empty'), findsOneWidget);
    });

    testWidgets('the add screen says what storing does and does not do', (
      tester,
    ) async {
      await pumpScreen(tester, const ScanScreen(), size: const Size(420, 1400));
      await settle(tester);

      expect(find.text('What happens to it'), findsOneWidget);
      expect(find.textContaining('Only you can open it'), findsOneWidget);
      expect(find.textContaining('Nothing reads it'), findsOneWidget);
      expect(
        find.textContaining('nothing is sent to a provider'),
        findsOneWidget,
      );

      // No claim the implementation cannot support. Phrases only, and only
      // ones that cannot appear inside a denial — "Nothing is verified" is
      // the opposite of a verification claim, so the word alone proves
      // nothing either way.
      for (final claim in const [
        'end-to-end',
        'bank-grade',
        'military-grade',
        'KYC',
        'shared with lenders',
        'sent to the lender',
        'we verify',
        'we check your documents',
      ]) {
        expect(
          find.textContaining(claim),
          findsNothing,
          reason: 'the screen claims "$claim"',
        );
      }

      // And the denials are actually on the screen.
      expect(find.textContaining('Nothing is verified'), findsOneWidget);
    });

    testWidgets('choosing a file and storing it really stores it', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ScanScreen(),
        size: const Size(420, 1600),
        overrides: [
          documentPickerProvider.overrideWithValue(FakeDocumentPicker()),
        ],
      );
      await settle(tester);

      await tester.tap(find.text('Choose from device'));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'Salary slip');
      await tester.tap(find.text('Identity'));
      await settle(tester);

      await tester.tap(find.text('Store in FynnVault'));
      await settle(tester);

      final stored = MockStore.instance.documents.single;
      expect(stored.name, 'Salary slip');
      expect(stored.category, DocumentCategory.identity);
      expect(MockStore.instance.documentBytes(stored.id), isNotNull);
    });

    testWidgets('an upload failure is shown and stores nothing', (
      tester,
    ) async {
      final service = FlakyDocumentService()..failUpload = ServerException();

      await pumpScreen(
        tester,
        const ScanScreen(),
        size: const Size(420, 1600),
        overrides: [
          documentServiceProvider.overrideWithValue(service),
          documentPickerProvider.overrideWithValue(FakeDocumentPicker()),
        ],
      );
      await settle(tester);

      await tester.tap(find.text('Choose from device'));
      await settle(tester);
      await tester.tap(find.text('Store in FynnVault'));
      await settle(tester);

      expect(find.textContaining('Something went wrong'), findsOneWidget);
      expect(MockStore.instance.documents, isEmpty);
    });
  });
}
