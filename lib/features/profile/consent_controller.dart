import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/error_text.dart';
import '../../data/models/consent.dart';
import '../ai/ai_controller.dart';

/// What the Privacy screen is doing right now.
class ConsentScreenState {
  const ConsentScreenState({
    this.state,
    this.loading = true,
    this.loadError,
    this.busyType,
    this.actionError,
  });

  final ConsentState? state;
  final bool loading;
  final Object? loadError;

  /// The one switch currently being saved, so only it shows as busy.
  final ConsentType? busyType;

  /// A failed change. The switch stays where the server says it is.
  final String? actionError;

  bool isBusy(ConsentType type) => busyType == type;

  ConsentScreenState copyWith({
    ConsentState? state,
    bool? loading,
    Object? loadError,
    bool clearLoadError = false,
    ConsentType? busyType,
    bool clearBusy = false,
    String? actionError,
    bool clearActionError = false,
  }) => ConsentScreenState(
    state: state ?? this.state,
    loading: loading ?? this.loading,
    loadError: clearLoadError ? null : (loadError ?? this.loadError),
    busyType: clearBusy ? null : (busyType ?? this.busyType),
    actionError: clearActionError ? null : (actionError ?? this.actionError),
  );
}

/// Grants and withdrawals, applied server-first.
///
/// The switch follows the server's answer rather than moving optimistically:
/// a consent shown as granted when the record was never written is the one
/// mistake this screen must not make.
class ConsentController extends Notifier<ConsentScreenState> {
  @override
  ConsentScreenState build() {
    Future.microtask(load);
    return const ConsentScreenState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearLoadError: true);

    try {
      final consents = await ref.read(consentServiceProvider).getConsents();
      if (!ref.mounted) return;
      state = ConsentScreenState(state: consents, loading: false);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, loadError: e);
    }
  }

  Future<bool> set(ConsentType type, bool granted) async {
    if (state.busyType != null) return false;

    state = state.copyWith(busyType: type, clearActionError: true);

    try {
      final service = ref.read(consentServiceProvider);
      final updated = granted
          ? await service.grant(type)
          : await service.withdraw(type);

      if (!ref.mounted) return false;
      state = state.copyWith(state: updated, clearBusy: true);

      _refreshWhatConsentGates(type);
      return true;
    } on Object catch (e) {
      if (!ref.mounted) return false;
      state = state.copyWith(clearBusy: true, actionError: messageFor(e));
      return false;
    }
  }

  /// What a consent decision actually changes.
  ///
  /// AI memory gates whether FynnAI uses the customer's figures, so a change
  /// has to reach it immediately rather than at the next cold start.
  void _refreshWhatConsentGates(ConsentType type) {
    if (type == ConsentType.aiMemory) {
      ref.invalidate(chatProvider);
    }
  }

  void clearActionError() {
    if (state.actionError == null) return;
    state = state.copyWith(clearActionError: true);
  }
}

final consentControllerProvider =
    NotifierProvider<ConsentController, ConsentScreenState>(
      ConsentController.new,
    );

/// The customer's decisions, newest first.
final consentHistoryProvider = FutureProvider<List<ConsentRecord>>(
  (ref) => ref.watch(consentServiceProvider).getHistory(),
);

/// Whether FynnAI may use the customer's own figures.
///
/// Read by the AI controller, so withdrawing the consent stops it using them
/// rather than merely changing a switch on a settings page.
final aiMemoryConsentProvider = FutureProvider<bool>((ref) async {
  final consents = await ref.watch(consentServiceProvider).getConsents();
  return consents.isGranted(ConsentType.aiMemory);
});
