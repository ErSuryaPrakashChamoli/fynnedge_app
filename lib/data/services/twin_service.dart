import '../mock/mock_data.dart';
import '../models/loan.dart';
import '../mock/mock_store.dart';
import '../models/twin.dart';
import '../twin/fynn_twin_engine.dart';
import 'api_client.dart';
import 'api_config.dart';

/// What FynnTwin can simulate, and whether this customer can use it.
class TwinCapabilities {
  const TwinCapabilities({
    this.scenarios = ScenarioType.values,
    this.hasFinancialProfile = false,
    this.referencePercent = 45,
  });

  final List<ScenarioType> scenarios;

  /// False when there is no income to project against.
  final bool hasFinancialProfile;
  final double referencePercent;

  factory TwinCapabilities.fromJson(Map<String, dynamic> json) =>
      TwinCapabilities(
        scenarios: (json['scenarios'] as List? ?? const [])
            .map((e) => ScenarioType.fromId((e as Map)['type'] as String?))
            .toList(),
        hasFinancialProfile: json['has_financial_profile'] == true,
        referencePercent:
            (json['affordability_reference_percent'] as num?)?.toDouble() ?? 45,
      );
}

/// FynnTwin.
///
/// Stateless on both sides: a simulation computes and returns, and writes
/// nothing about the customer.
abstract class TwinService {
  Future<TwinCapabilities> capabilities();
  Future<TwinProjection> simulate(TwinScenario scenario);
}

class MockTwinService implements TwinService {
  MockTwinService([MockStore? store]) : _store = store ?? MockStore.instance;

  final MockStore _store;

  @override
  Future<TwinCapabilities> capabilities() async {
    await ApiConfig.pauseFast();

    return TwinCapabilities(
      hasFinancialProfile: _store.snapshot.hasIncome,
    );
  }

  @override
  Future<TwinProjection> simulate(TwinScenario scenario) async {
    await ApiConfig.pause();

    // The same engine the API runs, over the same customer the rest of mock
    // mode reads, priced from the same catalogue.
    return fynnTwinEngine.simulate(
      current: _store.snapshot,
      scenario: scenario,
      product: _productFor(scenario.productId),
    );
  }

  LoanProduct? _productFor(String? id) {
    if (id == null) return null;

    final match = MockData.products.where((p) => p.id == id);
    if (match.isEmpty) {
      throw ApiException(
        'That product is not in the catalogue.',
        statusCode: 422,
      );
    }
    return match.first;
  }
}

class ApiTwinService implements TwinService {
  ApiTwinService(this._api);
  final ApiClient _api;

  @override
  Future<TwinCapabilities> capabilities() async => TwinCapabilities.fromJson(
    await _api.get('/fynn-twin') as Map<String, dynamic>,
  );

  @override
  Future<TwinProjection> simulate(TwinScenario scenario) async =>
      TwinProjection.fromJson(
        // Assumptions only. Where the customer is starting from, and what a
        // product costs, are the server's to decide.
        await _api.post('/fynn-twin/simulate', body: scenario.toJson())
            as Map<String, dynamic>,
      );
}
