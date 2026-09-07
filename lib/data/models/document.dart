import '../../core/utils/clock.dart';
import 'json.dart';

/// The document kinds FynnVault represents. Unchanged from what the product
/// has always shown — a larger taxonomy would be inventing filing rules
/// nothing asks for.
enum DocumentCategory {
  identity('identity', 'Identity'),
  income('income', 'Income'),
  bank('bank', 'Bank'),
  loan('loan', 'Loan'),
  property('property', 'Property'),
  other('other', 'Other');

  const DocumentCategory(this.id, this.label);
  final String id;
  final String label;

  static DocumentCategory fromId(String? id) => J.enumById(
    DocumentCategory.values,
    id,
    (c) => c.id,
    DocumentCategory.other,
  );
}

/// What has happened to a document.
///
/// Two states, because two things can happen: the bytes were stored, or they
/// were not. FynnEdge does not verify, process or reject documents, so there
/// is no status saying it did.
enum DocumentStatus {
  uploaded('uploaded', 'Stored'),
  failed('failed', 'Upload failed');

  const DocumentStatus(this.id, this.label);
  final String id;
  final String label;

  static DocumentStatus fromId(String? id) =>
      J.enumById(DocumentStatus.values, id, (s) => s.id, DocumentStatus.uploaded);
}

/// One document in the customer's vault.
///
/// Carries no storage location: where a file lives is the server's business,
/// and the only way to the bytes is an authenticated download.
class VaultDocument {
  const VaultDocument({
    required this.id,
    required this.name,
    required this.category,
    required this.uploadedAt,
    this.originalFilename = '',
    this.sizeBytes = 0,
    this.status = DocumentStatus.uploaded,
    this.mimeType = 'application/pdf',
    this.updatedAt,
  });

  final String id;
  final String name;
  final String originalFilename;
  final DocumentCategory category;
  final DateTime uploadedAt;
  final DateTime? updatedAt;
  final int sizeBytes;
  final DocumentStatus status;
  final String mimeType;

  /// Nothing in FynnEdge verifies a document or sends one anywhere. These
  /// are constants rather than fields so no payload can flip them on.
  bool get isVerified => false;
  bool get isShared => false;

  bool get isImage => mimeType.startsWith('image/');
  bool get isPdf => mimeType == 'application/pdf';

  String get sizeLabel => sizeBytes >= 1048576
      ? '${(sizeBytes / 1048576).toStringAsFixed(1)} MB'
      : '${(sizeBytes / 1024).ceil()} KB';

  factory VaultDocument.fromJson(Map<String, dynamic> json) => VaultDocument(
    id: J.str(json['id']),
    name: J.str(json['name']),
    originalFilename: J.str(json['original_filename']),
    category: DocumentCategory.fromId(J.strOrNull(json['type'])),
    uploadedAt: J.date(json['uploaded_at']) ?? AppClock.now(),
    updatedAt: J.date(json['updated_at']),
    sizeBytes: J.integer(json['size_bytes']),
    status: DocumentStatus.fromId(J.strOrNull(json['status'])),
    mimeType: J.str(json['mime_type'], 'application/pdf'),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'original_filename': originalFilename,
    'type': category.id,
    'type_label': category.label,
    'uploaded_at': uploadedAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'size_bytes': sizeBytes,
    'size_label': sizeLabel,
    'status': status.id,
    'status_label': status.label,
    'is_verified': isVerified,
    'is_shared': isShared,
    'mime_type': mimeType,
  };
}

/// What FynnVault accepts, as the server reports it.
class VaultLimits {
  const VaultLimits({
    this.maxBytes = 10 * 1024 * 1024,
    this.maxSizeLabel = '10 MB',
    this.mimeTypes = const [
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/heic',
      'image/webp',
    ],
    this.extensions = const ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'webp'],
  });

  final int maxBytes;
  final String maxSizeLabel;
  final List<String> mimeTypes;
  final List<String> extensions;

  bool accepts(String mimeType) => mimeTypes.contains(mimeType);

  factory VaultLimits.fromJson(Map<String, dynamic> json) => VaultLimits(
    maxBytes: J.integer(json['max_bytes'], 10 * 1024 * 1024),
    maxSizeLabel: J.str(json['max_size_label'], '10 MB'),
    mimeTypes: J.strings(json['mime_types']),
    extensions: J.strings(json['extensions']),
  );

  Map<String, dynamic> toJson() => {
    'max_bytes': maxBytes,
    'max_size_label': maxSizeLabel,
    'mime_types': mimeTypes,
    'extensions': extensions,
  };
}
