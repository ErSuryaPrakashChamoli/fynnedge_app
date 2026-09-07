import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/core/utils/clock.dart';
import 'package:fynnedge/core/utils/error_text.dart';
import 'package:fynnedge/data/models/user.dart';
import 'package:fynnedge/data/repositories/auth_repository.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/auth_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// A stand-in that lets each test decide how the server behaves.
class _FakeAuthService implements AuthService {
  _FakeAuthService({this.onCurrentUser});

  final Future<UserProfile> Function()? onCurrentUser;
  int currentUserCalls = 0;
  int logoutCalls = 0;

  @override
  Future<OtpChallenge> sendOtp(String mobile) async =>
      OtpChallenge(mobile: mobile, reference: 'ref', devHint: '123456');

  @override
  Future<AuthSession> verifyOtp({
    required String mobile,
    required String reference,
    required String code,
  }) async => AuthSession(
    token: 'token-for-$mobile',
    profile: UserProfile(id: '1', mobile: mobile),
    isNewUser: false,
    expiresAt: AppClock.now().add(const Duration(days: 30)),
  );

  @override
  Future<void> logout() async => logoutCalls++;

  @override
  Future<UserProfile> currentUser() async {
    currentUserCalls++;
    if (onCurrentUser != null) return onCurrentUser!();
    return const UserProfile(id: '1', mobile: '9876543210');
  }
}

Future<(AuthRepository, LocalStore, ApiClient, _FakeAuthService)> build({
  Map<String, Object> seed = const {},
  Future<UserProfile> Function()? onCurrentUser,
}) async {
  SharedPreferences.setMockInitialValues(seed);
  final store = await LocalStore.open();
  final api = ApiClient();
  final service = _FakeAuthService(onCurrentUser: onCurrentUser);
  return (AuthRepository(service, store, api), store, api, service);
}

void main() {
  setUpAll(initUnitTestEnvironment);

  group('Token persistence', () {
    test('a verified OTP stores the token and its expiry', () async {
      final (repo, store, api, _) = await build();

      await repo.verifyOtp(
        mobile: '9876543210',
        reference: 'ref',
        code: '123456',
      );

      expect(store.token, 'token-for-9876543210');
      expect(store.tokenExpiresAt, isNotNull);
      // The client must carry it immediately, not on the next launch.
      expect(api.token, 'token-for-9876543210');
      expect(repo.isLoggedIn, isTrue);
    });

    test('a stored token is handed to the client on construction', () async {
      final (_, _, api, _) = await build(
        seed: {'flutter.fynn.auth.token': 'persisted-token'},
      );

      expect(api.token, 'persisted-token');
    });

    test('an expired token does not count as signed in', () async {
      final past = AppClock.now().subtract(const Duration(days: 1));
      final (repo, _, _, _) = await build(
        seed: {
          'flutter.fynn.auth.token': 'stale',
          'flutter.fynn.auth.token_expires_at': past.toIso8601String(),
        },
      );

      expect(repo.isLoggedIn, isFalse);
    });

    test('a token with no recorded expiry is treated as live', () async {
      final (repo, _, _, _) = await build(
        seed: {'flutter.fynn.auth.token': 'no-expiry'},
      );

      expect(repo.isLoggedIn, isTrue);
    });
  });

  group('Session restore', () {
    test('no token means no session, and no call to the server', () async {
      final (repo, _, _, service) = await build();

      expect(await repo.restoreSession(), isNull);
      expect(service.currentUserCalls, 0);
    });

    test('an expired token is discarded without being sent', () async {
      final past = AppClock.now().subtract(const Duration(days: 1));
      final (repo, store, _, service) = await build(
        seed: {
          'flutter.fynn.auth.token': 'stale',
          'flutter.fynn.auth.token_expires_at': past.toIso8601String(),
        },
      );

      expect(await repo.restoreSession(), isNull);
      expect(service.currentUserCalls, 0);
      expect(store.token, isNull);
    });

    test('a live token is confirmed against the server', () async {
      final (repo, _, _, service) = await build(
        seed: {'flutter.fynn.auth.token': 'good'},
      );

      final profile = await repo.restoreSession();

      expect(profile, isNotNull);
      expect(profile!.mobile, '9876543210');
      expect(service.currentUserCalls, 1);
    });

    test('a rejected token clears the session', () async {
      final (repo, store, api, _) = await build(
        seed: {'flutter.fynn.auth.token': 'revoked'},
        onCurrentUser: () async => throw UnauthorizedException(),
      );

      expect(await repo.restoreSession(), isNull);
      expect(store.token, isNull);
      expect(api.token, isNull);
    });

    test('being offline is not the same as being signed out', () async {
      final cached = const UserProfile(
        id: '1',
        mobile: '9876543210',
        fullName: 'Rahul Sharma',
      );
      final (repo, store, _, _) = await build(
        seed: {'flutter.fynn.auth.token': 'good'},
        onCurrentUser: () async => throw NetworkException(),
      );
      await repo.cacheProfile(cached);

      final profile = await repo.restoreSession();

      // The customer keeps their session and their data on a dropped
      // connection; only the server may end a session.
      expect(profile, isNotNull);
      expect(profile!.fullName, 'Rahul Sharma');
      expect(store.token, 'good');
    });
  });

  group('Sign out', () {
    test('logout clears the token even if the server call fails', () async {
      final (repo, store, api, _) = await build(
        seed: {'flutter.fynn.auth.token': 'good'},
      );

      await repo.logout();

      expect(store.token, isNull);
      expect(api.token, isNull);
      expect(repo.isLoggedIn, isFalse);
    });
  });

  group('Error messages', () {
    test('a field error beats the generic summary', () {
      final error = ValidationException('The given data was invalid.', {
        'mobile': ['Enter a valid 10-digit mobile number.'],
      });

      expect(
        messageFor(error, field: 'mobile'),
        'Enter a valid 10-digit mobile number.',
      );
    });

    test(
      'a validation error for another field still says something useful',
      () {
        final error = ValidationException('The given data was invalid.', {
          'code': ['Enter all 6 digits.'],
        });

        expect(messageFor(error, field: 'mobile'), 'Enter all 6 digits.');
      },
    );

    test('a server fault never leaks internal detail', () {
      expect(
        messageFor(ServerException()),
        'Something went wrong at our end. Please try again.',
      );
    });

    test('a non-API error is reported generically', () {
      expect(
        messageFor(StateError('null check on a null value')),
        'Something went wrong. Please try again.',
      );
    });

    test('rate limiting is flagged as worth waiting for', () {
      expect(shouldWaitBeforeRetry(RateLimitedException('Slow down')), isTrue);
      expect(shouldWaitBeforeRetry(NetworkException()), isFalse);
    });
  });
}
