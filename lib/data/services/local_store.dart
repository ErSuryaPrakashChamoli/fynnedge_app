import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/clock.dart';

/// Thin key/value persistence for session + onboarding state.
/// Deliberately dumb: no business logic lives here.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());

  static const _kToken = 'fynn.auth.token';
  static const _kTokenExpiry = 'fynn.auth.token_expires_at';
  static const _kProfile = 'fynn.profile';
  static const _kFinancials = 'fynn.financials';
  static const _kOnboarded = 'fynn.onboarded';
  static const _kConsents = 'fynn.consents';

  String? get token => _prefs.getString(_kToken);

  Future<void> setToken(String? v, {DateTime? expiresAt}) async {
    if (v == null) {
      await _prefs.remove(_kToken);
      await _prefs.remove(_kTokenExpiry);
      return;
    }
    await _prefs.setString(_kToken, v);
    if (expiresAt == null) {
      await _prefs.remove(_kTokenExpiry);
    } else {
      await _prefs.setString(_kTokenExpiry, expiresAt.toIso8601String());
    }
  }

  DateTime? get tokenExpiresAt {
    final raw = _prefs.getString(_kTokenExpiry);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// A token with no recorded expiry is treated as live; the server is the
  /// final authority either way and will return 401 if it disagrees.
  bool get hasLiveToken {
    if (token == null) return false;
    final expiry = tokenExpiresAt;
    return expiry == null || expiry.isAfter(AppClock.now());
  }

  bool get onboardingComplete => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboardingComplete(bool v) => _prefs.setBool(_kOnboarded, v);

  Map<String, dynamic>? get profile => _readJson(_kProfile);
  Future<void> setProfile(Map<String, dynamic>? v) => _writeJson(_kProfile, v);

  Map<String, dynamic>? get financials => _readJson(_kFinancials);
  Future<void> setFinancials(Map<String, dynamic>? v) =>
      _writeJson(_kFinancials, v);

  Map<String, dynamic>? get consents => _readJson(_kConsents);
  Future<void> setConsents(Map<String, dynamic>? v) =>
      _writeJson(_kConsents, v);

  Future<void> clearSession() async {
    await _prefs.remove(_kToken);
    await _prefs.remove(_kTokenExpiry);
    await _prefs.remove(_kProfile);
    await _prefs.remove(_kFinancials);
    await _prefs.remove(_kOnboarded);
  }

  Map<String, dynamic>? _readJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeJson(String key, Map<String, dynamic>? value) async {
    if (value == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, jsonEncode(value));
    }
  }
}
