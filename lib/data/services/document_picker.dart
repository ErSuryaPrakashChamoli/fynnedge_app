import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';

import '../models/document.dart';

/// A file the customer chose, as the rest of the app sees it.
///
/// Deliberately not a platform file object: nothing above the data layer
/// should know whether the bytes came from a phone's document provider, a
/// desktop file dialog, or a test.
class PickedDocument {
  const PickedDocument({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  int get sizeBytes => bytes.length;

  String get sizeLabel => sizeBytes >= 1048576
      ? '${(sizeBytes / 1048576).toStringAsFixed(1)} MB'
      : '${(sizeBytes / 1024).ceil()} KB';

  String get extension {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(dot + 1).toLowerCase() : '';
  }
}

/// Why a selection produced nothing.
enum PickerFailure {
  /// The customer backed out. Not an error, and not worth an error message.
  cancelled,

  /// The platform handed back a reference it could not read.
  unreadable,

  /// The platform refused the request — no permission, no picker.
  unavailable,
}

/// The result of asking the customer for a file.
class PickerResult {
  const PickerResult.picked(this.document) : failure = null;
  const PickerResult.failed(this.failure) : document = null;

  final PickedDocument? document;
  final PickerFailure? failure;

  bool get isPicked => document != null;
  bool get wasCancelled => failure == PickerFailure.cancelled;
}

/// Asks the customer for a file.
abstract class DocumentPicker {
  /// [extensions] is the vault's allowlist, so the platform dialog offers
  /// only what FynnVault would accept.
  Future<PickerResult> pick({required List<String> extensions});
}

/// The real one, wrapping file_picker.
///
/// Everything platform-shaped stops here: the caller gets bytes, a name and
/// a MIME type, or a reason it got nothing.
class PlatformDocumentPicker implements DocumentPicker {
  const PlatformDocumentPicker();

  @override
  Future<PickerResult> pick({required List<String> extensions}) async {
    PlatformFile? file;

    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: extensions,
        dialogTitle: 'Choose a document',
      );
    } on Object {
      // A missing picker, a denied permission, a platform with no file
      // dialog: all of them mean the customer cannot choose a file here.
      return const PickerResult.failed(PickerFailure.unavailable);
    }

    if (file == null) {
      return const PickerResult.failed(PickerFailure.cancelled);
    }

    late final Uint8List bytes;

    try {
      // Read here, in the data layer, so nothing above it deals in file
      // handles or platform paths.
      bytes = await file.readAsBytes();
    } on Object {
      return const PickerResult.failed(PickerFailure.unreadable);
    }

    if (bytes.isEmpty) {
      return const PickerResult.failed(PickerFailure.unreadable);
    }

    return PickerResult.picked(
      PickedDocument(
        fileName: file.name,
        mimeType: resolveMimeType(file.name, bytes),
        bytes: bytes,
      ),
    );
  }

  /// The type of the file, from its own first bytes where possible.
  ///
  /// A name can say anything; the header cannot. The server checks this
  /// again regardless — this is so the app can refuse early and explain
  /// itself, not so the server can trust it.
  static String resolveMimeType(String fileName, Uint8List bytes) =>
      lookupMimeType(
        fileName,
        headerBytes: bytes.take(defaultMagicNumbersMaxLength).toList(),
      ) ??
      'application/octet-stream';
}

/// Nothing to pick from. Used where a platform picker cannot run.
class UnavailableDocumentPicker implements DocumentPicker {
  const UnavailableDocumentPicker();

  @override
  Future<PickerResult> pick({required List<String> extensions}) async =>
      const PickerResult.failed(PickerFailure.unavailable);
}

/// What the vault will take, as a picker filter.
List<String> pickerExtensions(VaultLimits limits) =>
    limits.extensions.isEmpty ? const ['pdf'] : limits.extensions;
