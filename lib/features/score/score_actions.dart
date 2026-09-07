import '../../app/routes.dart';

/// Where a FynnScore recommendation can actually be acted on.
///
/// Navigation only. Nothing here computes, scores or ranks — the score, its
/// dimensions and its recommendations are FynnScoreEngine's, and this decides
/// nothing except which existing screen is worth opening next.
///
/// The keys are the engine's own dimension keys. A dimension with no honest
/// destination gets none: an action that leads nowhere useful is worse than
/// no action, and inventing a feature to justify a button is worse still.
class ScoreAction {
  const ScoreAction({required this.label, required this.route});

  final String label;
  final String route;

  /// Null when FynnEdge has nothing that would actually help with this
  /// dimension today.
  static ScoreAction? forDimension(String key) => switch (key) {
    // Paying down what is already owed is the lever on this dimension, and
    // FynnLab's prepayment calculator is where that is worked out.
    'emi_burden' => const ScoreAction(
      label: 'Work out a prepayment',
      route: Routes.prepayment,
    ),

    // Spending less is a change FynnTwin can already model: it is one of
    // the three scenarios the engine supports.
    'spending_control' => const ScoreAction(
      label: 'See what spending less would do',
      route: Routes.fynnTwin,
    ),

    // The buffer has its own calculator, built on the same six-month target
    // the score measures against.
    'emergency_buffer' => const ScoreAction(
      label: 'Plan your buffer',
      route: Routes.emergencyFund,
    ),

    _ => null,
  };
}
