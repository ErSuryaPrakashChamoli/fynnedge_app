import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/error_text.dart';
import '../../data/models/twin.dart';
import '../../data/services/twin_service.dart';

/// What FynnTwin can do for this customer.
final twinCapabilitiesProvider = FutureProvider<TwinCapabilities>(
  (ref) => ref.watch(twinServiceProvider).capabilities(),
);

/// The scenario being built on screen, and its result.
class TwinScreenState {
  const TwinScreenState({
    this.type = ScenarioType.loan,
    this.amount = 500000,
    this.tenureMonths = 60,
    this.productId,
    this.monthlyChange = 5000,
    this.monthlyAmount = 5000,
    this.months = 12,
    this.projection,
    this.running = false,
    this.error,
  });

  final ScenarioType type;

  // Loan assumptions.
  final double amount;
  final int tenureMonths;
  final String? productId;

  // Spending assumption.
  final double monthlyChange;

  // Saving assumptions.
  final double monthlyAmount;
  final int months;

  /// The last result. Kept while a new one runs so the screen does not
  /// blank between simulations.
  final TwinProjection? projection;

  final bool running;
  final String? error;

  bool get canRun =>
      !running && (type != ScenarioType.loan || productId != null);

  TwinScenario get scenario => switch (type) {
    ScenarioType.loan => TwinScenario(
      type: type,
      amount: amount,
      tenureMonths: tenureMonths,
      productId: productId,
    ),
    ScenarioType.expenseChange => TwinScenario(
      type: type,
      monthlyChange: monthlyChange,
    ),
    ScenarioType.savingChange => TwinScenario(
      type: type,
      monthlyAmount: monthlyAmount,
      months: months,
    ),
  };

  TwinScreenState copyWith({
    ScenarioType? type,
    double? amount,
    int? tenureMonths,
    String? productId,
    double? monthlyChange,
    double? monthlyAmount,
    int? months,
    TwinProjection? projection,
    bool clearProjection = false,
    bool? running,
    String? error,
    bool clearError = false,
  }) => TwinScreenState(
    type: type ?? this.type,
    amount: amount ?? this.amount,
    tenureMonths: tenureMonths ?? this.tenureMonths,
    productId: productId ?? this.productId,
    monthlyChange: monthlyChange ?? this.monthlyChange,
    monthlyAmount: monthlyAmount ?? this.monthlyAmount,
    months: months ?? this.months,
    projection: clearProjection ? null : (projection ?? this.projection),
    running: running ?? this.running,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Builds a scenario and runs it.
///
/// Nothing here calculates. The assumptions go to the service, the engine
/// projects, and the result is displayed — so the screen can never disagree
/// with the server about what a decision would do.
class TwinController extends Notifier<TwinScreenState> {
  @override
  TwinScreenState build() => const TwinScreenState();

  /// Opens on a loan the customer arrived with.
  ///
  /// Used when FynnTwin is reached from a product they are already looking
  /// at, so the simulation is about that loan rather than about defaults.
  /// Applied once; it must not overwrite assumptions the customer has since
  /// changed on this screen.
  void presetLoan({
    required String productId,
    double? amount,
    int? tenureMonths,
  }) {
    if (state.type == ScenarioType.loan && state.productId == productId) {
      return;
    }

    state = TwinScreenState(
      type: ScenarioType.loan,
      productId: productId,
      amount: amount ?? state.amount,
      tenureMonths: tenureMonths ?? state.tenureMonths,
    );
  }

  /// Changing the scenario clears the last result: a projection belongs to
  /// the assumptions it came from.
  void setType(ScenarioType type) => state = state.copyWith(
    type: type,
    clearProjection: true,
    clearError: true,
  );

  void setProduct(String productId) =>
      state = state.copyWith(productId: productId, clearProjection: true);

  void setAmount(double amount) =>
      state = state.copyWith(amount: amount, clearProjection: true);

  void setTenure(int months) =>
      state = state.copyWith(tenureMonths: months, clearProjection: true);

  void setMonthlyChange(double amount) =>
      state = state.copyWith(monthlyChange: amount, clearProjection: true);

  void setMonthlyAmount(double amount) =>
      state = state.copyWith(monthlyAmount: amount, clearProjection: true);

  void setMonths(int months) =>
      state = state.copyWith(months: months, clearProjection: true);

  Future<TwinProjection?> run() async {
    if (!state.canRun) return null;

    state = state.copyWith(running: true, clearError: true);

    try {
      final projection = await ref
          .read(twinServiceProvider)
          .simulate(state.scenario);

      if (!ref.mounted) return null;
      state = state.copyWith(projection: projection, running: false);
      return projection;
    } on Object catch (e) {
      if (!ref.mounted) return null;
      state = state.copyWith(running: false, error: messageFor(e));
      return null;
    }
  }

  /// Drops a result whose "today" no longer exists.
  ///
  /// A projection is a comparison against the customer's current position.
  /// The moment they change their income, spending or EMIs, the left-hand
  /// column of that comparison is wrong, so the result goes. The assumptions
  /// they typed stay: those are still theirs, and re-running is one tap.
  void discardStaleResult() {
    if (state.projection == null) return;
    state = state.copyWith(clearProjection: true);
  }

  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(clearError: true);
  }
}

final twinControllerProvider =
    NotifierProvider<TwinController, TwinScreenState>(TwinController.new);
