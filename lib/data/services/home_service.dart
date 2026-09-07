import '../../core/money/money.dart';
import '../engine/financial_engine.dart';
import '../home/attention_rules.dart';
import '../home/primary_action_rules.dart';
import '../mock/mock_store.dart';
import '../models/application.dart';
import '../models/home_snapshot.dart';
import '../score/fynn_score_engine.dart';
import 'api_client.dart';
import 'api_config.dart';

/// GET /api/v1/home — one call, everything the dashboard renders.
abstract class HomeService {
  Future<HomeSnapshot> getSnapshot();
}

/// Assembles Home from the shared mock store, through the same engines and
/// the same rules the API uses.
///
/// Nothing here is seeded. Every figure comes from FinancialEngine, the score
/// from FynnScoreEngine, the attention items from the mirrored AttentionRules
/// and the next step from the mirrored PrimaryActionRules — so mock mode
/// cannot show something the real endpoint would not.
class MockHomeService implements HomeService {
  const MockHomeService();

  /// The server's page sizes, mirrored so mock mode truncates identically.
  static const int goalsShown = 3;
  static const int applicationsShown = 3;

  @override
  Future<HomeSnapshot> getSnapshot() async {
    await ApiConfig.pause();

    // Read through the shared store, not seed constants: the real /home
    // endpoint reads the same rows the profile endpoints write, and mock mode
    // has to behave the same or Home shows a figure the customer changed.
    final store = MockStore.instance;
    final f = store.financials;

    final snapshot = financialEngine.snapshot(
      income: Money.of(f.monthlyIncome),
      expenses: Money.of(f.monthlyExpenses),
      existingEmi: Money.of(f.existingEmi),
      otherObligations: Money.of(f.otherObligations),
      savings: Money.of(f.savings),
    );

    // Active goals, nearest date first — the order the API returns.
    final goals = store.goals.where((g) => g.status == 'active').toList()
      ..sort((a, b) => a.targetDate.compareTo(b.targetDate));

    final applications = store.applications;
    final name = store.profile.fullName.trim();

    return HomeSnapshot(
      customer: HomeCustomer(
        firstName: name.isEmpty ? null : name.split(' ').first,
        hasFinancialProfile: snapshot.hasIncome,
      ),
      financials: HomeFinancials(
        monthlyIncome: snapshot.income.rupees,
        monthlyExpenses: snapshot.expenses.rupees,
        monthlyOutgo: snapshot.totalOutgo.rupees,
        surplus: snapshot.surplus.rupees,
        existingEmi: snapshot.existingEmi.rupees,
        otherObligations: snapshot.otherObligations.rupees,
        savings: snapshot.savings.rupees,
        emiRatio: snapshot.emiRatio.value,
        expenseRatio: snapshot.expenseRatio.value,
        emergencyMonths: snapshot.emergencyMonths.value,
        hasIncome: snapshot.hasIncome,
      ),
      // From the same engine the profile service uses, so Home and the
      // FynnScore screen can never disagree.
      score: fynnScoreEngine.score(snapshot),
      goals: goals.take(goalsShown).map((g) => g.withLocalDerived()).toList(),
      goalsTotal: goals.length,
      applications: applications
          .take(applicationsShown)
          .map(_asHomeApplication)
          .toList(),
      applicationsTotal: applications.length,
      applicationsActive: applications
          .where((a) => !a.status.isTerminal)
          .length,
      vaultDocumentCount: store.documents.length,
      attention: attentionRules.evaluate(
        financials: snapshot,
        goals: goals,
        applications: applications,
      ),
      primaryAction: primaryActionRules.resolve(
        hasIncome: snapshot.hasIncome,
        hasName: name.isNotEmpty,
        goalCount: goals.length,
        applicationCount: applications.length,
      ),
    );
  }

  static HomeApplication _asHomeApplication(LoanApplication a) =>
      HomeApplication(
        id: a.id,
        reference: a.reference,
        lender: a.lender,
        productName: a.productName,
        amount: a.amount,
        status: a.status.id,
        statusLabel: a.status.label,
        isSimulated: a.isSimulated,
      );
}

class ApiHomeService implements HomeService {
  ApiHomeService(this._api);
  final ApiClient _api;

  @override
  Future<HomeSnapshot> getSnapshot() async =>
      HomeSnapshot.fromJson(await _api.get('/home') as Map<String, dynamic>);
}
