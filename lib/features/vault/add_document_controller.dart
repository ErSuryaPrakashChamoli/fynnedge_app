import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/document.dart';
import '../../data/services/document_picker.dart';
import '../../data/models/scan.dart';
import '../../data/services/document_service.dart';
import 'vault_controller.dart';

/// Which step of adding a document the customer is on.
enum AddDocumentStep {
  /// Nothing chosen yet.
  choose,

  /// A file is in hand: name it, file it, check it, then store it.
  review,

  /// Stored in FynnVault.
  stored,
}

class AddDocumentState {
  const AddDocumentState({
    this.step = AddDocumentStep.choose,
    this.picked,
    this.type = DocumentCategory.bank,
    this.picking = false,
    this.uploading = false,
    this.error,
    this.stored,
  });

  final AddDocumentStep step;

  /// The chosen file, held in memory until the customer stores it.
  final PickedDocument? picked;
  final DocumentCategory type;

  final bool picking;
  final bool uploading;
  final String? error;

  /// What FynnVault stored, once it did.
  final VaultDocument? stored;

  bool get busy => picking || uploading;

  AddDocumentState copyWith({
    AddDocumentStep? step,
    PickedDocument? picked,
    DocumentCategory? type,
    bool? picking,
    bool? uploading,
    String? error,
    bool clearError = false,
    VaultDocument? stored,
  }) => AddDocumentState(
    step: step ?? this.step,
    picked: picked ?? this.picked,
    type: type ?? this.type,
    picking: picking ?? this.picking,
    uploading: uploading ?? this.uploading,
    error: clearError ? null : (error ?? this.error),
    stored: stored ?? this.stored,
  );
}

/// Choose a file, file it, store it.
///
/// Nothing here reads the document. Storing a document stores it, and the
/// screens say so.
class AddDocumentController extends Notifier<AddDocumentState> {
  @override
  AddDocumentState build() => const AddDocumentState();

  void reset() => state = const AddDocumentState();

  void setType(DocumentCategory type) => state = state.copyWith(type: type);

  /// Asks the device for a file.
  ///
  /// A cancelled picker is not an error and leaves no message behind: the
  /// customer changed their mind, which is not a failure to report.
  Future<void> choose() async {
    if (state.busy) return;
    state = state.copyWith(picking: true, clearError: true);

    final limits = ref.read(vaultLimitsProvider).value ?? const VaultLimits();

    final result = await ref
        .read(documentPickerProvider)
        .pick(extensions: pickerExtensions(limits));

    if (!ref.mounted) return;

    if (!result.isPicked) {
      state = state.copyWith(
        picking: false,
        error: switch (result.failure) {
          PickerFailure.cancelled => null,
          PickerFailure.unreadable =>
            'That file could not be read. Try choosing it again.',
          _ =>
            'Your device did not offer a file picker. You can add documents '
                'from a device that has one.',
        },
        clearError: result.wasCancelled,
      );
      return;
    }

    final picked = result.document!;

    // Refused here as well as on the server, so the customer hears why
    // before spending an upload on it.
    if (!limits.accepts(picked.mimeType)) {
      state = state.copyWith(
        picking: false,
        error:
            'FynnVault takes PDFs and photos. ${picked.fileName} is not one '
            'of those.',
      );
      return;
    }

    if (picked.sizeBytes > limits.maxBytes) {
      state = state.copyWith(
        picking: false,
        error:
            '${picked.fileName} is ${picked.sizeLabel}, over the '
            '${limits.maxSizeLabel} limit.',
      );
      return;
    }

    state = state.copyWith(
      picking: false,
      picked: picked,
      step: AddDocumentStep.review,
    );
  }

  /// Stores it through FynnVault — the same path, ownership and validation
  /// every document goes through.
  Future<VaultDocument?> store({String? name}) async {
    final picked = state.picked;
    if (picked == null || state.busy) return null;

    state = state.copyWith(uploading: true, clearError: true);

    final document = await ref
        .read(vaultControllerProvider.notifier)
        .upload(
          DocumentUpload(
            bytes: picked.bytes,
            fileName: picked.fileName,
            mimeType: picked.mimeType,
            category: state.type,
            name: name,
          ),
        );

    if (!ref.mounted) return null;

    if (document == null) {
      // Nothing was stored. The file is still in hand, so the customer can
      // try again without choosing it a second time.
      state = state.copyWith(
        uploading: false,
        error:
            ref.read(vaultControllerProvider).error ??
            'That document could not be stored.',
      );
      return null;
    }

    state = state.copyWith(
      uploading: false,
      stored: document,
      step: AddDocumentStep.stored,
    );
    return document;
  }

  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(clearError: true);
  }
}

final addDocumentProvider =
    NotifierProvider<AddDocumentController, AddDocumentState>(
      AddDocumentController.new,
    );

/// The scan state of one document.
final documentScanProvider = FutureProvider.family<DocumentScan, String>(
  (ref, documentId) async =>
      ref.watch(documentScanServiceProvider).statusFor(documentId),
);
