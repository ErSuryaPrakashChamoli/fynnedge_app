import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/error_text.dart';
import '../../data/models/kyc.dart';
import '../../data/services/api_client.dart';
import '../profile/profile_controller.dart';

/// Why a check could not happen.
///
/// Every one of these is a failure of the check, never a finding about the
/// customer — which is why none of them is a verification status.
enum KycFailure {
  /// No verification service is connected to this deployment.
  notConfigured,

  /// FynnEdge does not verify this kind of document.
  unsupportedDocument,

  /// The customer has not permitted identity verification.
  consentRequired,

  /// The service did not answer. FynnEdge knows nothing new.
  providerUnavailable,

  /// Too many checks in a short time.
  tooManyChecks,

  /// The stored file could not be read.
  documentMissing,

  other;

  static KycFailure from(Object error) => switch (error) {
    CapabilityUnavailableException(:final reason)
        when reason == 'document_type_not_verifiable' =>
      KycFailure.unsupportedDocument,
    CapabilityUnavailableException() => KycFailure.notConfigured,
    PermissionRequiredException(:final reason) when reason == 'consent_required' =>
      KycFailure.consentRequired,
    UpstreamUnavailableException() => KycFailure.providerUnavailable,
    RateLimitedException() => KycFailure.tooManyChecks,
    ApiException(statusCode: 409) => KycFailure.documentMissing,
    _ => KycFailure.other,
  };
}

class KycScreenState {
  const KycScreenState({
    this.verification,
    this.loading = true,
    this.loadError,
    this.checking = false,
    this.busyField,
    this.failure,
    this.failureMessage,
  });

  final KycVerification? verification;
  final bool loading;
  final Object? loadError;

  /// A check the customer asked for, in flight.
  final bool checking;

  /// The one difference currently being resolved.
  final String? busyField;

  final KycFailure? failure;
  final String? failureMessage;

  bool isBusy(String field) => busyField == field;

  KycScreenState copyWith({
    KycVerification? verification,
    bool? loading,
    Object? loadError,
    bool clearLoadError = false,
    bool? checking,
    String? busyField,
    bool clearBusy = false,
    KycFailure? failure,
    String? failureMessage,
    bool clearFailure = false,
  }) => KycScreenState(
    verification: verification ?? this.verification,
    loading: loading ?? this.loading,
    loadError: clearLoadError ? null : (loadError ?? this.loadError),
    checking: checking ?? this.checking,
    busyField: clearBusy ? null : (busyField ?? this.busyField),
    failure: clearFailure ? null : (failure ?? this.failure),
    failureMessage: clearFailure ? null : (failureMessage ?? this.failureMessage),
  );
}

/// Identity verification on screen.
///
/// Two rules shape this class.
///
/// A document goes to a verification service when the customer taps the
/// button, and at no other time — a check may be billed per call, so it is
/// theirs to ask for.
///
/// And a verified value reaches the customer's profile only when they choose
/// that specific outcome for that specific difference. There is no path here
/// that writes a name FynnEdge was not explicitly told to write.
class KycController extends Notifier<KycScreenState> {
  KycController(this.documentId);

  final String documentId;

  @override
  KycScreenState build() {
    Future.microtask(load);
    return const KycScreenState();
  }

  /// Reads what FynnEdge already holds. Asks no provider.
  Future<void> load() async {
    state = state.copyWith(loading: true, clearLoadError: true);

    try {
      final result = await ref.read(kycRepositoryProvider).status(documentId);
      if (!ref.mounted) return;
      state = KycScreenState(verification: result, loading: false);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, loadError: e);
    }
  }

  /// The check, and only from an explicit tap.
  Future<bool> verify({bool force = false}) async {
    if (state.checking) return false;

    state = state.copyWith(checking: true, clearFailure: true);

    try {
      final result = await ref
          .read(kycRepositoryProvider)
          .verify(documentId, force: force);
      if (!ref.mounted) return false;
      state = state.copyWith(verification: result, checking: false);
      return true;
    } on Object catch (e) {
      if (!ref.mounted) return false;

      // Whatever was established before stays exactly as it was. A failure
      // is not new information about the customer or their document.
      state = state.copyWith(
        checking: false,
        failure: KycFailure.from(e),
        failureMessage: messageFor(e),
      );
      return false;
    }
  }

  Future<bool> keepProfile(String field) => _resolve(
    field,
    (repo) => repo.keepProfile(documentId, field),
    changesProfile: false,
  );

  Future<bool> updateProfile(String field) => _resolve(
    field,
    (repo) => repo.updateProfile(documentId, field),
    changesProfile: true,
  );

  Future<bool> _resolve(
    String field,
    Future<KycVerification> Function(dynamic repo) action, {
    required bool changesProfile,
  }) async {
    if (state.busyField != null) return false;

    state = state.copyWith(busyField: field, clearFailure: true);

    try {
      final result = await action(ref.read(kycRepositoryProvider));
      if (!ref.mounted) return false;

      state = state.copyWith(verification: result, clearBusy: true);

      if (changesProfile) {
        // The customer's own details changed, so what reads them is
        // refreshed. A name is not a financial figure, so this is the
        // profile provider and nothing else: FynnScore, Home and FynnMatch
        // depend on money, and none of it moved.
        ref.invalidate(userProfileProvider);
      }

      return true;
    } on Object catch (e) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        clearBusy: true,
        failure: KycFailure.from(e),
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
final kycControllerProvider =
    NotifierProvider.family<KycController, KycScreenState, String>(
      KycController.new,
    );
