import '../../core/money/money.dart';
import '../engine/financial_engine.dart';
import '../match/fynn_match_engine.dart';
import '../mock/mock_data.dart';
import '../mock/mock_store.dart';
import '../models/match.dart';
import 'api_client.dart';
import 'api_config.dart';

/// GET /fynn-match
///
/// The request carries what the customer asked for and nothing about who they
/// are. Whose finances are evaluated is decided by the token on the server.
abstract class MatchService {
  Future<MatchResult> findMatches(MatchRequest request);

  /// One product re-evaluated at a chosen amount and tenure — the simulation
  /// behind Loan Detail's sliders.
  ///
  /// Computes and returns. It writes nothing: moving a slider must never
  /// change what FynnEdge holds about the customer.
  Future<ProductMatch> simulate(String productId, MatchRequest request);
}

class MockMatchService implements MatchService {
  MockMatchService([MockStore? store]) : _store = store ?? MockStore.instance;

  final MockStore _store;

  /// The stored customer, through the Financial Engine. Read only — a
  /// simulation never writes back here.
  FinancialSnapshot get _snapshot {
    final f = _store.financials;
    return financialEngine.snapshot(
      income: Money.of(f.monthlyIncome),
      expenses: Money.of(f.monthlyExpenses),
      existingEmi: Money.of(f.existingEmi),
      otherObligations: Money.of(f.otherObligations),
      savings: Money.of(f.savings),
    );
  }

  @override
  Future<MatchResult> findMatches(MatchRequest request) async {
    await ApiConfig.pause();

    // The same engine the API runs, over the same customer the rest of mock
    // mode reads. Editing the financial profile moves these results here
    // exactly as it would against the real backend.
    return fynnMatchEngine.match(
      products: MockData.products,
      request: request,
      financials: _snapshot,
      customerAge: _store.profile.age,
    );
  }

  @override
  Future<ProductMatch> simulate(String productId, MatchRequest request) async {
    await ApiConfig.pauseFast();

    final product = MockData.products.where((p) => p.id == productId);
    if (product.isEmpty) {
      throw ApiException('That product is no longer in our set.');
    }

    return fynnMatchEngine.evaluate(
      product: product.first,
      request: request,
      financials: _snapshot,
      customerAge: _store.profile.age,
    );
  }
}

class ApiMatchService implements MatchService {
  ApiMatchService(this._api);
  final ApiClient _api;

  @override
  Future<MatchResult> findMatches(MatchRequest request) async =>
      MatchResult.fromJson(
        await _api.get('/fynn-match', query: request.toQuery())
            as Map<String, dynamic>,
      );

  @override
  Future<ProductMatch> simulate(String productId, MatchRequest request) async =>
      ProductMatch.fromJson(
        await _api.get('/fynn-match/$productId', query: request.toQuery())
            as Map<String, dynamic>,
      );
}
