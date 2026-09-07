import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/error_text.dart';
import '../../data/models/credit.dart';
import '../../data/services/api_client.dart';

/// Why a check could not happen. Each one is a different thing to tell the
/// customer, and none of them is a score.
enum CreditFailure {
  /// No bureau is connected to this deployment.
  notConfigured,

  /// The customer has not permitted a credit check.
  consentRequired,

  /// The bureau did not answer. FynnEdge has no information — which is not
  /// the same as bad information.
  bureauUnavailable,

  /// Too many checks in a short time. A pull may cost money and may be
  /// recorded as an enquiry, so this limit protects the customer.
  tooManyChecks,

  /// Anything else.
  other;

  static CreditFailure from(Object error) => switch (error) {
    CapabilityUnavailableException() => CreditFailure.notConfigured,
    PermissionRequiredException(:final reason)
        when reason == 'consent_required' =>
      CreditFailure.consentRequired,
    UpstreamUnavailableException() => CreditFailure.bureauUnavailable,
    RateLimitedException() => CreditFailure.tooManyChecks,
    _ => CreditFailure.other,
  };
}

class CreditScreenState {
  const CreditScreenState({
    this.credit,
    this.loading = true,
    this.loadError,
    this.checking = false,
    this.failure,
    this.failureMessage,
  });

  final CreditState? credit;
  final bool loading;
  final Object? loadError;

  /// A check the customer asked for, in flight.
  final bool checking;

  /// Why the last check did not produce information. Held separately from
  /// [credit] because a failure never replaces a report and never becomes
  /// one.
  final CreditFailure? failure;
  final String? failureMessage;

  CreditScreenState copyWith({
    CreditState? credit,
    bool? loading,
    Object? loadError,
    bool clearLoadError = false,
    bool? checking,
    CreditFailure? failure,
    String? failureMessage,
    bool clearFailure = false,
  }) => CreditScreenState(
    credit: credit ?? this.credit,
    loading: loading ?? this.loading,
    loadError: clearLoadError ? null : (loadError ?? this.loadError),
    checking: checking ?? this.checking,
    failure: clearFailure ? null : (failure ?? this.failure),
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
  );
}

/// Credit information on screen.
///
/// The one rule that shapes this whole class: a check happens when the
/// customer taps the button, and at no other time. Not on load, not on
/// refresh, not on returning to the screen. A bureau request may cost money
/// and may be recorded as an enquiry against the customer, so it is theirs
/// to initiate.
class CreditController extends Notifier<CreditScreenState> {
  @override
  CreditScreenState build() {
    Future.microtask(load);
    return const CreditScreenState();
  }

  /// Reads what FynnEdge already holds. Asks no bureau.
  Future<void> load() async {
    state = state.copyWith(loading: true, clearLoadError: true);

    try {
      final credit = await ref.read(creditRepositoryProvider).status();
      if (!ref.mounted) return;
      state = CreditScreenState(credit: credit, loading: false);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, loadError: e);
    }
  }

  /// The check, and only from an explicit tap.
  Future<bool> check() async {
    if (state.checking) return false;

    state = state.copyWith(checking: true, clearFailure: true);

    try {
      final credit = await ref.read(creditRepositoryProvider).check();
      if (!ref.mounted) return false;
      state = state.copyWith(credit: credit, checking: false);
      return true;
    } on Object catch (e) {
      if (!ref.mounted) return false;

      // The previous report, if there was one, stays exactly as it was. A
      // failure is not new information about the customer's credit.
      state = state.copyWith(
        checking: false,
        failure: CreditFailure.from(e),
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

final creditControllerProvider =
    NotifierProvider<CreditController, CreditScreenState>(
      CreditController.new,
    );
