import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/json.dart';
import '../models/user.dart';
import 'api_client.dart';
import 'api_config.dart';

class OtpChallenge {
  const OtpChallenge({
    required this.mobile,
    required this.reference,
    this.expiresInSeconds = 30,
    this.devHint,
  });

  final String mobile;
  final String reference;
  final int expiresInSeconds;

  /// Only populated by the mock service so the OTP is visible in development.
  final String? devHint;
}

class AuthSession {
  const AuthSession({
    required this.token,
    required this.profile,
    required this.isNewUser,
    this.expiresAt,
  });

  final String token;
  final UserProfile profile;
  final bool isNewUser;

  /// Null means the server issues non-expiring tokens.
  final DateTime? expiresAt;
}

/// POST /api/v1/auth/send-otp, /verify-otp
abstract class AuthService {
  Future<OtpChallenge> sendOtp(String mobile);
  Future<AuthSession> verifyOtp({
    required String mobile,
    required String reference,
    required String code,
  });
  Future<void> logout();

  /// Confirms a persisted token is still accepted, and returns the profile it
  /// belongs to. Throws UnauthorizedException when the token is dead.
  Future<UserProfile> currentUser();
}

/// Development implementation. Accepts any 6-digit code except '000000',
/// which is reserved so the error path stays testable.
class MockAuthService implements AuthService {
  int _sends = 0;

  @override
  Future<OtpChallenge> sendOtp(String mobile) async {
    await ApiConfig.pause();
    if (mobile.length != 10) {
      throw ApiException('Enter a valid 10-digit mobile number.');
    }
    _sends++;
    return OtpChallenge(
      mobile: mobile,
      reference: 'mock_ref_$_sends',
      expiresInSeconds: 30,
      devHint: '123456',
    );
  }

  @override
  Future<AuthSession> verifyOtp({
    required String mobile,
    required String reference,
    required String code,
  }) async {
    await ApiConfig.pause();
    if (code.length != 6) {
      throw ApiException('Enter all 6 digits.');
    }
    if (code == '000000') {
      throw ApiException('That code is not correct. Please try again.');
    }
    return AuthSession(
      token: 'mock_token_$mobile',
      profile: UserProfile(id: 'usr_$mobile', mobile: mobile),
      isNewUser: true,
    );
  }

  @override
  Future<void> logout() => ApiConfig.pauseFast();

  @override
  Future<UserProfile> currentUser() async {
    await ApiConfig.pauseFast();
    return const UserProfile(id: 'usr_mock_001', mobile: '9876543210');
  }
}

class ApiAuthService implements AuthService {
  ApiAuthService(this._api);
  final ApiClient _api;

  @override
  Future<OtpChallenge> sendOtp(String mobile) async {
    final data = await _api.post(
      '/auth/send-otp',
      body: {'mobile': mobile, 'device_name': _deviceName},
    );
    return OtpChallenge(
      mobile: mobile,
      reference: data['reference']?.toString() ?? '',
      expiresInSeconds: (data['expires_in'] as num?)?.toInt() ?? 30,
      // Present only while a development OTP provider is configured; the
      // server omits the key entirely once real delivery is wired in.
      devHint: data['dev_hint']?.toString(),
    );
  }

  @override
  Future<AuthSession> verifyOtp({
    required String mobile,
    required String reference,
    required String code,
  }) async {
    final data = await _api.post(
      '/auth/verify-otp',
      body: {
        'mobile': mobile,
        'reference': reference,
        'code': code,
        'device_name': _deviceName,
      },
    );
    final token = data['token']?.toString() ?? '';
    _api.setToken(token);
    return AuthSession(
      token: token,
      profile: UserProfile.fromJson(J.map(data['profile'])),
      isNewUser: data['is_new_user'] == true,
      expiresAt: J.date(data['expires_at']),
    );
  }

  @override
  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } finally {
      // Local sign-out must happen even if the server call fails, or the
      // customer is stuck signed in to a session they asked to end.
      _api.setToken(null);
    }
  }

  @override
  Future<UserProfile> currentUser() async =>
      UserProfile.fromJson(J.map(await _api.get('/auth/me')));

  /// Labels the token so a customer can tell their devices apart later.
  static String get _deviceName {
    if (kIsWeb) return 'FynnEdge Web';
    return 'FynnEdge ${Platform.operatingSystem}';
  }
}
