import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/data/models/application.dart';

/// Proves the Flutter application model reads exactly what Laravel sends, for
/// every lifecycle state the product can actually reach.
///
/// The provider-decision states are absent on purpose: no gateway in the
/// codebase can produce one, and a fixture for a state nothing can enter
/// would be a promise the code does not keep. What is asserted here is that
/// the model parses them safely if one ever arrives.
void main() {
  final file = File('test/fixtures/application_lifecycle.json');
  if (!file.existsSync()) {
    test('the application lifecycle fixture is present', () {
      fail(
        'test/fixtures/application_lifecycle.json is missing. Regenerate:\n'
        '  cd ../fynnedge-api && php artisan fynn:parity-fixture',
      );
    });
    return;
  }

  final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  LoanApplication parse(String name) => LoanApplication.fromJson(
    cases.firstWhere((c) => c['name'] == name)['payload']
        as Map<String, dynamic>,
  );

  test('the fixture covers the states the product implements', () {
    expect(
      cases.map((c) => c['name']).toList(),
      fixture['implemented_states'],
    );
  });

  test('a started application claims nothing', () {
    final a = parse('started');

    expect(a.status, ApplicationStatus.started);
    expect(a.canSubmit, isTrue);
    expect(a.isEditable, isTrue);
    expect(a.isSimulated, isFalse);
    expect(a.gateway, isNull);
    expect(a.submittedAt, isNull);
    expect(a.acknowledgedAt, isNull);
    expect(a.events.single.source, EventSource.fynnedge);
  });

  test('a submitted application is marked simulated, with no provider', () {
    final a = parse('submitted');

    expect(a.status, ApplicationStatus.submitted);
    expect(a.canSubmit, isFalse);
    expect(a.isEditable, isFalse);
    expect(a.canCancel, isTrue);
    expect(a.isSimulated, isTrue);
    expect(a.gateway, 'mock');
    expect(a.providerReference, isNull);
    expect(a.hasProviderEvents, isFalse);
    expect(a.events.last.source, EventSource.simulated);
    expect(a.events.last.detail, contains('No provider has received'));
    expect(a.status.isProviderDecision, isFalse);
  });

  test('a cancelled application is closed', () {
    final a = parse('cancelled');

    expect(a.status, ApplicationStatus.cancelled);
    expect(a.status.isTerminal, isTrue);
    expect(a.canSubmit, isFalse);
    expect(a.canCancel, isFalse);
    expect(a.isSimulated, isFalse);
    expect(a.events.last.source, EventSource.fynnedge);
  });

  test('the customer is asked to confirm the same two things on both sides', () {
    final acknowledgements = (fixture['acknowledgements'] as List).cast<String>();

    expect(acknowledgements, hasLength(2));
    expect(parse('started').acknowledgements, acknowledgements);

    // Neither statement claims a consent FynnEdge does not hold.
    final text = acknowledgements.join(' ').toLowerCase();
    for (final absent in const ['bureau', 'cibil', 'credit report', 'credit check']) {
      expect(text, isNot(contains(absent)));
    }
  });

  test('a provider state is understood but never produced here', () {
    final providerStates = (fixture['provider_states'] as List).cast<String>();

    for (final state in providerStates) {
      final status = ApplicationStatus.fromId(state);
      expect(status.id, state, reason: '$state must parse to itself');
      expect(status.isProviderDecision, isTrue);
    }

    // And nothing the product can currently produce is one of them.
    for (final name in (fixture['implemented_states'] as List).cast<String>()) {
      expect(ApplicationStatus.fromId(name).isProviderDecision, isFalse);
    }
  });

  test('every fixture payload round-trips through the model', () {
    for (final testCase in cases) {
      final payload = testCase['payload'] as Map<String, dynamic>;
      final parsed = LoanApplication.fromJson(payload);
      final restored = LoanApplication.fromJson(parsed.toJson());

      expect(
        restored.toJson(),
        parsed.toJson(),
        reason: '${testCase['name']} did not survive a round trip',
      );

      // The figures the customer chose, unchanged by parsing.
      expect(parsed.amount, payload['amount']);
      expect(parsed.tenureMonths, payload['tenure_months']);
      expect(parsed.productId, payload['product_id']);
      expect(parsed.emi, payload['emi']);
    }
  });
}
