import 'dart:typed_data';

import 'package:fynnedge/data/services/document_picker.dart';
import 'package:fynnedge/features/vault/sample_document.dart';

/// A picker whose answer the test decides.
///
/// Stands in for the platform file dialog, which cannot open in a widget
/// test — and should not, since what is being tested is what the app does
/// with a file, not that a platform dialog works.
class FakeDocumentPicker implements DocumentPicker {
  FakeDocumentPicker({
    this.fileName = 'March statement.pdf',
    this.mimeType = 'application/pdf',
    Uint8List? bytes,
    this.failure,
  }) : bytes = bytes ?? SampleDocument.bytes();

  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  /// Set to make the picker fail instead of returning a file.
  PickerFailure? failure;

  int calls = 0;
  List<String>? lastExtensions;

  @override
  Future<PickerResult> pick({required List<String> extensions}) async {
    calls++;
    lastExtensions = extensions;

    if (failure != null) return PickerResult.failed(failure!);

    return PickerResult.picked(
      PickedDocument(fileName: fileName, mimeType: mimeType, bytes: bytes),
    );
  }
}
