import '../models/credit.dart';
import 'api_client.dart';
import 'api_config.dart';

/// Credit information, through one seam.
///
/// NO LIVE BUREAU IS CONNECTED TO FYNNEDGE. The API's default driver is
/// `none`, and the mock implementation below reports exactly that. When a
/// real bureau contract exists, only the server changes; this interface and
/// everything above it stay as they are.
///
/// Two rules hold on both sides:
///   - reading the state never causes a bureau to be asked;
///   - a failed check produces no score, not a guessed one.
abstract class CreditService {
  /// What FynnEdge already knows. Never triggers a bureau request.
  Future<CreditState> getStatus();

  /// Asks the bureau, because the customer asked FynnEdge to.
  ///
  /// Throws [PermissionRequiredException] when consent has not been given,
  /// [CapabilityUnavailableException] when no bureau is connected, and
  /// [UpstreamUnavailableException] when the bureau did not answer. Each of
  /// those is a different thing to tell the customer, which is why they are
  /// different types.
  Future<CreditState> check();
}

/// Mock mode has no bureau, and says so.
///
/// It deliberately does not simulate a score. A fictional credit score shown
/// in a demo is the exact confusion this module exists to prevent, and there
/// would be no honest way to label it on screen.
class MockCreditService implements CreditService {
  const MockCreditService();

  @override
  Future<CreditState> getStatus() async {
    await ApiConfig.pauseFast();
    return const CreditState(status: CreditReportStatus.notConfigured);
  }

  @override
  Future<CreditState> check() async {
    await ApiConfig.pauseFast();
    throw CapabilityUnavailableException(
      'FynnEdge is not connected to a credit bureau yet.',
      reason: 'not_configured',
    );
  }
}

class ApiCreditService implements CreditService {
  ApiCreditService(this._api);
  final ApiClient _api;

  @override
  Future<CreditState> getStatus() async => CreditState.fromJson(
    await _api.get('/credit/status') as Map<String, dynamic>,
  );

  @override
  Future<CreditState> check() async => CreditState.fromJson(
    // No body at all: whose credit is checked comes from the session.
    await _api.post('/credit/check') as Map<String, dynamic>,
  );
}
