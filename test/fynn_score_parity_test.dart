import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/core/money/money.dart';
import 'package:fynnedge/data/engine/financial_engine.dart';
import 'package:fynnedge/data/models/score.dart';
import 'package:fynnedge/data/score/fynn_score_engine.dart';

/// Proves the Flutter scoring engine agrees with the Laravel one, case for
/// case, against the fixture the backend generated.
///
/// If either engine changes an anchor, a weight or a rounding rule, this
/// fails — which is the point: mock mode and the real API must never show a
/// customer two different scores for the same figures.
void main() {
  const engine = FynnScoreEngine();
  const financial = FinancialEngine();

  final file = File('test/fixtures/fynnscore_parity.json');
  if (!file.existsSync()) {
    test('the score parity fixture is present', () {
      fail(
        'test/fixtures/fynnscore_parity.json is missing. Regenerate with:\n'
        '  cd ../fynnedge-api && php artisan fynn:parity-fixture',
      );
    });
    return;
  }

  final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  FynnScore scoreFor(Map<String, dynamic> profile) => engine.score(
    financial.snapshot(
      income: Money.of(profile['monthly_income']),
      expenses: Money.of(profile['monthly_expenses']),
      existingEmi: Money.of(profile['existing_emi']),
      otherObligations: Money.of(profile['other_obligations']),
      savings: Money.of(profile['savings']),
    ),
  );

  test('the fixture is for the model this engine implements', () {
    expect(fixture['model_version'], FynnScoreEngine.modelVersion);
  });

  test('the matrix covers every required situation', () {
    final names = cases.map((c) => c['name'] as String).toList();
    for (final required in const [
      'healthy_profile',
      'high_emi_burden',
      'high_spending_ratio',
      'low_emergency_savings',
      'negative_surplus',
      'strong_goal_progress',
      'weak_goal_progress',
      'zero_income',
      'all_zero_profile',
      'incomplete_profile',
    ]) {
      expect(names, contains(required));
    }
  });

  for (final testCase in cases) {
    final name = testCase['name'] as String;
    final profile = ((testCase['input'] as Map)['profile'] as Map)
        .cast<String, dynamic>();
    final expected = (testCase['expected'] as Map).cast<String, dynamic>();

    group(name, () {
      test('overall score and band match the backend', () {
        final actual = scoreFor(profile);

        expect(actual.hasScore, expected['status'] == 'ok', reason: 'status');
        expect(actual.score, expected['score'], reason: 'score');
        expect(actual.band?.id, expected['band'], reason: 'band');
        expect(actual.modelVersion, expected['model_version']);
        expect(actual.summary, expected['summary'], reason: 'summary');
      });

      test('dimensions match the backend', () {
        final actual = scoreFor(profile);
        final want = (expected['dimensions'] as List)
            .cast<Map<String, dynamic>>();

        expect(actual.dimensions, hasLength(want.length));

        for (var i = 0; i < want.length; i++) {
          final a = actual.dimensions[i];
          final w = want[i];

          expect(a.key, w['key'], reason: 'dimension $i key');
          expect(a.name, w['name'], reason: '${a.key} name');
          expect(a.score, w['score'], reason: '${a.key} score');
          expect(a.metric, w['metric'], reason: '${a.key} metric');
          expect(
            a.metricValue,
            (w['metric_value'] as num).toDouble(),
            reason: '${a.key} metric value',
          );
          expect(a.isHelping, w['is_helping'], reason: '${a.key} is_helping');
          expect(
            a.explanation,
            w['explanation'],
            reason: '${a.key} explanation must match word for word',
          );
        }
      });

      test('recommendations match the backend', () {
        final actual = scoreFor(profile);
        final want = (expected['recommendations'] as List)
            .cast<Map<String, dynamic>>();

        expect(actual.recommendations, hasLength(want.length));

        for (var i = 0; i < want.length; i++) {
          final a = actual.recommendations[i];
          final w = want[i];

          expect(a.dimension, w['dimension'], reason: 'recommendation $i');
          expect(a.title, w['title']);
          expect(a.detail, w['detail'], reason: 'detail must match exactly');
          expect(a.currentScore, w['current_score']);
          expect(a.projectedScore, w['projected_score']);
          expect(a.delta, w['delta']);
        }
      });

      test('missing requirements match the backend', () {
        final actual = scoreFor(profile);
        expect(
          actual.missingRequirements,
          (expected['missing_requirements'] as List).cast<String>(),
        );
      });
    });
  }

  group('Goals never move the score', () {
    test('the two goal cases share a profile and a score', () {
      final byName = {for (final c in cases) c['name'] as String: c};
      final strong = byName['strong_goal_progress']!;
      final weak = byName['weak_goal_progress']!;

      // Identical finances, very different goals...
      expect(
        (strong['input'] as Map)['profile'],
        (weak['input'] as Map)['profile'],
      );
      expect(
        (strong['input'] as Map)['goals'],
        isNot((weak['input'] as Map)['goals']),
      );

      // ...and therefore an identical score, in Dart as in PHP.
      final a = scoreFor(
        ((strong['input'] as Map)['profile'] as Map).cast<String, dynamic>(),
      );
      final b = scoreFor(
        ((weak['input'] as Map)['profile'] as Map).cast<String, dynamic>(),
      );

      expect(a.score, b.score);
      expect(a.score, (strong['expected'] as Map)['score']);
    });
  });
}
