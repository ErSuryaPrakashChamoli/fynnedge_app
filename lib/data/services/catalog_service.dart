import '../mock/mock_data.dart';
import '../models/loan.dart';
import 'api_client.dart';
import 'api_config.dart';

/// GET /products, GET /products/{id}
abstract class CatalogService {
  Future<List<LoanProduct>> getProducts({
    LoanCategory? category,
    double? amount,
  });
  Future<LoanProduct> getProduct(String id);
}

class MockCatalogService implements CatalogService {
  const MockCatalogService();

  @override
  Future<List<LoanProduct>> getProducts({
    LoanCategory? category,
    double? amount,
  }) async {
    await ApiConfig.pause();
    return MockData.products.where((p) {
      if (category != null && p.category != category) return false;
      if (amount != null && (amount < p.minAmount || amount > p.maxAmount)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<LoanProduct> getProduct(String id) async {
    await ApiConfig.pauseFast();
    final match = MockData.products.where((p) => p.id == id);
    if (match.isEmpty) throw ApiException('That offer is no longer available.');
    return match.first;
  }
}

class ApiCatalogService implements CatalogService {
  ApiCatalogService(this._api);
  final ApiClient _api;

  @override
  Future<List<LoanProduct>> getProducts({
    LoanCategory? category,
    double? amount,
  }) async {
    final data = await _api.get(
      '/products',
      query: {'category': ?category?.id, 'amount': ?amount},
    );
    // A product whose own record contradicts itself is dropped rather than
    // shown with whatever the parser made of it. Better one product missing
    // from a list than one product on screen quoting a range nobody
    // published. See LoanProduct.isCoherent.
    return (data as List)
        .map((e) => LoanProduct.fromJson(e as Map<String, dynamic>))
        .where((p) => p.isCoherent)
        .toList();
  }

  @override
  Future<LoanProduct> getProduct(String id) async {
    final product = LoanProduct.fromJson(
      await _api.get('/products/$id') as Map<String, dynamic>,
    );

    if (!product.isCoherent) {
      // Nothing useful can be said about this product, and guessing at its
      // missing pieces would put invented terms in front of a decision.
      throw ApiException('That product is not available right now.');
    }

    return product;
  }
}
