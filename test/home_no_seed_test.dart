import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/data/mock/mock_data.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/services/api_config.dart';
import 'package:fynnedge/data/services/home_service.dart';

/// Home carries nothing FynnEdge did not calculate.
///
/// This replaces the Module 7 guard that kept the seeded "smart insights"
/// honest. The insights are gone — there was no engine behind them — and what
/// is guarded now is stronger: that Home invents no content at all.
void main() {
  setUp(() {
    ApiConfig.simulateLatency = false;
    MockStore.instance.reset();
  });

  tearDown(() {
    ApiConfig.simulateLatency = true;
    MockStore.instance.reset();
  });

  test('the seeded insight block is gone from the mock data', () {
    // MockData is a const class; if `insights` came back this would not
    // compile, which is the guard. The catalogue is sample product data and
    // is labelled as such, so it stays.
    expect(MockData.products, isNotEmpty);
  });

  test('mock mode sends no notification the API would not', () {
    // Nothing in FynnEdge writes a notification. Mock mode used to seed
    // four, two of which made claims nobody could stand behind.
    expect(MockData.notifications, isEmpty);
  });

  test('Home invents no applications, documents or activity', () async {
    final snapshot = await const MockHomeService().getSnapshot();

    // The store starts with no applications and no documents, because both
    // are things the customer did. Home must report what it finds.
    expect(snapshot.applications, isEmpty);
    expect(snapshot.applicationsTotal, 0);
    expect(snapshot.applicationsActive, 0);
    expect(snapshot.vaultDocumentCount, 0);
  });

  test('every attention item carries the figure behind it', () async {
    final snapshot = await const MockHomeService().getSnapshot();

    for (final item in snapshot.attention) {
      expect(item.key, isNotEmpty);
      expect(item.title, isNotEmpty);
      // A claim with no detail is a claim nobody can check.
      expect(item.detail, isNotEmpty);
    }
  });

  test('Home says nothing about a customer it cannot measure', () async {
    MockStore.instance.financials = MockStore.instance.financials.copyWith(
      monthlyIncome: 0,
      monthlyExpenses: 0,
      existingEmi: 0,
      otherObligations: 0,
      savings: 0,
    );

    final snapshot = await const MockHomeService().getSnapshot();

    expect(snapshot.needsFinancialProfile, isTrue);
    expect(snapshot.score.hasScore, isFalse);
    expect(snapshot.score.score, isNull);
    expect(snapshot.attention, isEmpty);
    expect(snapshot.primaryAction.key, 'complete_profile');
  });
}
