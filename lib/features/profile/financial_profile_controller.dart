import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/error_text.dart';
import '../../data/models/user.dart';
import '../twin/twin_controller.dart';
import '../../data/services/api_client.dart';
import '../home/home_controller.dart';
import '../loans/loan_controller.dart';
import 'profile_controller.dart';

/// Everything the Financial Profile screen needs to render, in one value.
///
/// The screen is a pure function of this; it owns no business state of its
/// own beyond the text fields the customer is typing into.
class FinancialProfileState {
  const FinancialProfileState({
    this.saved,
    this.draft,
    this.loading = true,
    this.saving = false,
    this.loadError,
    this.saveError,
    this.fieldErrors = const {},
    this.savedAt,
  });

  /// What the server last confirmed. Carries the server's derived values.
  final FinancialProfile? saved;

  /// Local edits, if any. Null means the customer has changed nothing.
  final FinancialProfile? draft;

  final bool loading;
  final bool saving;

  /// Set when the profile could not be fetched at all.
  final Object? loadError;

  /// Set when a save failed. The draft is deliberately kept so the customer
  /// does not lose what they entered.
  final String? saveError;

  /// Server validation, keyed by the field the server named.
  final Map<String, String> fieldErrors;

  /// Drives the transient success confirmation.
  final DateTime? savedAt;

  /// What the screen should display: the draft while editing, otherwise the
  /// server's copy.
  FinancialProfile? get current => draft ?? saved;

  bool get hasUnsavedChanges =>
      draft != null && saved != null && !draft!.hasSameFiguresAs(saved!);

  bool get canSave => hasUnsavedChanges && !saving;

  /// True once loaded but with nothing filled in — a customer who has not
  /// told us anything yet.
  bool get isEmpty =>
      !loading && loadError == null && (saved?.monthlyIncome ?? 0) <= 0;

  FinancialProfileState copyWith({
    FinancialProfile? saved,
    FinancialProfile? draft,
    bool? loading,
    bool? saving,
    Object? loadError,
    String? saveError,
    Map<String, String>? fieldErrors,
    DateTime? savedAt,
    bool clearDraft = false,
    bool clearLoadError = false,
    bool clearSaveError = false,
  }) => FinancialProfileState(
    saved: saved ?? this.saved,
    draft: clearDraft ? null : (draft ?? this.draft),
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    loadError: clearLoadError ? null : (loadError ?? this.loadError),
    saveError: clearSaveError ? null : (saveError ?? this.saveError),
    fieldErrors: fieldErrors ?? this.fieldErrors,
    savedAt: savedAt ?? this.savedAt,
  );
}

class FinancialProfileController extends Notifier<FinancialProfileState> {
  @override
  FinancialProfileState build() {
    // Kick the first load without blocking the first frame, so the screen can
    // show its loading state immediately.
    Future.microtask(load);
    return const FinancialProfileState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearLoadError: true);
    try {
      final profile = await ref
          .read(profileRepositoryProvider)
          .getFinancialProfile();
      // The customer can leave the screen mid-request; writing state to a
      // disposed provider throws.
      if (!ref.mounted) return;
      // A reload replaces the server's copy, never the customer's unsaved
      // edits. Nothing calls load() over an open draft today; the day
      // something does — a pull-to-refresh, a retry — it must not silently
      // discard figures they have typed and not yet saved.
      state = FinancialProfileState(
        saved: profile,
        draft: state.draft,
        loading: false,
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, loadError: e);
    }
  }

  /// Records a local edit. Clears any stale validation for the fields the
  /// customer has just touched, so errors do not linger over corrected input.
  void edit(FinancialProfile draft) {
    state = state.copyWith(
      draft: draft,
      fieldErrors: const {},
      clearSaveError: true,
    );
  }

  /// Throws nothing: every outcome is represented in the state.
  /// Returns true when the server accepted the change.
  Future<bool> save() async {
    final draft = state.draft;
    // Guards a double tap: a second call while saving is ignored outright.
    if (draft == null || state.saving) return false;

    state = state.copyWith(
      saving: true,
      clearSaveError: true,
      fieldErrors: const {},
    );

    try {
      final result = await ref
          .read(profileRepositoryProvider)
          .updateFinancialProfile(draft);

      if (!ref.mounted) return true;

      // The server's response replaces local state wholesale, so derived
      // values on screen are the ones it just calculated.
      state = FinancialProfileState(
        saved: result,
        loading: false,
        savedAt: DateTime.now(),
      );

      refreshDependentScreens();
      return true;
    } on ValidationException catch (e) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        saving: false,
        saveError: e.hasFieldErrors ? null : e.message,
        fieldErrors: {
          for (final entry in e.errors.entries)
            if (entry.value.isNotEmpty) entry.key: entry.value.first,
        },
      );
      return false;
    } on UnauthorizedException {
      // The ApiClient has already signalled the global handler, which clears
      // the session and routes to Welcome. Nothing to show here.
      if (ref.mounted) state = state.copyWith(saving: false);
      return false;
    } on Object catch (e) {
      // The draft survives, so a retry does not cost the customer their work.
      if (!ref.mounted) return false;
      state = state.copyWith(saving: false, saveError: messageFor(e));
      return false;
    }
  }

  /// Anything that reads the customer's financial figures must be refreshed
  /// from one place, or a screen keeps showing a number the customer has
  /// already changed.
  ///
  /// FynnScore is included because all three of its dimensions are derived
  /// from this profile. Goals are not: they do not feed the numerical score.
  /// FynnMatch is, because a changed income or EMI load changes both which
  /// products fit and what the affordability check says about them.
  ///
  /// FynnTwin is not invalidated but its last result is dropped: a
  /// projection compares a scenario against the position the customer was
  /// in, and that position has just changed. The assumptions they entered
  /// are left alone — only the answer to a question about the old figures
  /// goes.
  /// Public so the other route into this data — confirming a figure
  /// FynnScan read off a document — goes down this exact path. A second
  /// invalidation mechanism would be a second definition of what a changed
  /// income affects.
  void refreshDependentScreens() {
    ref.invalidate(financialProfileProvider);
    ref.invalidate(fynnScoreProvider);
    ref.invalidate(homeSnapshotProvider);
    ref.invalidate(fynnMatchProvider);
    ref.read(twinControllerProvider.notifier).discardStaleResult();
  }

  /// Abandons local edits and returns to the server's copy.
  void discardChanges() {
    state = state.copyWith(
      clearDraft: true,
      clearSaveError: true,
      fieldErrors: const {},
    );
  }
}

final financialProfileControllerProvider =
    NotifierProvider<FinancialProfileController, FinancialProfileState>(
      FinancialProfileController.new,
    );
