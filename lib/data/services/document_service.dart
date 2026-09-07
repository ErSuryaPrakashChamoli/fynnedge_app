import 'dart:typed_data';

import '../../core/utils/clock.dart';
import '../mock/mock_store.dart';
import '../models/document.dart';
import 'api_client.dart';
import 'api_config.dart';

/// A file the customer is adding, in memory.
///
/// The bytes travel with it: FynnEdge uploads what it was handed rather than
/// a path, so nothing downstream has to trust a filename.
class DocumentUpload {
  const DocumentUpload({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.category,
    this.name,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final DocumentCategory category;

  /// What the customer wants it called. Falls back to the filename.
  final String? name;

  int get sizeBytes => bytes.length;
}

/// FynnVault: the customer's own documents.
///
/// There is no OCR, no verification and no sharing here, because there is
/// none in the product. Storing a document stores it.
abstract class DocumentService {
  Future<List<VaultDocument>> getDocuments();
  Future<VaultDocument> getDocument(String id);
  Future<VaultLimits> getLimits();
  Future<VaultDocument> upload(DocumentUpload upload);

  /// The document's bytes, fetched through an authenticated request. There
  /// is no URL that reaches them without one.
  Future<Uint8List> download(String id);

  Future<void> delete(String id);
}

class MockDocumentService implements DocumentService {
  MockDocumentService([MockStore? store]) : _store = store ?? MockStore.instance;

  final MockStore _store;

  static const VaultLimits limits = VaultLimits();

  @override
  Future<List<VaultDocument>> getDocuments() async {
    await ApiConfig.pause();
    return _store.documents;
  }

  @override
  Future<VaultDocument> getDocument(String id) async {
    await ApiConfig.pauseFast();
    return _find(id);
  }

  @override
  Future<VaultLimits> getLimits() async {
    await ApiConfig.pauseFast();
    return limits;
  }

  @override
  Future<VaultDocument> upload(DocumentUpload upload) async {
    await ApiConfig.pause();

    // The same refusals the API makes, so mock mode cannot accept something
    // the real vault would reject.
    if (!limits.accepts(upload.mimeType)) {
      throw ApiException(
        'FynnVault takes PDFs and photos (JPG, PNG, HEIC, WebP).',
        statusCode: 422,
      );
    }

    if (upload.sizeBytes <= 0 || upload.sizeBytes > limits.maxBytes) {
      throw ApiException(
        'That file is larger than ${limits.maxSizeLabel}.',
        statusCode: 422,
      );
    }

    final document = VaultDocument(
      id: _store.nextDocumentId(),
      name: (upload.name?.trim().isNotEmpty ?? false)
          ? upload.name!.trim()
          : _baseName(upload.fileName),
      originalFilename: _safeName(upload.fileName),
      category: upload.category,
      uploadedAt: AppClock.now(),
      updatedAt: AppClock.now(),
      sizeBytes: upload.sizeBytes,
      mimeType: upload.mimeType,
      // Stored. Not checked, not verified, not sent anywhere.
      status: DocumentStatus.uploaded,
    );

    _store.addDocument(document, upload.bytes);
    return document;
  }

  @override
  Future<Uint8List> download(String id) async {
    await ApiConfig.pauseFast();
    _find(id);

    final bytes = _store.documentBytes(id);
    if (bytes == null) {
      throw ApiException('That document is no longer stored.', statusCode: 404);
    }
    return bytes;
  }

  @override
  Future<void> delete(String id) async {
    await ApiConfig.pauseFast();
    _find(id);
    _store.removeDocument(id);
  }

  VaultDocument _find(String id) {
    final match = _store.documents.where((d) => d.id == id);
    if (match.isEmpty) {
      throw ApiException(
        'That document could not be found.',
        statusCode: 404,
      );
    }
    return match.first;
  }

  /// Display name from a filename, without its extension.
  static String _baseName(String fileName) {
    final safe = _safeName(fileName);
    final dot = safe.lastIndexOf('.');
    return dot > 0 ? safe.substring(0, dot) : safe;
  }

  /// Strips anything that makes a name a path. Display only either way.
  static String _safeName(String fileName) {
    final name = fileName.replaceAll('\\', '/').split('/').last;
    final cleaned = name.replaceAll(RegExp(r'^\.+'), '');
    return cleaned.isEmpty ? 'document' : cleaned;
  }
}

class ApiDocumentService implements DocumentService {
  ApiDocumentService(this._api);
  final ApiClient _api;

  @override
  Future<List<VaultDocument>> getDocuments() async =>
      (await _api.get('/documents') as List)
          .map((e) => VaultDocument.fromJson(e as Map<String, dynamic>))
          .toList();

  @override
  Future<VaultDocument> getDocument(String id) async => VaultDocument.fromJson(
    await _api.get('/documents/$id') as Map<String, dynamic>,
  );

  @override
  Future<VaultLimits> getLimits() async => VaultLimits.fromJson(
    await _api.get('/documents/limits') as Map<String, dynamic>,
  );

  @override
  Future<VaultDocument> upload(DocumentUpload upload) async =>
      VaultDocument.fromJson(
        await _api.upload(
              '/documents',
              bytes: upload.bytes,
              fileName: upload.fileName,
              mimeType: upload.mimeType,
              fields: {
                'type': upload.category.id,
                if (upload.name != null) 'name': upload.name!,
              },
            )
            as Map<String, dynamic>,
      );

  @override
  Future<Uint8List> download(String id) =>
      _api.getBytes('/documents/$id/download');

  @override
  Future<void> delete(String id) => _api.delete('/documents/$id');
}
