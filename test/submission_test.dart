import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/models/submission.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/data/services/submission_service.dart';
import 'package:fynnedge/features/applications/submission_card.dart';
import 'package:fynnedge/features/applications/submission_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// External submission on the customer's side.
///
/// NO LIVE LENDER SUBMISSION PROVIDER IS CONNECTED. Everything here is
/// synthetic, and no real lender or gateway is involved.
class ScriptedSubmissionService implements SubmissionService {
  ScriptedSubmissionService(this.state);

  ApplicationSubmission state;
  Object? failSubmit;

  int statusCalls = 0;
  int submitCalls = 0;

  @override
  Future<ApplicationSubmission> statusFor(String applicationId) async {
    statusCalls++;
    return state;
  }

  @override
  Future<ApplicationSubmission> submit(String applicationId) async {
    submitCalls++;
    if (failSubmit != null) throw failSubmit!;
    return state;
  }
}

ApplicationSubmission built({
  String outcome = 'simulated',
  bool providerReceived = false,
  bool isSimulated = true,
  bool canRetry = false,
  bool needsReconciliation = false,
  String? reason,
  String? providerReference,
  String displayName = 'FynnEdge Simulated Provider',
  String role = 'simulated',
}) => ApplicationSubmission.fromJson({
  'application': {
    'id': 'app_1',
    'reference': 'FE-2026-000123',
    'status': 'started',
    'status_label': 'Started',
  },
  'submission': {
    'outcome': outcome,
    'outcome_label': 'label',
    'provider_received': providerReceived,
    'is_simulated': isSimulated,
    'attempt': 1,
    'attempted_at': '2026-09-07T10:00:00+05:30',
    'provider_reference': providerReference,
    'reason': reason,
    'message': null,
    'can_retry': canRetry,
    'needs_reconciliation': needsReconciliation,
  },
  'destination': {
    'provider': 'fixture',
    'display_name': displayName,
    'role': role,
    'is_simulated': isSimulated,
  },
  'disclaimer': 'This was a simulated submission. No lender or provider '
      'received this application.',
});

Future<ProviderContainer> containerWith(SubmissionService service) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      submissionServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

