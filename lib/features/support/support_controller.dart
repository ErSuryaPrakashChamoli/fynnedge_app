import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/support.dart';
import '../../data/services/api_client.dart';

/// Why a request could not be made. Each is a different thing to tell the
/// customer, and none of them is "something went wrong".
enum SupportFailure {
  /// The thing they said it was about is not theirs, or is gone.
  contextUnavailable,

  /// The request is already closed.
  caseClosed,

  /// Too many requests in an hour. Not a fault of theirs.
  tooMany,

  /// The form was not accepted.
  invalid,

  offline,
  other;

  static SupportFailure from(Object error) => switch (error) {
    RateLimitedException() => SupportFailure.tooMany,
    NetworkException() => SupportFailure.offline,
    ApiException(statusCode: 409) => SupportFailure.caseClosed,
    ApiException(statusCode: 422) => SupportFailure.invalid,
    _ => SupportFailure.other,
  };
}

/// The list of a customer's requests.
class SupportHomeState {
  const SupportHomeState({
    this.categories = const [],
    this.cases = const [],
    this.loading = true,
    this.loadError,
  });

  final List<SupportCategoryOption> categories;
  final List<SupportCase> cases;
  final bool loading;

  /// Held, not thrown. A list that could not load is an error with a retry,
  /// never a reason to lose the session.
  final Object? loadError;

  bool get isEmpty => cases.isEmpty && !loading && loadError == null;

  SupportHomeState copyWith({
    List<SupportCategoryOption>? categories,
    List<SupportCase>? cases,
    bool? loading,
    Object? loadError,
    bool clearError = false,
  }) => SupportHomeState(
    categories: categories ?? this.categories,
    cases: cases ?? this.cases,
    loading: loading ?? this.loading,
    loadError: clearError ? null : (loadError ?? this.loadError),
  );
}

class SupportController extends Notifier<SupportHomeState> {
  @override
  SupportHomeState build() {
    Future.microtask(load);
    return const SupportHomeState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);

    try {
      final repository = ref.read(supportRepositoryProvider);

      // Both together: the screen offers categories and lists requests, and
      // showing one without the other is a half-loaded screen.
      final categories = await repository.categories();
      final cases = await repository.cases();

      if (!ref.mounted) return;

      state = SupportHomeState(
        categories: categories,
        cases: cases,
        loading: false,
      );
    } on Object catch (e) {
      if (!ref.mounted) return;

      // Offline is not signed out.
      state = state.copyWith(loading: false, loadError: e);
    }
  }

  /// Raises a request. Returns the case, or null when it could not be made.
  Future<SupportCase?> create(SupportRequestDraft draft) async {
    try {
      final created = await ref.read(supportRepositoryProvider).create(draft);
      await load();
      return created;
    } on Object {
      return null;
    }
  }
}

final supportControllerProvider =
    NotifierProvider<SupportController, SupportHomeState>(
      SupportController.new,
    );

/// One request, read fresh.
///
/// Its own provider rather than a field on the list state: a customer
/// opening a request wants what is true now, and a stale copy from a list
/// loaded ten minutes ago is the wrong thing to show about their own case.
final supportCaseProvider = FutureProvider.family<SupportCase, String>(
  (ref, id) => ref.watch(supportRepositoryProvider).read(id),
);

/// What the categories offer, for the request form.
final supportCategoriesProvider = FutureProvider<List<SupportCategoryOption>>(
  (ref) => ref.watch(supportRepositoryProvider).categories(),
);
