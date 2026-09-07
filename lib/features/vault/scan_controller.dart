import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/error_text.dart';
import '../../data/models/scan.dart';
import '../../data/services/api_client.dart';
import '../profile/financial_profile_controller.dart';

/// Why a reading could not happen. Each is a different thing to tell the
/// customer, and none of them is an extraction.
enum ScanFailure {
  /// No document-reading service is connected to this deployment.
  notConfigured,

  /// FynnScan does not read this kind of document.
  unsupportedDocument,

  /// The customer has not permitted document processing.
  consentRequired,

  /// The provider did not answer. FynnEdge has no information — which is
  /// not the same as the document being unreadable by anyone.
  providerUnavailable,

  /// Too many readings in a short time. Document intelligence is billed per
  /// page, so this limit protects the customer.
  tooManyScans,

  /// The stored file could not be read.
  documentMissing,

  other;

  static ScanFailure from(Object error) => switch (error) {
    CapabilityUnavailableException(:final reason)
        when reason == 'document_family_not_supported' =>
      ScanFailure.unsupportedDocument,
    CapabilityUnavailableException() => ScanFailure.notConfigured,
    PermissionRequiredException(:final reason) when reason == 'consent_required' =>
      ScanFailure.consentRequired,
    UpstreamUnavailableException() => ScanFailure.providerUnavailable,
    RateLimitedException() => ScanFailure.tooManyScans,
    ApiException(statusCode: 409) => ScanFailure.documentMissing,
    _ => ScanFailure.other,
  };
}

class ScanScreenState {
  const ScanScreenState({
    this.scan,
    this.loading = true,
    this.loadError,
    this.scanning = false,
    this.busyField,
    this.failure,
    this.failureMessage,
    this.savedToProfile = false,
  });

  final DocumentScan? scan;
  final bool loading;
  final Object? loadError;

  /// A reading the customer asked for, in flight.
  final bool scanning;

  /// The one field currently being decided, so only it shows as busy.
  final String? busyField;

  final ScanFailure? failure;
  final String? failureMessage;

  /// Set once a confirmed figure has reached the customer's profile, so the
  /// screen can say so plainly — and say only that.
  final bool savedToProfile;

  bool isBusy(String fieldKey) => busyField == fieldKey;

  ScanScreenState copyWith({
    DocumentScan? scan,
    bool? loading,
    Object? loadError,
    bool clearLoadError = false,
    bool? scanning,
    String? busyField,
    bool clearBusy = false,
    ScanFailure? failure,
    String? failureMessage,
    bool clearFailure = false,
    bool? savedToProfile,
  }) => ScanScreenState(
    scan: scan ?? this.scan,
    loading: loading ?? this.loading,
    loadError: clearLoadError ? null : (loadError ?? this.loadError),
    scanning: scanning ?? this.scanning,
    busyField: clearBusy ? null : (busyField ?? this.busyField),
    failure: clearFailure ? null : (failure ?? this.failure),
    failureMessage: clearFailure ? null : (failureMessage ?? this.failureMessage),
    savedToProfile: savedToProfile ?? this.savedToProfile,
  );
}

/// FynnScan on screen.
///
/// Two rules shape this class.
///
/// A document is sent to a provider when the customer taps the button, and
/// at no other time. Not on load, not on refresh, not on returning to the
/// screen — a reading may be billed per page, so it is theirs to ask for.
///
/// And nothing read from a document reaches the customer's financial profile
/// unless they say so on that specific field. Confirming records that the
/// document was read correctly; saving is a further, separate act.
class ScanController extends Notifier<ScanScreenState> {
  ScanController(this.documentId);

  final String documentId;
  @override
  ScanScreenState build() {
    Future.microtask(load);
    return const ScanScreenState();
  }

  /// Reads what FynnEdge already holds. Asks no provider.
  Future<void> load() async {
    state = state.copyWith(loading: true, clearLoadError: true);

    try {
      final scan = await ref.read(scanRepositoryProvider).status(documentId);
      if (!ref.mounted) return;
      state = ScanScreenState(scan: scan, loading: false);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, loadError: e);
    }
  }

  /// The reading, and only from an explicit tap.
  Future<bool> scan({bool force = false}) async {
    if (state.scanning) return false;

    state = state.copyWith(scanning: true, clearFailure: true);

    try {
      final scan = await ref.read(scanRepositoryProvider).scan(documentId, force: force);
      if (!ref.mounted) return false;
      state = state.copyWith(scan: scan, scanning: false);
      return true;
    } on Object catch (e) {
      if (!ref.mounted) return false;

      // Whatever was read before stays exactly as it was. A failure is not
      // new information about what the document contains.
      state = state.copyWith(
        scanning: false,
        failure: ScanFailure.from(e),
        failureMessage: messageFor(e),
      );
      return false;
    }
  }

  Future<bool> confirm(String fieldKey, {bool save = false}) =>
      _decide(fieldKey, (repo) => repo.confirm(documentId, fieldKey, applyToProfile: save), save);

  Future<bool> correct(String fieldKey, String value, {bool save = false}) =>
      _decide(fieldKey, (repo) => repo.correct(documentId, fieldKey, value, applyToProfile: save), save);

  Future<bool> reject(String fieldKey) =>
      _decide(fieldKey, (repo) => repo.reject(documentId, fieldKey), false);

  Future<bool> _decide(
    String fieldKey,
    Future<DocumentScan> Function(dynamic repo) action,
    bool save,
  ) async {
    if (state.busyField != null) return false;

    state = state.copyWith(busyField: fieldKey, clearFailure: true);

    try {
      final scan = await action(ref.read(scanRepositoryProvider));
      if (!ref.mounted) return false;

      state = state.copyWith(
        scan: scan,
        clearBusy: true,
        savedToProfile: save || state.savedToProfile,
      );

      if (save) {
        // The customer's figures genuinely changed, so everything that
        // depends on them is refreshed — down the one existing path, not a
        // second one built for documents.
        ref
            .read(financialProfileControllerProvider.notifier)
            .refreshDependentScreens();
      }

      return true;
    } on Object catch (e) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        clearBusy: true,
        failure: ScanFailure.from(e),
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

/// One controller per document.
final scanControllerProvider = NotifierProvider.family<
  ScanController,
  ScanScreenState,
  String
>(ScanController.new);