void main() {
  setUpAll(initTestEnvironment);

  // --- The central distinction ---------------------------------------------

  group('the server is authoritative about what a provider did', () {
    test('a simulated outcome never reads as provider receipt', () {
      final submission = built();

      expect(submission.outcome, SubmissionOutcome.simulated);
      expect(submission.providerReceived, isFalse);
      expect(submission.isSimulated, isTrue);
    });

    test('only provider_received means an external party has it', () {
      for (final outcome in SubmissionOutcome.values) {
        final submission = built(
          outcome: outcome.id,
          providerReceived: outcome == SubmissionOutcome.providerReceived,
          isSimulated: false,
        );

        expect(
          submission.providerReceived,
          outcome == SubmissionOutcome.providerReceived,
          reason: outcome.id,
        );
      }
    });

    test('an unknown outcome is never taken for a delivery', () {
      final submission = ApplicationSubmission.fromJson(const {
        'application': {'id': '1', 'reference': 'FE-2026-000001'},
        'submission': {'outcome': 'lender_approved_it'},
      });

      expect(submission.outcome, SubmissionOutcome.unavailable);
      expect(submission.providerReceived, isFalse);
    });

    test('the FynnEdge reference survives and is not the provider\'s', () {
      final submission = built(providerReference: 'GW-9999');

      expect(submission.application.reference, 'FE-2026-000123');
      expect(submission.providerReference, 'GW-9999');
      expect(
        submission.application.reference,
        isNot(submission.providerReference),
      );
    });
  });

  // --- Mock mode -----------------------------------------------------------

  group('mock mode has no provider and says so', () {
    test('the outcome is unavailable, never failed', () async {
      final submission =
          await const MockSubmissionService().statusFor('app_1');

      expect(submission.outcome, SubmissionOutcome.unavailable);
      expect(submission.outcome, isNot(SubmissionOutcome.failed));
      expect(submission.providerReceived, isFalse);
      expect(submission.message, contains('nothing about it has failed'));
    });

    test('submitting invents no delivery', () async {
      final submission = await const MockSubmissionService().submit('app_1');

      expect(submission.outcome, SubmissionOutcome.unavailable);
      expect(submission.providerReceived, isFalse);
    });
  });

  // --- Nothing is sent unasked ---------------------------------------------

  group('an application leaves only when the customer asks', () {
    test('opening the screen reads state and sends nothing', () async {
      final service = ScriptedSubmissionService(
        built(outcome: 'not_attempted', canRetry: true),
      );
      final container = await containerWith(service);

      container.read(submissionControllerProvider('app_1'));
      await pumpEventQueue();

      expect(service.statusCalls, 1);
      expect(
        service.submitCalls,
        0,
        reason: 'opening a screen must never submit an application',
      );
    });

    test('a tap sends it exactly once', () async {
      final service = ScriptedSubmissionService(
        built(outcome: 'not_attempted', canRetry: true),
      );
      final container = await containerWith(service);

      container.read(submissionControllerProvider('app_1'));
      await pumpEventQueue();

      final controller =
          container.read(submissionControllerProvider('app_1').notifier);
      await Future.wait([controller.submit(), controller.submit()]);

      expect(service.submitCalls, 1);
    });
  });

  // --- Failures ------------------------------------------------------------

  group('a refused request is not a finding about the application', () {
    Future<SubmissionScreenState> after(Object error) async {
      final service = ScriptedSubmissionService(
        built(outcome: 'not_attempted', canRetry: true),
      )..failSubmit = error;
      final container = await containerWith(service);

      container.read(submissionControllerProvider('app_1'));
      await pumpEventQueue();
      await container
          .read(submissionControllerProvider('app_1').notifier)
          .submit();

      return container.read(submissionControllerProvider('app_1'));
    }

    test('no provider is its own state', () async {
      expect(
        (await after(CapabilityUnavailableException(
          'not connected',
          reason: 'lender_provider_unavailable',
        ))).failure,
        SubmissionFailure.notConfigured,
      );
    });

    test('missing consent is its own state, not a signed-out session',
        () async {
      expect(
        (await after(PermissionRequiredException(
          'needs consent',
          reason: 'submission_consent_required',
        ))).failure,
        SubmissionFailure.consentRequired,
      );
    });

    test('too many attempts is its own state', () async {
      expect(
        (await after(RateLimitedException('slow down'))).failure,
        SubmissionFailure.tooManyAttempts,
      );
    });

    test('a conflict is not submittable, not a provider failure', () async {
      expect(
        (await after(ApiException('conflict', statusCode: 409))).failure,
        SubmissionFailure.notSubmittable,
      );
    });
  });

  // --- What the card says --------------------------------------------------

  group('the card never claims a lender has it', () {
    Future<void> pumpWith(
      WidgetTester tester,
      ApplicationSubmission submission,
    ) async {
      await pumpScreen(
        tester,
        const Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: SubmissionCard(applicationId: 'app_1'),
            ),
          ),
        ),
        overrides: [
          submissionServiceProvider.overrideWithValue(
            ScriptedSubmissionService(submission),
          ),
        ],
      );
      await settle(tester);
    }

    testWidgets('a simulated submission says so loudly', (tester) async {
      await pumpWith(tester, built());

      expect(
        find.text('Simulated — no lender received this'),
        findsOneWidget,
      );
      expect(find.text('SIMULATED'), findsOneWidget);
      expect(
        find.textContaining('Nothing has been sent to any lender'),
        findsOneWidget,
      );

      await golden(tester, SubmissionCard, 'submission/simulated');
    });

    testWidgets('an unknown outcome offers no send-again button',
        (tester) async {
      await pumpWith(
        tester,
        built(outcome: 'unknown', needsReconciliation: true),
      );

      expect(find.textContaining("couldn't confirm delivery"), findsOneWidget);
      expect(
        find.textContaining('Please do not send it again'),
        findsOneWidget,
      );

      // A retry here could create a second application at a provider that
      // may already hold this one.
      expect(find.text('Try sending again'), findsNothing);
      expect(find.text('Submit application'), findsNothing);

      await golden(tester, SubmissionCard, 'submission/unknown');
    });

    testWidgets('a gateway rejection is not a lending decision',
        (tester) async {
      await pumpWith(
        tester,
        built(outcome: 'rejected_by_gateway', canRetry: true),
      );

      expect(
        find.textContaining('not a decision about lending to you'),
        findsOneWidget,
      );

      await golden(tester, SubmissionCard, 'submission/rejected');
    });

    testWidgets('no provider says not sent, never failed', (tester) async {
      await pumpWith(
        tester,
        built(outcome: 'unavailable', canRetry: false),
      );

      expect(find.text('Not sent anywhere'), findsOneWidget);

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ')
          .toLowerCase();

      expect(text.contains('nothing about it has failed'), isTrue);

      await golden(tester, SubmissionCard, 'submission/unavailable');
    });

    testWidgets('ready to send names the destination as simulated',
        (tester) async {
      await pumpWith(
        tester,
        built(outcome: 'not_attempted', canRetry: true),
      );

      expect(find.text('Submit application'), findsOneWidget);
      expect(find.text('Would go to'), findsOneWidget);
      expect(find.text('FynnEdge Simulated Provider'), findsOneWidget);
      expect(
        find.textContaining('Nothing will be sent to a lender'),
        findsOneWidget,
      );

      await golden(tester, SubmissionCard, 'submission/ready');
    });

    testWidgets('consent required offers the way to grant it',
        (tester) async {
      await pumpWith(
        tester,
        built(
          outcome: 'not_attempted',
          reason: 'submission_consent_required',
        ),
      );

      expect(find.text('Your permission is needed'), findsOneWidget);
      expect(find.text('Review and allow sending'), findsOneWidget);
      expect(find.text('Submit application'), findsNothing);

      await golden(tester, SubmissionCard, 'submission/consent_required');
    });

    testWidgets('no state claims approval or a lender receipt',
        (tester) async {
      for (final outcome in [
        'simulated', 'not_attempted', 'unavailable', 'failed',
        'unknown', 'rejected_by_gateway',
      ]) {
        await pumpWith(tester, built(outcome: outcome, canRetry: true));

        // Negations are stripped first: "no lender received this" is the
        // honest sentence, and a bare substring sweep would flag exactly
        // the copy the module exists to produce.
        final text = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join(' ')
            .toLowerCase()
            .replaceAll('no lender received this', '')
            .replaceAll('no lender or provider received this', '')
            .replaceAll('nothing has been sent to any lender', '')
            .replaceAll('nothing will be sent to a lender', '')
            .replaceAll('no lender has seen it', '');

        for (final claim in [
          'approved', 'pre-approved', 'guaranteed', 'you qualify',
          'eligible', 'lender received', 'received by lender',
          'submitted to lender', 'sanctioned', 'disbursed',
          'get loan now', 'lender has your',
        ]) {
          expect(
            text.contains(claim),
            isFalse,
            reason: '$outcome said: $claim',
          );
        }
      }
    });
  });
}
