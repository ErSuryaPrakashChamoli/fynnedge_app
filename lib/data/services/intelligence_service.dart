import '../mock/mock_store.dart';
import '../models/intelligence.dart';
import '../score/fynn_score_engine.dart';
import 'api_client.dart';
import 'api_config.dart';

abstract class IntelligenceService {
  Future<FinancialIntelligence> getIntelligence();
  Future<List<FinancialMoment>> getTimeline();
}

/// Mock mode has no financial history, because nothing has happened.
///
/// A moment is a record of something that occurred to a real customer.
/// Seeding a timeline would be inventing the events behind it — and a
/// fabricated "your FynnScore improved by 6" is exactly the kind of claim
/// Module 31 exists to prevent, whether it comes from a rule or a fixture.
///
/// The next action is still produced, because that is derived from current
/// state rather than from history, and mock mode has a state.
class MockIntelligenceService implements IntelligenceService {
  const MockIntelligenceService();

  @override
  Future<FinancialIntelligence> getIntelligence() async {
    await ApiConfig.pause();

    /*
     * The plan and the next action are the same first item, because the
     * server derives both from one ladder. Mock mode mirrors that rather
     * than inventing a second answer.
     */
    /*
     * The same customer MockStore describes.
     *
     * The mock profile records ₹1,00,000 coming in and ₹60,000 going out
     * against ₹1,80,000 saved, so the position says exactly that and the
     * one suggestion is the one the real ladder reaches for a buffer of
     * three months against a reference of six. This used to answer "add
     * your financial details" for a customer whose figures were already
     * on the next screen — a demo of a product contradicting itself.
     */
    const buffer = NextAction(
      type: 'review_buffer',
      title: 'Look at your savings buffer',
      reason:
          'Your recorded savings would cover about 3 months of your monthly '
          'outgo. FynnEdge measures against 6 months.',
      actionLabel: 'Plan a buffer',
      actionRoute: '/fynnlab/emergency-fund',
      priority: 10,
    );

    /*
     * Scored and counted from the same store every other mock service
     * reads, so mock mode cannot show a review that contradicts the
     * FynnScore screen or the Goals screen beside it.
     */
    final store = MockStore.instance;
    final score = fynnScoreEngine.score(store.snapshot);

    return FinancialIntelligence(
      score: ScoreSummary(
        hasScore: score.hasScore,
        score: score.score,
        band: score.band?.id,
        bandLabel: score.band?.label,
        summary: score.summary,
      ),
      goals: store.goals.map((g) => g.withLocalDerived()).toList(),
      goalCount: store.goals.length,
      position: const FinancialPosition(
        isMeasurable: true,
        surplusState: SurplusState.positive,
        statement: 'Your recorded income is higher than your monthly outgo.',
        income: 100000,
        monthlyOutgo: 60000,
        surplus: 40000,
        emergencyMonths: 3,
        emergencyBelowReference: true,
        emergencyStatement:
            'Your recorded savings would cover about 3 months of your '
            'monthly outgo. FynnEdge measures against 6 months.',
      ),
      nextAction: buffer,
      plan: const [buffer],
      insights: const [],
      recentMoments: const [],
      observations: 0,
      hasComparableHistory: false,
    );
  }

  @override
  Future<List<FinancialMoment>> getTimeline() async {
    await ApiConfig.pause();
    return const [];
  }
}

class ApiIntelligenceService implements IntelligenceService {
  ApiIntelligenceService(this._api);
  final ApiClient _api;

  @override
  Future<FinancialIntelligence> getIntelligence() async =>
      FinancialIntelligence.fromJson(
        await _api.get('/intelligence') as Map<String, dynamic>,
      );

  @override
  Future<List<FinancialMoment>> getTimeline() async =>
      (await _api.get('/intelligence/timeline') as List)
          .map((e) => FinancialMoment.fromJson(e as Map<String, dynamic>))
          .toList();
}
