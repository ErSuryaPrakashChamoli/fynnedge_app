import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/session.dart';
import '../../data/models/match.dart';
import '../../data/services/api_client.dart';

/// FynnMatch for the request currently being explored.
///
/// Every product is evaluated, fitting or not, so the screens can explain a
/// gap rather than leave one. Nothing here identifies the customer: whose
/// finances are assessed is decided by the session on the server.
final fynnMatchProvider = FutureProvider<MatchResult>((ref) async {
  final request = ref.watch(loanRequestProvider);

  return ref
      .watch(matchServiceProvider)
      .findMatches(
        MatchRequest(
          amount: request.amount,
          tenureMonths: request.tenureMonths,
          purpose: request.purpose,
          preferredEmi: request.preferredEmi,
        ),
      );
});

/// The products that fit, best fit first.
final matchesProvider = FutureProvider<List<ProductMatch>>(
  (ref) async => (await ref.watch(fynnMatchProvider.future)).viable,
);

/// The products that do not, kept so the app can say why.
final unmatchedProvider = FutureProvider<List<ProductMatch>>(
  (ref) async => (await ref.watch(fynnMatchProvider.future)).rejected,
);

/// One product, evaluated against the same request as the list it came from.
final matchProvider = FutureProvider.family<ProductMatch, String>((
  ref,
  productId,
) async {
  final match = (await ref.watch(fynnMatchProvider.future)).byId(productId);
  if (match == null) {
    throw ApiException('That product is no longer in our set.');
  }
  return match;
});

/// The products the customer ticked for side-by-side comparison.
final comparisonProvider = FutureProvider<List<ProductMatch>>((ref) async {
  final ids = ref.watch(compareProvider);
  if (ids.isEmpty) return const [];

  final result = await ref.watch(fynnMatchProvider.future);
  return [for (final id in ids) ?result.byId(id)];
});

/// What Loan Detail is currently modelling for one product.
///
/// Held apart from [loanRequestProvider] on purpose: the customer's stated
/// request is what FynnMatch answers, and dragging a slider on one product's
/// page must not rewrite it. Nothing here is persisted.
class SimulationInputs {
  const SimulationInputs({
    this.productId = '',
    this.amount = 0,
    this.tenureMonths = 0,
    this.isCustomised = false,
  });

  final String productId;
  final double amount;
  final int tenureMonths;

  /// True once the customer has moved something away from their request.
  final bool isCustomised;

  bool appliesTo(String id) => isCustomised && productId == id;

  SimulationInputs copyWith({double? amount, int? tenureMonths}) =>
      SimulationInputs(
        productId: productId,
        amount: amount ?? this.amount,
        tenureMonths: tenureMonths ?? this.tenureMonths,
        isCustomised: true,
      );
}

class SimulationNotifier extends Notifier<SimulationInputs> {
  @override
  SimulationInputs build() => const SimulationInputs();

  void setAmount(ProductMatch base, double amount) {
    state = _baseline(base).copyWith(amount: amount);
  }

  void setTenure(ProductMatch base, int months) {
    state = _baseline(base).copyWith(tenureMonths: months);
  }

  /// Adopts assumptions decided elsewhere — FynnTwin handing a loan over to
  /// FynnMirror, so both screens describe the same loan.
  ///
  /// The same state Loan Detail's sliders write, deliberately: a second
  /// place to hold "what is being modelled" is a second thing to disagree.
  void setFor({
    required String productId,
    required double amount,
    required int tenureMonths,
  }) {
    state = SimulationInputs(
      productId: productId,
      amount: amount,
      tenureMonths: tenureMonths,
      isCustomised: true,
    );
  }

  /// Back to the customer's own request.
  void reset() => state = const SimulationInputs();

  /// What the untouched slider keeps.
  ///
  /// Moving one slider must leave the other where the match already priced
  /// it. Starting from an empty state instead would silently re-price the
  /// loan at the product's minimum term.
  SimulationInputs _baseline(ProductMatch base) =>
      state.appliesTo(base.product.id)
      ? state
      : SimulationInputs(
          productId: base.product.id,
          amount: base.pricing.amount,
          tenureMonths: base.pricing.tenureMonths,
        );
}

final simulationInputsProvider =
    NotifierProvider<SimulationNotifier, SimulationInputs>(
      SimulationNotifier.new,
    );

/// One product priced at whatever Loan Detail is currently modelling.
///
/// Until the customer moves something this is the match itself — no second
/// call, and no chance of the two disagreeing. Once they do, it is a fresh
/// evaluation of that product alone, through the same service seam.
final simulatedMatchProvider = FutureProvider.family<ProductMatch, String>((
  ref,
  productId,
) async {
  final inputs = ref.watch(simulationInputsProvider);
  final match = await ref.watch(matchProvider(productId).future);

  if (!inputs.appliesTo(productId)) return match;

  final request = ref.read(loanRequestProvider);
  return ref
      .watch(matchServiceProvider)
      .simulate(
        productId,
        MatchRequest(
          amount: inputs.amount,
          tenureMonths: inputs.tenureMonths,
          purpose: request.purpose,
          preferredEmi: request.preferredEmi,
        ),
      );
});
