import '../../core/utils/clock.dart';
import '../mock/mock_store.dart';
import '../models/consent.dart';
import 'api_client.dart';
import 'api_config.dart';

/// Reading and recording consent.
///
/// Both implementations append: a change of mind adds a decision, it never
/// edits one. Nothing here can remove a record, because there is no such
/// operation on either side.
abstract class ConsentService {
  Future<ConsentState> getConsents();
  Future<List<ConsentRecord>> getHistory();

  /// Records a grant. Granting something already granted under the current
  /// version adds nothing.
  Future<ConsentState> grant(ConsentType type, {String source});

  /// Records a withdrawal. Refused for required and unavailable types.
  Future<ConsentState> withdraw(ConsentType type, {String source});
}

class MockConsentService implements ConsentService {
  MockConsentService([MockStore? store]) : _store = store ?? MockStore.instance;

  final MockStore _store;

  @override
  Future<ConsentState> getConsents() async {
    await ApiConfig.pause();
    return _store.consentState;
  }

  @override
  Future<List<ConsentRecord>> getHistory() async {
    await ApiConfig.pauseFast();
    return _store.consentHistory;
  }

  @override
  Future<ConsentState> grant(
    ConsentType type, {
    String source = 'privacy_screen',
  }) async {
    await ApiConfig.pauseFast();

    final item = _store.consentState.byType(type);

    if (item == null || !item.isAvailable) {
      throw ApiException(
        'That permission is not available yet. FynnEdge will ask you when '
        'the feature behind it exists.',
        statusCode: 422,
      );
    }

    // Already granted under the wording in force: the same decision, not a
    // second one.
    if (item.isGranted) return _store.consentState;

    _store.recordConsent(
      ConsentRecord(
        type: type,
        label: item.label,
        version: item.currentVersion ?? 'v1',
        status: ConsentStatus.granted,
        source: source,
        at: AppClock.now(),
      ),
    );

    return _store.consentState;
  }

  @override
  Future<ConsentState> withdraw(
    ConsentType type, {
    String source = 'privacy_screen',
  }) async {
    await ApiConfig.pauseFast();

    final item = _store.consentState.byType(type);

    if (item == null || !item.isAvailable) {
      throw ApiException(
        'That permission is not available yet. FynnEdge will ask you when '
        'the feature behind it exists.',
        statusCode: 422,
      );
    }

    if (item.isRequired) {
      throw ApiException(
        'This permission is part of using FynnEdge and cannot be switched '
        'off here. To stop entirely, delete your account.',
        statusCode: 422,
      );
    }

    if (!item.isGranted) {
      final everGranted = _store.consentHistory.any((r) => r.type == type);
      if (!everGranted) {
        throw ApiException(
          'There is nothing to withdraw for that permission.',
          statusCode: 422,
        );
      }
      return _store.consentState;
    }

    _store.recordConsent(
      ConsentRecord(
        type: type,
        label: item.label,
        version: item.grantedVersion ?? item.currentVersion ?? 'v1',
        status: ConsentStatus.withdrawn,
        source: source,
        at: AppClock.now(),
      ),
    );

    return _store.consentState;
  }
}

class ApiConsentService implements ConsentService {
  ApiConsentService(this._api);
  final ApiClient _api;

  @override
  Future<ConsentState> getConsents() async => ConsentState.fromJson(
    await _api.get('/consents') as Map<String, dynamic>,
  );

  @override
  Future<List<ConsentRecord>> getHistory() async =>
      (await _api.get('/consents/history') as List)
          .map((e) => ConsentRecord.fromJson(e as Map<String, dynamic>))
          .toList();

  @override
  Future<ConsentState> grant(
    ConsentType type, {
    String source = 'privacy_screen',
  }) async => ConsentState.fromJson(
    // No version and no customer id: the server decides both.
    await _api.post('/consents', body: {'type': type.id, 'source': source})
        as Map<String, dynamic>,
  );

  @override
  Future<ConsentState> withdraw(
    ConsentType type, {
    String source = 'privacy_screen',
  }) async => ConsentState.fromJson(
    await _api.post('/consents/${type.id}/withdraw', body: {'source': source})
        as Map<String, dynamic>,
  );
}
