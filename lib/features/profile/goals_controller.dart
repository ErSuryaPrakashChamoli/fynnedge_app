import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/error_text.dart';
import '../../data/models/goal.dart';
import '../../data/services/api_client.dart';
import '../home/home_controller.dart';
import 'profile_controller.dart';

/// Everything the Goals screen and its editor need, in one value.
class GoalsState {
  const GoalsState({
    this.goals = const [],
    this.loading = true,
    this.loadError,
    this.busy = false,
    this.actionError,
    this.fieldErrors = const {},
    this.changedAt,
  });

  final List<Goal> goals;
  final bool loading;

  /// Set when the list could not be fetched at all.
  final Object? loadError;

  /// True while a create, update or delete is in flight. Blocks a second
  /// submission and drives the editor's spinner.
  final bool busy;

  /// A create/update/delete failure the customer can retry.
  final String? actionError;

  /// Server validation, keyed by the field the server named.
  final Map<String, String> fieldErrors;

  /// Drives the transient success confirmation.
  final DateTime? changedAt;

  bool get isEmpty => !loading && loadError == null && goals.isEmpty;

  GoalsState copyWith({
    List<Goal>? goals,
    bool? loading,
    Object? loadError,
    bool? busy,
    String? actionError,
    Map<String, String>? fieldErrors,
    DateTime? changedAt,
    bool clearLoadError = false,
    bool clearActionError = false,
  }) => GoalsState(
    goals: goals ?? this.goals,
    loading: loading ?? this.loading,
    loadError: clearLoadError ? null : (loadError ?? this.loadError),
    busy: busy ?? this.busy,
    actionError: clearActionError ? null : (actionError ?? this.actionError),
    fieldErrors: fieldErrors ?? this.fieldErrors,
    changedAt: changedAt ?? this.changedAt,
  );
}

/// The outcome of a create/update/delete, so the editor knows whether to
/// close or stay open showing errors.
enum GoalActionResult { success, validationFailed, failed, unauthorized }

class GoalsController extends Notifier<GoalsState> {
  @override
  GoalsState build() {
    Future.microtask(load);
    return const GoalsState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearLoadError: true);
    try {
      final goals = await ref.read(profileRepositoryProvider).getGoals();
      if (!ref.mounted) return;
      state = GoalsState(goals: goals, loading: false);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, loadError: e);
    }
  }

  Future<GoalActionResult> create(Goal goal) =>
      _mutate(() => ref.read(profileRepositoryProvider).createGoal(goal));

  Future<GoalActionResult> update(Goal goal) =>
      _mutate(() => ref.read(profileRepositoryProvider).updateGoal(goal));

  Future<GoalActionResult> delete(String id) =>
      _mutate(() => ref.read(profileRepositoryProvider).deleteGoal(id));

  /// One path for every write, so the busy guard, error mapping and refresh
  /// behave identically whichever operation the customer performed.
  Future<GoalActionResult> _mutate(Future<void> Function() action) async {
    // Guards a double tap: a second call while busy is ignored outright.
    if (state.busy) return GoalActionResult.failed;

    state = state.copyWith(
      busy: true,
      clearActionError: true,
      fieldErrors: const {},
    );

    try {
      await action();
      if (!ref.mounted) return GoalActionResult.success;

      // Re-read rather than patching the list locally: the server owns
      // ordering and every derived figure.
      final goals = await ref.read(profileRepositoryProvider).getGoals();
      if (!ref.mounted) return GoalActionResult.success;

      state = GoalsState(
        goals: goals,
        loading: false,
        changedAt: DateTime.now(),
      );
      _refreshDependentScreens();
      return GoalActionResult.success;
    } on ValidationException catch (e) {
      if (!ref.mounted) return GoalActionResult.validationFailed;
      state = state.copyWith(
        busy: false,
        actionError: e.hasFieldErrors ? null : e.message,
        fieldErrors: {
          for (final entry in e.errors.entries)
            if (entry.value.isNotEmpty) entry.key: entry.value.first,
        },
      );
      return GoalActionResult.validationFailed;
    } on UnauthorizedException {
      // The ApiClient has already signalled the global handler, which clears
      // the session and routes to Welcome.
      if (ref.mounted) state = state.copyWith(busy: false);
      return GoalActionResult.unauthorized;
    } on Object catch (e) {
      if (!ref.mounted) return GoalActionResult.failed;
      state = state.copyWith(busy: false, actionError: messageFor(e));
      return GoalActionResult.failed;
    }
  }

  /// Home shows the customer's first goal, so it must not keep rendering one
  /// that has just been renamed or deleted.
  void _refreshDependentScreens() {
    ref.invalidate(goalsProvider);
    ref.invalidate(homeSnapshotProvider);
  }

  /// Clears validation as soon as the customer edits, so a corrected field
  /// does not keep its old complaint.
  void clearErrors() {
    if (state.fieldErrors.isEmpty && state.actionError == null) return;
    state = state.copyWith(fieldErrors: const {}, clearActionError: true);
  }
}

final goalsControllerProvider = NotifierProvider<GoalsController, GoalsState>(
  GoalsController.new,
);
