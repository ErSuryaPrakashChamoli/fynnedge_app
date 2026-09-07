import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/error_text.dart';
import '../../data/models/application.dart';
import '../../data/models/match.dart';
import '../../data/services/application_service.dart';
import '../home/home_controller.dart';

final applicationsProvider = FutureProvider<List<LoanApplication>>((ref) async {
  return ref.watch(applicationServiceProvider).getApplications();
});

final applicationProvider = FutureProvider.family<LoanApplication, String>((
  ref,
  id,
) async {
  return ref.watch(applicationServiceProvider).getApplication(id);
});

/// Where the Review screen is in the act of applying.
class ApplicationFlowState {
  const ApplicationFlowState({
    this.application,
    this.busy = false,
    this.error,
    this.acknowledged = false,
  });

  /// The draft, once started.
  final LoanApplication? application;

  /// True while a request is in flight. The submit button is disabled on it,
  /// but it is not what prevents a duplicate — the idempotency key is.
  final bool busy;

  final String? error;

  /// Both statements confirmed. Submission is refused without it, here and
  /// on the server.
  final bool acknowledged;

  bool get canSubmit => acknowledged && !busy && application != null;

  /// True only once the server (or mock gateway) confirmed the submission.
  bool get isSubmitted => application?.status == ApplicationStatus.submitted;

  ApplicationFlowState copyWith({
    LoanApplication? application,
    bool? busy,
    String? error,
    bool clearError = false,
    bool? acknowledged,
  }) => ApplicationFlowState(
    application: application ?? this.application,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
    acknowledged: acknowledged ?? this.acknowledged,
  );
}

/// Drives Review → Submit for one product.
///
/// The customer's chosen amount, tenure and product are passed in once and
/// never re-derived: nothing here may substitute a default for them.
class ApplicationFlowController extends Notifier<ApplicationFlowState> {
  @override
  ApplicationFlowState build() => const ApplicationFlowState();

  /// One key per attempt at applying, generated when the flow starts. The
  /// server treats a repeat with the same key as the same operation, so a
  /// double tap, a retry after a dropped response, or a rebuild cannot
  /// produce a second application.
  String? _idempotencyKey;

  void reset() {
    _idempotencyKey = null;
    state = const ApplicationFlowState();
  }

  void setAcknowledged(bool value) =>
      state = state.copyWith(acknowledged: value, clearError: true);

  /// Creates the draft for a product the customer chose, at exactly the
  /// figures they were shown.
  Future<LoanApplication?> start(ProductMatch match) async {
    if (state.busy) return state.application;

    // Already started for this product: keep the draft rather than making
    // another one.
    if (state.application?.productId == match.product.id) {
      return state.application;
    }

    _idempotencyKey ??=
        'app-${match.product.id}-${AppClock.now().microsecondsSinceEpoch}';

    state = state.copyWith(busy: true, clearError: true);

    try {
      final application = await ref
          .read(applicationServiceProvider)
          .create(
            ApplicationDraft(
              productId: match.product.id,
              amount: match.pricing.amount,
              tenureMonths: match.pricing.tenureMonths,
            ),
            idempotencyKey: _idempotencyKey!,
          );

      if (!ref.mounted) return null;
      state = state.copyWith(application: application, busy: false);

      // A started application is one the customer has, so the two screens
      // that count what they have are now out of date. Submitting already
      // did this; starting did not, and Home went on saying nothing was in
      // flight until something else happened to refresh it.
      ref.invalidate(applicationsProvider);
      ref.invalidate(homeSnapshotProvider);

      return application;
    } on Object catch (e) {
      if (!ref.mounted) return null;
      state = state.copyWith(busy: false, error: messageFor(e));
      return null;
    }
  }

  /// Sends it. Returns true only if the submission was actually accepted.
  Future<bool> submit() async {
    final application = state.application;
    if (application == null || state.busy || !state.acknowledged) return false;

    state = state.copyWith(busy: true, clearError: true);

    try {
      final submitted = await ref
          .read(applicationServiceProvider)
          .submit(application.id);

      if (!ref.mounted) return false;
      state = state.copyWith(application: submitted, busy: false);

      _refreshDependentScreens();
      return submitted.status == ApplicationStatus.submitted;
    } on Object catch (e) {
      if (!ref.mounted) return false;
      // The application stays exactly as it was. A failed submission must
      // never leave a success on screen.
      state = state.copyWith(busy: false, error: messageFor(e));
      return false;
    }
  }

  /// What an application changes, and nothing else.
  ///
  /// FynnScore and FynnMatch read the customer's financial profile, which an
  /// application does not touch, so they are deliberately left alone.
  void _refreshDependentScreens() {
    ref.invalidate(applicationsProvider);
    ref.invalidate(homeSnapshotProvider);
  }
}

final applicationFlowProvider =
    NotifierProvider<ApplicationFlowController, ApplicationFlowState>(
      ApplicationFlowController.new,
    );

/// Cancelling from the detail screen.
final applicationActionsProvider = Provider<ApplicationActions>(
  ApplicationActions.new,
);

class ApplicationActions {
  ApplicationActions(this._ref);
  final Ref _ref;

  Future<LoanApplication?> cancel(String id) async {
    try {
      final cancelled = await _ref.read(applicationServiceProvider).cancel(id);

      _ref.invalidate(applicationsProvider);
      _ref.invalidate(applicationProvider(id));
      _ref.invalidate(homeSnapshotProvider);
      return cancelled;
    } on Object {
      return null;
    }
  }
}
