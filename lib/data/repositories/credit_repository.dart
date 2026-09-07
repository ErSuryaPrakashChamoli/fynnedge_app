import '../models/credit.dart';
import '../services/credit_service.dart';

/// The one place the app asks about credit information.
///
/// Thin on purpose. There is nothing to derive here: a bureau score is a
/// fact obtained from a third party, and any arithmetic FynnEdge performed
/// on it would be FynnEdge's opinion wearing a bureau's authority.
///
/// What this seam is for is the boundary itself — every screen goes through
/// it, so when a real bureau replaces the current one, nothing above this
/// line changes.
class CreditRepository {
  CreditRepository(this._service);
  final CreditService _service;

  /// What FynnEdge already holds. Safe to call on any screen: it never
  /// causes a bureau to be asked, so it can never cost the customer an
  /// enquiry.
  Future<CreditState> status() => _service.getStatus();

  /// A check, because the customer asked for one.
  ///
  /// Only ever called from an explicit action. Never on screen load, never
  /// on a refresh, never in the background.
  Future<CreditState> check() => _service.check();
}
