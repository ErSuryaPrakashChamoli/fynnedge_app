import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/core/money/money.dart';
import 'package:fynnedge/data/engine/financial_engine.dart';
import 'package:fynnedge/data/home/attention_rules.dart';
import 'package:fynnedge/data/models/goal.dart';
import 'package:fynnedge/data/models/intent.dart';

/// Proves the Flutter attention rules agree with the Laravel ones, case for
/// case, against the fixture the backend generated.
///
/// Home is where a customer is told what matters about their money. If mock
/// mode raised a different item, raised them in a different order, or worded
/// one differently, the version of FynnEdge being demonstrated would not be
/// the version that ships.
void main() {
  final file = File('test/fixtures/home_attention_parity.json');
  if (!file.existsSync()) {
    test('the attention parity fixture is present', () {
      fail(
        'test/fixtures/home_attention_parity.json is missing. Regenerate:\n'
        '  cd ../fynnedge-api && php artisan fynn:parity-fixture',
      );
    });
    return;
  }

  final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  test('the fixture agrees about the thresholds the rules read', () {
    expect(
      fixture['affordability_reference_percent'],
      FinancialEngine.affordabilityCeilingPercent,
    );
    expect(
      fixture['emergency_fund_target_months'],
      FinancialEngine.emergencyFundTargetMonths,
    );
  });

  test('every case is covered', () => expect(cases, isNotEmpty));

  for (final c in cases) {
    final name = c['name'] as String;
    final input = c['input'] as Map<String, dynamic>;
    final profile = input['profile'] as Map<String, dynamic>;
    final expected = (c['expected'] as List).cast<Map<String, dynamic>>();

    test('$name — ${c['note']}', () {
      final snapshot = financialEngine.snapshot(
        income: Money.of(profile['monthly_income'] as num),
        expenses: Money.of(profile['monthly_expenses'] as num),
        existingEmi: Money.of(profile['existing_emi'] as num),
        otherObligations: Money.of(profile['other_obligations'] as num),
        savings: Money.of(profile['savings'] as num),
      );

      final goals = (input['goals'] as List)
          .cast<Map<String, dynamic>>()
          .map(
            (g) => Goal(
              id: '',
              title: g['title'] as String,
              category: GoalCategory.other,
              targetAmount: (g['target_amount'] as num).toDouble(),
              savedAmount: (g['saved_amount'] as num).toDouble(),
              targetDate: DateTime.parse(g['target_date'] as String),
            ),
          )
          .toList();

      final items = attentionRules.evaluate(financials: snapshot, goals: goals);

      // The order is the priority, so it is asserted as a whole rather than
      // item by item.
      expect(
        items.map((i) => i.key).toList(),
        expected.map((e) => e['key']).toList(),
        reason: 'wrong items, or the wrong order, for "$name"',
      );

      for (var i = 0; i < expected.length; i++) {
        expect(items[i].severity.id, expected[i]['severity']);
        expect(items[i].title, expected[i]['title']);
        expect(items[i].detail, expected[i]['detail']);
        expect(items[i].actionLabel, expected[i]['action_label']);
        expect(items[i].actionRoute, expected[i]['action_route']);
      }
    });
  }
}
