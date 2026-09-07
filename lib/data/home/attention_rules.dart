import '../../app/routes.dart';
import '../../core/money/money.dart';
import '../engine/financial_engine.dart';
import '../models/application.dart';
import '../models/goal.dart';
import '../models/home_snapshot.dart';

/// What matters about this customer's money right now.
///
/// Mirrors App\Domain\Home\AttentionRules. Laravel is authoritative; this
/// exists so mock mode raises the same items in the same order with the same
/// words, and test/home_attention_parity_test.dart holds it to the fixture
/// the server generated.
///
/// Deterministic and ordered. Nothing here decides by score, weighting or
/// model: each rule is a comparison against a figure an engine produced, and
/// the order below is the order they are considered.
///
/// PRIORITY, highest first:
///
///   1. negative_surplus         spending more than you earn
///   2. emi_ratio_past_reference EMIs past FynnEdge's 45% reference
///   3. thin_emergency_buffer    savings cover under 6 months of outgo
///   4. application_action       a provider asked for something
///   5. goal_overdue             a goal's date has passed
///
/// Every threshold is an existing product definition — the affordability
/// reference from FinancialEngine and the emergency-fund target from the same
/// place. No number here was invented to make a card appear.
class AttentionRules {
  const AttentionRules();

  List<AttentionItem> evaluate({
    required FinancialSnapshot financials,
    List<Goal> goals = const [],
    List<LoanApplication> applications = const [],
  }) {
    // Without an income nothing can be measured, so nothing is claimed.
    if (!financials.hasIncome) return const [];

    return [
      _negativeSurplus(financials),
      _emiRatio(financials),
      _emergencyBuffer(financials),
      _applicationAction(applications),
      _overdueGoal(goals),
    ].whereType<AttentionItem>().toList();
  }

  AttentionItem? _negativeSurplus(FinancialSnapshot f) {
    if (!f.surplus.isNegative) return null;

    return AttentionItem(
      key: 'negative_surplus',
      severity: AttentionSeverity.serious,
      title: 'You are spending more than you earn',
      detail:
          'Your outgoings of ${f.totalOutgo.toIndianString()} are above '
          'your income of ${f.income.toIndianString()} each month.',
      actionLabel: 'Review your figures',
      actionRoute: Routes.financialProfile,
    );
  }

  /// The affordability reference FynnEdge already uses everywhere else.
  AttentionItem? _emiRatio(FinancialSnapshot f) {
    final ratio = f.emiRatio.value;
    if (ratio <= FinancialEngine.affordabilityCeilingPercent) return null;

    return AttentionItem(
      key: 'emi_ratio_past_reference',
      severity: AttentionSeverity.caution,
      title: 'Your EMIs take a large share of your income',
      detail:
          'Repayments use ${_percent(ratio)}% of what you earn, past the '
          '${_percent(FinancialEngine.affordabilityCeilingPercent)}% '
          'FynnEdge uses as its affordability reference. That is '
          "FynnEdge's reference, not a lender rule.",
      actionLabel: 'See what a change would do',
      actionRoute: Routes.fynnTwin,
    );
  }

  /// The six-month target the emergency-fund definition already uses.
  AttentionItem? _emergencyBuffer(FinancialSnapshot f) {
    final months = f.emergencyMonths.value;
    if (months >= FinancialEngine.emergencyFundTargetMonths) return null;

    return AttentionItem(
      key: 'thin_emergency_buffer',
      severity: AttentionSeverity.caution,
      title: 'Your savings would not last long',
      detail:
          'What you have saved covers about ${_percent(months)} months of '
          'your outgoings. ${FinancialEngine.emergencyFundTargetMonths} '
          'months is the buffer FynnEdge measures against.',
      actionLabel: 'Plan a buffer',
      actionRoute: Routes.emergencyFund,
    );
  }

  /// Only a status a provider actually reported.
  ///
  /// No provider integration exists, so this cannot fire today. It is here
  /// because the rule belongs with the others, not to fill the card.
  AttentionItem? _applicationAction(List<LoanApplication> applications) {
    final needsAction = applications
        .where((a) => a.status == ApplicationStatus.actionNeeded)
        .firstOrNull;

    if (needsAction == null) return null;

    return AttentionItem(
      key: 'application_action',
      severity: AttentionSeverity.caution,
      title: '${needsAction.lender} needs something from you',
      detail:
          'Your application ${needsAction.reference} cannot move forward '
          'until you respond.',
      actionLabel: 'Open the application',
      actionRoute: Routes.applications,
    );
  }

  /// A goal whose date has passed, from the goal's own metrics.
  AttentionItem? _overdueGoal(List<Goal> goals) {
    final overdue = goals.where((g) => g.isOverdue).firstOrNull;
    if (overdue == null) return null;

    return AttentionItem(
      key: 'goal_overdue',
      severity: AttentionSeverity.info,
      title: '${overdue.title} has passed its date',
      detail:
          'You saved ${Money.of(overdue.savedAmount).toIndianString()} of '
          '${Money.of(overdue.targetAmount).toIndianString()}. Moving the '
          'date or the target keeps it useful.',
      actionLabel: 'Open goals',
      actionRoute: Routes.goals,
    );
  }

  /// Mirrors the server's trimmed two-decimal formatting: 45, 46, 3.33.
  static String _percent(double value) {
    final fixed = value.toStringAsFixed(2);
    if (!fixed.contains('.')) return fixed;
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

const attentionRules = AttentionRules();
