import '../models/decision.dart';
import 'api_client.dart';
import 'api_config.dart';

abstract class DecisionService {
  Future<List<Decision>> getDecisions();
  Future<Decision> getDecision(String id);
}

/// Mock mode has no decision history, because nothing was explored.
///
/// A decision record says a real customer did a real thing. Seeding one
/// would be fabricating the exploration behind it — and a fabricated "you
/// simulated a ₹10 lakh loan" is a claim about somebody's intentions,
/// which is the specific thing this module refuses to invent.
class MockDecisionService implements DecisionService {
  const MockDecisionService();

  @override
  Future<List<Decision>> getDecisions() async {
    await ApiConfig.pause();
    return const [];
  }

  @override
  Future<Decision> getDecision(String id) async {
    await ApiConfig.pauseFast();
    throw StateError('Mock mode records no decisions.');
  }
}

class ApiDecisionService implements DecisionService {
  ApiDecisionService(this._api);
  final ApiClient _api;

  @override
  Future<List<Decision>> getDecisions() async =>
      (await _api.get('/decisions') as List)
          .map((e) => Decision.fromJson(e as Map<String, dynamic>))
          .toList();

  @override
  Future<Decision> getDecision(String id) async => Decision.fromJson(
    await _api.get('/decisions/$id') as Map<String, dynamic>,
  );
}
