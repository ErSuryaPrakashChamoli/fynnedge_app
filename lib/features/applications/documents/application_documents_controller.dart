import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/utils/error_text.dart';
import '../../../data/models/application_documents.dart';
import '../../../data/services/api_client.dart';

/// Why a document action could not happen.
///
/// None of these is a statement about a lender, because nothing here
/// involves one.
enum DocumentActionFailure {
  /// The application can no longer be changed.
  notEditable,

  /// This application does not ask for that document.
  unknownRequirement,

  /// The chosen document is not the kind this requirement asks for.
  wrongType,

  /// The document is gone from the vault.
  unavailable,

  /// Nothing has been chosen to confirm.
  nothingSelected,

  other;

  static DocumentActionFailure from(Object error) => switch (error) {
    NotFoundException() => DocumentActionFailure.unknownRequirement,
    ApiException(statusCode: 409) => DocumentActionFailure.unavailable,
    _ => DocumentActionFailure.other,
  };
}

class DocumentsScreenState {
  const DocumentsScreenState({
    this.checklist,
    this.loading = true,
    this.loadError,
    this.busyCode,
    this.failure,
    this.failureMessage,
  });

  final DocumentChecklist? checklist;
  final bool loading;
  final Object? loadError;

  /// The one requirement currently being acted on, so only its row is busy.
  final String? busyCode;

  final DocumentActionFailure? failure;
  final String? failureMessage;

  bool isBusy(String code) => busyCode == code;

  DocumentsScreenState copyWith({
    DocumentChecklist? checklist,
    bool? loading,
    Object? loadError,
    bool clearLoadError = false,
    String? busyCode,
    bool clearBusy = false,
    DocumentActionFailure? failure,
    String? failureMessage,
    bool clearFailure = false,
  }) => DocumentsScreenState(
    checklist: checklist ?? this.checklist,
    loading: loading ?? this.loading,
    loadError: clearLoadError ? null : (loadError ?? this.loadError),
    busyCode: clearBusy ? null : (busyCode ?? this.busyCode),
    failure: clearFailure ? null : (failure ?? this.failure),
    failureMessage: clearFailure ? null : (failureMessage ?? this.failureMessage),
  );
}

/// An application's documents on screen.
///
/// Readiness is never computed here. Every action returns the server's
/// checklist, and that is what is rendered — so a document deleted from the
/// vault shows as missing the moment anybody looks, without this class
/// having to know that could happen.
///
/// Nothing here submits an application. Documents becoming ready is not a
/// trigger; the customer chooses to proceed, separately.
class ApplicationDocumentsController extends Notifier<DocumentsScreenState> {
  ApplicationDocumentsController(this.applicationId);

  final String applicationId;

  @override
  DocumentsScreenState build() {
    Future.microtask(load);
    return const DocumentsScreenState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearLoadError: true);

    try {
      final checklist = await ref
          .read(applicationDocumentsRepositoryProvider)
          .checklist(applicationId);
      if (!ref.mounted) return;
      state = DocumentsScreenState(checklist: checklist, loading: false);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, loadError: e);
    }
  }

  Future<bool> attach(String code, String documentId) => _act(
    code,
    (repo) => repo.attach(applicationId, code, documentId),
  );

  Future<bool> detach(String code) =>
      _act(code, (repo) => repo.detach(applicationId, code));

  Future<bool> confirm(String code) =>
      _act(code, (repo) => repo.confirm(applicationId, code));

  Future<bool> reject(String code) =>
      _act(code, (repo) => repo.reject(applicationId, code));

  Future<bool> _act(
    String code,
    Future<DocumentChecklist> Function(dynamic repo) action,
  ) async {
    if (state.busyCode != null) return false;

    state = state.copyWith(busyCode: code, clearFailure: true);

    try {
      final checklist =
          await action(ref.read(applicationDocumentsRepositoryProvider));
      if (!ref.mounted) return false;

      // The server's checklist, rendered as it came. Nothing is patched
      // locally, so there is no way for the two to drift.
      state = state.copyWith(checklist: checklist, clearBusy: true);
      return true;
    } on Object catch (e) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        clearBusy: true,
        failure: DocumentActionFailure.from(e),
        failureMessage: messageFor(e),
      );
      return false;
    }
  }

  void clearFailure() {
    if (state.failure == null) return;
    state = state.copyWith(clearFailure: true);
  }
}

/// One controller per application.
final applicationDocumentsProvider =
    NotifierProvider.family<
      ApplicationDocumentsController,
      DocumentsScreenState,
      String
    >(ApplicationDocumentsController.new);
