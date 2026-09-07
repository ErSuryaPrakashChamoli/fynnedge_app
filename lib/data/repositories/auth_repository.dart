import '../models/user.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/local_store.dart';

/// Owns the session. Controllers talk to this, never to AuthService directly.
class AuthRepository {
  AuthRepository(this._service, this._store, this._api) {
    // A token persisted on a previous launch has to reach the client before
    // the first request goes out.
    _api.setToken(_store.token);
  }

  final AuthService _service;
  final LocalStore _store;
  final ApiClient _api;

  bool get isLoggedIn => _store.hasLiveToken;
  bool get onboardingComplete => _store.onboardingComplete;

  UserProfile? get cachedProfile {
    final json = _store.profile;
    return json == null ? null : UserProfile.fromJson(json);
  }

  Future<OtpChallenge> sendOtp(String mobile) => _service.sendOtp(mobile);

  Future<AuthSession> verifyOtp({
    required String mobile,
    required String reference,
    required String code,
  }) async {
    final session = await _service.verifyOtp(
      mobile: mobile,
      reference: reference,
      code: code,
    );
    await _store.setToken(session.token, expiresAt: session.expiresAt);
    await _store.setProfile(session.profile.toJson());
    _api.setToken(session.token);
    return session;
  }

  /// Confirms a stored token is still good. Returns null when there is no
  /// session, or when the server has rejected the one we had.
  Future<UserProfile?> restoreSession() async {
    if (!_store.hasLiveToken) {
      // An expired token is dead weight; drop it rather than sending it.
      if (_store.token != null) await clearSession();
      return null;
    }

    _api.setToken(_store.token);

    try {
      final profile = await _service.currentUser();
      await _store.setProfile(profile.toJson());
      return profile;
    } on UnauthorizedException {
      await clearSession();
      return null;
    } on NetworkException {
      // Offline is not signed out. Fall back to what we last knew, so the
      // customer is not thrown to the sign-in screen by a dropped connection.
      return cachedProfile;
    }
  }

  Future<void> cacheProfile(UserProfile profile) =>
      _store.setProfile(profile.toJson());

  Future<void> completeOnboarding() => _store.setOnboardingComplete(true);

  Future<void> logout() async {
    try {
      await _service.logout();
    } catch (_) {
      // Local sign-out must succeed even if the server call fails.
    }
    await clearSession();
  }

  /// Drops every trace of the session locally. Used by logout and whenever
  /// the server rejects our token.
  Future<void> clearSession() async {
    await _store.clearSession();
    _api.setToken(null);
  }
}
