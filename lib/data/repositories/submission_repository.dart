import '../models/submission.dart';
import '../services/submission_service.dart';

/// The one place the app asks about external submission.
///
/// Thin on purpose. The server's canonical outcome is authoritative: nothing
/// here infers a submission state from an HTTP status, because a 200 from
/// FynnEdge says only that FynnEdge handled the request.
class SubmissionRepository {
  SubmissionRepository(this._service);
  final SubmissionService _service;

  /// Where it stands. Sends nothing.
  Future<ApplicationSubmission> status(String applicationId) =>
      _service.statusFor(applicationId);

  /// Sends it, from an explicit customer action and no other trigger.
  Future<ApplicationSubmission> submit(String applicationId) =>
      _service.submit(applicationId);
}
