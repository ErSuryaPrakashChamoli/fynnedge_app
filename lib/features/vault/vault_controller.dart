import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/error_text.dart';
import '../home/home_controller.dart';
import '../../data/models/document.dart';
import '../../data/services/document_service.dart';

final documentsProvider = FutureProvider<List<VaultDocument>>((ref) async {
  return ref.watch(documentServiceProvider).getDocuments();
});

final vaultLimitsProvider = FutureProvider<VaultLimits>((ref) async {
  return ref.watch(documentServiceProvider).getLimits();
});

/// Where an upload or a deletion has got to.
class VaultActionState {
  const VaultActionState({
    this.uploading = false,
    this.deletingId,
    this.error,
    this.lastUploaded,
  });

  final bool uploading;
  final String? deletingId;
  final String? error;

  /// The document just added, so the screen can point at it.
  final VaultDocument? lastUploaded;

  bool get busy => uploading || deletingId != null;

  bool isDeleting(String id) => deletingId == id;
}

/// Adding and removing documents.
///
/// Nothing here inspects a file, verifies it, or sends it anywhere: the vault
/// stores what the customer put in it, and that is the whole of it.
class VaultController extends Notifier<VaultActionState> {
  @override
  VaultActionState build() => const VaultActionState();

  Future<VaultDocument?> upload(DocumentUpload upload) async {
    if (state.busy) return null;
    state = const VaultActionState(uploading: true);

    try {
      final document = await ref.read(documentServiceProvider).upload(upload);

      if (!ref.mounted) return null;
      state = VaultActionState(lastUploaded: document);
      ref.invalidate(documentsProvider);
      // Home shows how many documents are stored, so it has just changed.
      ref.invalidate(homeSnapshotProvider);
      return document;
    } on Object catch (e) {
      if (!ref.mounted) return null;
      // The vault is unchanged. A failed upload must never leave a document
      // on screen that was never stored.
      state = VaultActionState(error: messageFor(e));
      return null;
    }
  }

  Future<bool> delete(String id) async {
    if (state.busy) return false;
    state = VaultActionState(deletingId: id);

    try {
      await ref.read(documentServiceProvider).delete(id);
      if (!ref.mounted) return false;
      state = const VaultActionState();
      ref.invalidate(documentsProvider);
      ref.invalidate(homeSnapshotProvider);
      return true;
    } on Object catch (e) {
      if (!ref.mounted) return false;
      state = VaultActionState(error: messageFor(e));
      return false;
    }
  }

  /// The document's bytes, for viewing or saving. Fetched with the
  /// customer's token every time.
  Future<Uint8List?> open(String id) async {
    try {
      return await ref.read(documentServiceProvider).download(id);
    } on Object catch (e) {
      if (!ref.mounted) return null;
      state = VaultActionState(error: messageFor(e));
      return null;
    }
  }

  void clearError() {
    if (state.error == null) return;
    state = const VaultActionState();
  }
}

final vaultControllerProvider =
    NotifierProvider<VaultController, VaultActionState>(VaultController.new);
