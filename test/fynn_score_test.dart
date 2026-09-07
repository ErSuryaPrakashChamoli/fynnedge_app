import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/core/money/money.dart';
import 'package:fynnedge/data/engine/financial_engine.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/score.dart';
import 'package:fynnedge/data/models/user.dart';
import 'package:fynnedge/data/score/fynn_score_engine.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/home/home_controller.dart';
import 'package:fynnedge/features/profile/financial_profile_controller.dart';
import 'package:fynnedge/features/profile/profile_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

const _engine = FynnScoreEngine();
const _financial = FinancialEngine();

FynnScore scoreOf({
  required String income,
  String expenses = '0.00',
  String emi = '0.00',
  String savings = '0.00',
  String obligations = '0.00',
}) => _engine.score(
  _financial.snapshot(
    income: Money.of(income),
    expenses: Money.of(expenses),
    existingEmi: Money.of(emi),
    otherObligations: Money.of(obligations),
    savings: Money.of(savings),
  ),
);

ScoreDimension dimensionOf(FynnScore score, String key) =>
    score.dimensions.firstWhere((d) => d.key == key);

void main() {
  setUpAll(initUnitTestEnvironment);

  group('Determinism', () {
    test('identical inputs always give an identical score', () {
      final a = scoreOf(
        income: '100000.00',
        expenses: '40000.00',
        emi: '20000.00',
        savings: '180000.00',
      );
      final b = scoreOf(
        income: '100000.00',
        expenses: '40000.00',
        emi: '20000.00',
        savings: '180000.00',
      );

      expect(a.score, b.score);
      expect(a.toJson(), b.toJson());
    });
  });

  group('Anchors', () {
    test('an EMI ratio of 20% scores full marks', () {
      final s = scoreOf(income: '100000.00', emi: '20000.00');
      expect(dimensionOf(s, 'emi_burden').score, 100);
    });

    test('an EMI ratio of 45% scores zero', () {
      final s = scoreOf(income: '100000.00', emi: '45000.00');
      expect(dimensionOf(s, 'emi_burden').metricValue, 45);
      expect(dimensionOf(s, 'emi_burden').score, 0);
    });

    test('the EMI curve is linear at its midpoint', () {
      // 32.5% is halfway between the 20% and 45% anchors.
      final s = scoreOf(income: '100000.00', emi: '32500.00');
      expect(dimensionOf(s, 'emi_burden').score, 50);
    });

    test('spending anchors at 40% and 80%', () {
      expect(
        dimensionOf(
          scoreOf(income: '100000.00', expenses: '40000.00'),
          'spending_control',
        ).score,
        100,
      );
      expect(
        dimensionOf(
          scoreOf(income: '100000.00', expenses: '80000.00'),
          'spending_control',
        ).score,
        0,
      );
    });

    test('six months of cover scores full marks', () {
      // Outgo 50,000; savings 300,000 = exactly 6 months.
      final s = scoreOf(
        income: '100000.00',
        expenses: '40000.00',
        emi: '10000.00',
        savings: '300000.00',
      );
      expect(dimensionOf(s, 'emergency_buffer').metricValue, 6);
      expect(dimensionOf(s, 'emergency_buffer').score, 100);
    });
  });

  group('One metric moves one dimension', () {
    test('the EMI ratio moves only the EMI dimension', () {
      final before = scoreOf(
        income: '100000.00',
        expenses: '40000.00',
        emi: '10000.00',
        savings: '360000.00',
      );
      final after = scoreOf(
        income: '100000.00',
        expenses: '40000.00',
        emi: '40000.00',
        savings: '360000.00',
      );

      expect(
        dimensionOf(before, 'emi_burden').score,
        isNot(dimensionOf(after, 'emi_burden').score),
      );
      expect(
        dimensionOf(before, 'spending_control').score,
        dimensionOf(after, 'spending_control').score,
      );
    });

    test('savings move only the emergency dimension', () {
      final before = scoreOf(
        income: '100000.00',
        expenses: '40000.00',
        emi: '20000.00',
        savings: '60000.00',
      );
      final after = scoreOf(
        income: '100000.00',
        expenses: '40000.00',
        emi: '20000.00',
        savings: '360000.00',
      );

      expect(
        dimensionOf(before, 'emergency_buffer').score,
        isNot(dimensionOf(after, 'emergency_buffer').score),
      );
      expect(
        dimensionOf(before, 'emi_burden').score,
        dimensionOf(after, 'emi_burden').score,
      );
    });
  });

  group('Range and bands', () {
    test('the score never leaves 0..100', () {
      for (final s in [
        scoreOf(income: '1000000.00', savings: '99999999.00'),
        scoreOf(income: '1000.00', expenses: '999999.00', emi: '999999.00'),
        scoreOf(income: '1.00'),
      ]) {
        if (!s.hasScore) continue;
        expect(s.score, greaterThanOrEqualTo(0));
        expect(s.score, lessThanOrEqualTo(100));
      }
    });

    test('bands follow the 75/55/40 breakpoints', () {
      expect(ScoreBand.forScore(100), ScoreBand.strong);
      expect(ScoreBand.forScore(75), ScoreBand.strong);
      expect(ScoreBand.forScore(74), ScoreBand.good);
      expect(ScoreBand.forScore(55), ScoreBand.good);
      expect(ScoreBand.forScore(54), ScoreBand.needsAttention);
      expect(ScoreBand.forScore(40), ScoreBand.needsAttention);
      expect(ScoreBand.forScore(39), ScoreBand.atRisk);
      expect(ScoreBand.forScore(0), ScoreBand.atRisk);
    });
  });

  group('Insufficient data', () {
    test('zero income yields no score at all', () {
      final s = scoreOf(income: '0.00', expenses: '20000.00');

      expect(s.hasScore, isFalse);
      expect(s.score, isNull);
      expect(s.band, isNull);
      expect(s.dimensions, isEmpty);
      expect(s.missingRequirements, ['monthly_income']);
      expect(s.summary, contains('monthly income'));
    });

    test('income alone is enough to produce a score', () {
      final s = scoreOf(income: '50000.00');
      expect(s.hasScore, isTrue);
      expect(s.score, isNotNull);
    });
  });

  group('Explanations', () {
    test('each dimension names the metric it reads', () {
      final s = scoreOf(
        income: '100000.00',
        expenses: '40000.00',
        emi: '20000.00',
        savings: '180000.00',
      );

      expect(dimensionOf(s, 'emi_burden').metric, 'emi_ratio');
      expect(dimensionOf(s, 'spending_control').metric, 'expense_ratio');
      expect(dimensionOf(s, 'emergency_buffer').metric, 'emergency_months');

      for (final d in s.dimensions) {
        expect(d.explanation, isNotEmpty);
        expect(s.metrics[d.metric], d.metricValue);
      }
    });

    test('recommendation impact is reproducible from the response', () {
      final s = scoreOf(
        income: '100000.00',
        expenses: '40000.00',
        emi: '20000.00',
        savings: '180000.00',
      );

      expect(s.recommendations, isNotEmpty);
      for (final r in s.recommendations) {
        expect(r.currentScore, s.score);
        expect(r.delta, r.projectedScore - r.currentScore);
        expect(r.delta, greaterThan(0));
      }
    });

    test('a perfect profile has nothing to recommend', () {
      final s = scoreOf(
        income: '200000.00',
        expenses: '60000.00',
        emi: '20000.00',
        savings: '1000000.00',
      );
      expect(s.score, 100);
      expect(s.recommendations, isEmpty);
    });
  });

  group('No prototype values survive', () {
    test('the old dimension names are gone', () {
      final s = scoreOf(
        income: '100000.00',
        expenses: '40000.00',
        emi: '20000.00',
        savings: '180000.00',
      );
      final names = s.dimensions.map((d) => d.name).toList();

      expect(names, ['EMI Burden', 'Spending Control', 'Emergency Buffer']);
      expect(names, isNot(contains('Income stability')));
      expect(names, isNot(contains('Credit conduct')));
    });

    test('the demo customer no longer scores the prototype 74', () {
      // The prototype showed 74; the real model gives 83 for these figures.
      final s = scoreOf(
        income: '100000.00',
        expenses: '40000.00',
        emi: '20000.00',
        savings: '180000.00',
      );
      expect(s.score, 83);
    });
  });

  group('Serialisation', () {
    test('a score survives toJson then fromJson', () {
      final original = scoreOf(
        income: '100000.00',
        expenses: '40000.00',
        emi: '20000.00',
        savings: '180000.00',
      );
      final restored = FynnScore.fromJson(original.toJson());

      expect(restored.score, original.score);
      expect(restored.band, original.band);
      expect(restored.modelVersion, original.modelVersion);
      expect(restored.dimensions, hasLength(original.dimensions.length));
      expect(
        restored.dimensions.first.metric,
        original.dimensions.first.metric,
      );
      expect(
        restored.recommendations,
        hasLength(original.recommendations.length),
      );
      expect(restored.helping, original.helping);
      expect(restored.needsAttention, original.needsAttention);
    });

    test('an insufficient-data response round-trips', () {
      final original = scoreOf(income: '0.00', expenses: '20000.00');
      final restored = FynnScore.fromJson(original.toJson());

      expect(restored.hasScore, isFalse);
      expect(restored.score, isNull);
      expect(restored.missingRequirements, ['monthly_income']);
    });

    test('a malformed payload does not crash', () {
      final s = FynnScore.fromJson(const {});
      expect(s.dimensions, isEmpty);
      expect(s.score, isNull);
    });

    test('the model version is always reported', () {
      final s = scoreOf(income: '100000.00');
      expect(s.modelVersion, 'fynnscore-v1');
      expect(s.toJson()['model_version'], 'fynnscore-v1');
    });
  });

  group('Mock mode', () {
    setUp(MockStore.instance.reset);
    tearDown(MockStore.instance.reset);

    Future<ProviderContainer> mockContainer() async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('mock mode serves the real scoring model', () async {
      final container = await mockContainer();
      final score = await container.read(fynnScoreProvider.future);

      expect(score.hasScore, isTrue);
      expect(score.modelVersion, 'fynnscore-v1');
      // The seeded customer's real score under v1.
      expect(score.score, 83);
      expect(score.band, ScoreBand.strong);
    });

    test('editing the financial profile moves the score', () async {
      final container = await mockContainer();
      container.listen(financialProfileControllerProvider, (_, _) {});

      final before = await container.read(fynnScoreProvider.future);

      // Push EMIs to the 45% ceiling.
      final controller = container.read(
        financialProfileControllerProvider.notifier,
      );
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (container.read(financialProfileControllerProvider).loading) {
        if (DateTime.now().isAfter(deadline)) fail('profile never loaded');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      controller.edit(
        container
            .read(financialProfileControllerProvider)
            .saved!
            .copyWith(existingEmi: 45000),
      );
      expect(await controller.save(), isTrue);

      final after = await container.read(fynnScoreProvider.future);
      expect(after.score, lessThan(before.score!));
    });

    test('Home carries the same score as the FynnScore screen', () async {
      final container = await mockContainer();

      final direct = await container.read(fynnScoreProvider.future);
      final home = await container.read(homeSnapshotProvider.future);

      expect(home.score.score, direct.score);
      expect(home.score.band, direct.band);
      expect(home.score.modelVersion, direct.modelVersion);
    });

    test('a customer with no income gets no score, in mock mode too', () async {
      MockStore.instance.financials = const FinancialProfile(
        monthlyIncome: 0,
        monthlyExpenses: 20000,
      );

      final container = await mockContainer();
      final score = await container.read(fynnScoreProvider.future);

      expect(score.hasScore, isFalse);
      expect(score.missingRequirements, ['monthly_income']);
    });
  });
}
