import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/error_text.dart';
import '../../data/models/submission.dart';
import '../../data/services/api_client.dart';
import '../home/home_controller.dart';

/// Why a submission could not happen.
///
/// Every one of these is a fact about a delivery attempt, never a lending
/// decision — which is why none of them is an application status.
enum SubmissionFailure {
  /// No submission channel is connected to this deployment.
  notConfigured,

  /// The customer has not permitted external submission.
  consentRequired,

  /// The application is not in a state that can be sent.
  notSubmittable,

  /// This product has no mapping to anything the provider recognises.
  mappingMissing,

  /// The provider is unreachable or refused.
  providerUnavailable,

  /// Too many attempts in a short time.
  tooManyAttempts,

  other;

  static SubmissionFailure from(Object error) => switch (error) {
    CapabilityUnavailableException() => SubmissionFailure.notConfigured,
    PermissionRequiredException(:final reason)
        when reason == 'submission_consent_required' =>
      SubmissionFailure.consentRequired,
    RateLimitedException() => SubmissionFailure.tooManyAttempts,
    UpstreamUnavailableException() => SubmissionFailure.providerUnavailable,
    ApiException(statusCode: 409) => SubmissionFailure.notSubmittable,
    _ => SubmissionFailure.other,
  };
}

class SubmissionScreenState {
  const SubmissionScreenState({
    this.submission,
    this.loading = true,
    this.loadError,
    this.submitting = false,
    this.failure,
    this.failureMessage,
  });

  final ApplicationSubmission? submission;
  final bool loading;
  final Object? loadError;

  /// An attempt the customer asked for, in flight.
  final bool submitting;

  final SubmissionFailure? failure;
  final String? failureMessage;

  SubmissionScreenState copyWith({
    ApplicationSubmission? submission,
    bool? loading,
    Object? loadError,
    bool clearLoadError = false,
    bool? submitting,
    SubmissionFailure? failure,
    String? failureMessage,
    bool clearFailure = false,
  }) => SubmissionScreenState(
    submission: submission ?? this.submission,
    loading: loading ?? this.loading,
    loadError: clearLoadError ? null : (loadError ?? this.loadError),
    submitting: submitting ?? this.submitting,
    failure: clearFailure ? null : (failure ?? this.failure),
    failureMessage: clearFailure ? null : (failureMessage ?? this.failureMessage),
  );
}

/// External submission on screen.
///
/// Two rules shape this class.
///
/// An application is sent when the customer taps the button, and at no other
/// time. Not on load, not on refresh, not on opening Application Detail — a
/// submission may create an application at a third party.
///
/// And the state shown is the server's, never inferred. A successful HTTP
/// response is FynnEdge saying it handled the request; whether a provider
/// received anything is a separate fact that only the server can report.
class SubmissionController extends Notifier<SubmissionScreenState> {
  SubmissionController(this.applicationId);

  final String applicationId;

  @override
  SubmissionScreenState build() {
    Future.microtask(load);
    return const SubmissionScreenState();
  }

  /// Reads where it stands. Sends nothing.
  Future<void> load() async {
    state = state.copyWith(loading: true, clearLoadError: true);

    try {
      final result = await ref
          .read(submissionRepositoryProvider)
          .status(applicationId);
      if (!ref.mounted) return;
      state = SubmissionScreenState(submission: result, loading: false);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, loadError: e);
    }
  }

  /// The submission, and only from an explicit tap.
  Future<bool> submit() async {
    if (state.submitting) return false;

    state = state.copyWith(submitting: true, clearFailure: true);

    try {
      final result = await ref
          .read(submissionRepositoryProvider)
          .submit(applicationId);
      if (!ref.mounted) return false;

      state = state.copyWith(submission: result, submitting: false);

      // An attempt happened, so what counts applications is refreshed —
      // down the existing invalidation path, not a second one.
      ref.invalidate(homeSnapshotProvider);

      return true;
    } on Object catch (e) {
      if (!ref.mounted) return false;

      // Whatever was recorded before stays exactly as it was. A refused
      // request is not new information about a previous attempt.
      state = state.copyWith(
        submitting: false,
        failure: SubmissionFailure.from(e),
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
final submissionControllerProvider =
    NotifierProvider.family<
      SubmissionController,
      SubmissionScreenState,
      String
    >(SubmissionController.new);
