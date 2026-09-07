import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/models/credit.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/credit_service.dart';
import 'package:fynnedge/features/credit/credit_screen.dart';

import 'support/harness.dart';

/// Every credit state, drawn.
///
/// The screen is where the four concepts are most likely to blur, so each
/// state gets a golden and each one is checked for language that would
/// promise something FynnEdge cannot.
class FixedCreditService implements CreditService {
  FixedCreditService(this.state, {this.failure});

  final CreditState state;
  final Object? failure;

  @override
  Future<CreditState> getStatus() async => state;

  @override
  Future<CreditState> check() async {
    if (failure != null) throw failure!;
    return state;
  }
}

CreditState reported() => CreditState(
  status: CreditReportStatus.available,
  profile: CreditProfile.fromJson({
    'score': 742,
    'score_model': 'SAMPLE-SCORE-V1',
    'scale': {'min': 300, 'max': 900},
    'bureau': 'fixture',
    'bureau_label': 'Sample Bureau',
    'is_sample': true,
    'obtained_at': '2026-09-06T10:00:00+05:30',
  }),
);

void main() {
  setUpAll(initTestEnvironment);

  Future<void> pumpWith(
    WidgetTester tester,
    CreditState state, {
    Object? failure,
  }) async {
    await pumpScreen(
      tester,
      const CreditScreen(),
      overrides: [
        creditServiceProvider.overrideWithValue(
          FixedCreditService(state, failure: failure),
        ),
      ],
    );
    await settle(tester);
  }

  testWidgets('a report shows its score, model and scale together',
      (tester) async {
    await pumpWith(tester, reported());

    expect(find.text('742'), findsOneWidget);
    expect(find.text('of 300–900'), findsOneWidget);
    expect(find.text('SAMPLE-SCORE-V1'), findsOneWidget);

    // A fictional score is labelled as one, on the same card as the number.
    expect(find.text('Sample data'), findsOneWidget);

    await golden(tester, CreditScreen, 'credit/available');
  });

  testWidgets('consent required offers the way to grant it', (tester) async {
    await pumpWith(
      tester,
      const CreditState(status: CreditReportStatus.consentRequired),
    );

    expect(find.text('Your permission comes first'), findsOneWidget);
    expect(find.text('Privacy & Consent'), findsOneWidget);

    // No check button: there is nothing to check until consent exists.
    expect(find.text('Check my credit information'), findsNothing);

    await golden(tester, CreditScreen, 'credit/consent_required');
  });

  testWidgets('permitted but never asked offers the check', (tester) async {
    await pumpWith(
      tester,
      const CreditState(status: CreditReportStatus.notRequested),
    );

    expect(find.text('Nothing checked yet'), findsOneWidget);
    expect(find.text('Check my credit information'), findsOneWidget);

    await golden(tester, CreditScreen, 'credit/not_requested');
  });

  testWidgets('an unreachable bureau shows no number at all', (tester) async {
    await pumpWith(
      tester,
      const CreditState(status: CreditReportStatus.notRequested),
      failure: UpstreamUnavailableException('down'),
    );

    await tester.tap(find.text('Check my credit information'));
    await settle(tester);

    expect(find.text('We could not reach the bureau'), findsOneWidget);

    // Nothing invented, and no zero standing in for a score.
    expect(find.text('0'), findsNothing);
    expect(find.textContaining('of 300–900'), findsNothing);

    await golden(tester, CreditScreen, 'credit/bureau_unavailable');
  });

  testWidgets('no state promises an approval or a soft enquiry',
      (tester) async {
    for (final state in [
      reported(),
      const CreditState(status: CreditReportStatus.notConfigured),
      const CreditState(status: CreditReportStatus.consentRequired),
      const CreditState(status: CreditReportStatus.notRequested),
      const CreditState(status: CreditReportStatus.failed),
    ]) {
      await pumpWith(tester, state);

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ')
          .toLowerCase();

      for (final claim in [
        // Approval is a provider's decision, not FynnEdge's.
        'approved', 'pre-approved', 'you qualify', 'guaranteed',
        'eligible for', 'you will get',
        // No contract guarantees this, so FynnEdge does not say it.
        'soft enquiry', 'soft check', 'will not affect',
        "won't affect", 'no impact on your score',
        // The two numbers are never presented as one.
        'your fynnscore is', 'credit health score',
      ]) {
        expect(
          text.contains(claim),
          isFalse,
          reason: '${state.status.id} said: $claim',
        );
      }
    }
  });
}
