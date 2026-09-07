import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/models/credit.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/credit_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/credit/credit_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// The credit boundary, as the app sees it.
///
/// NO LIVE BUREAU IS CONNECTED TO FYNNEDGE. Nothing here reaches a network,
/// and no real person's credit information is involved.
class ScriptedCreditService implements CreditService {
  ScriptedCreditService({this.status = CreditState.unknown});

  CreditState status;
  Object? failCheck;
  CreditState? checkResult;

  int statusCalls = 0;
  int checkCalls = 0;

  @override
  Future<CreditState> getStatus() async {
    statusCalls++;
    return status;
  }

  @override
  Future<CreditState> check() async {
    checkCalls++;
    if (failCheck != null) throw failCheck!;
    return checkResult ?? status;
  }
}

Future<ProviderContainer> containerWith(CreditService service) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      creditServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

CreditState available({int score = 742}) => CreditState(
  status: CreditReportStatus.available,
  profile: CreditProfile.fromJson({
    'score': score,
    'score_model': 'SAMPLE-SCORE-V1',
    'scale': {'min': 300, 'max': 900},
    'bureau': 'fixture',
    'bureau_label': 'Sample Bureau',
    'is_sample': true,
    'obtained_at': '2026-09-06T10:00:00+05:30',
  }),
);

void main() {
  setUpAll(initUnitTestEnvironment);

  // --- Reading a report ----------------------------------------------------

  group('a score is never separated from what it means', () {
    test('a complete report parses', () {
      final profile = CreditProfile.fromJson({
        'score': 742,
        'score_model': 'SAMPLE-SCORE-V1',
        'scale': {'min': 300, 'max': 900},
        'bureau_label': 'Sample Bureau',
        'is_sample': true,
      });

      expect(profile, isNotNull);
      expect(profile!.score, 742);
      expect(profile.scoreModel, 'SAMPLE-SCORE-V1');
      expect(profile.scaleLabel, '300–900');
      expect(profile.isSample, isTrue);
    });

    for (final entry in <String, Map<String, dynamic>>{
      'no score': {'score': null},
      'no scoring model': {'score_model': null},
      'no scale': {'scale': null},
      'half a scale': {
        'scale': {'min': 300},
      },
    }.entries) {
      test('refused: ${entry.key}', () {
        // A number with no model and no scale cannot be compared against a
        // documented minimum, and cannot be drawn. It is refused rather
        // than rendered with invented context.
        expect(
          CreditProfile.fromJson({
            'score': 742,
            'score_model': 'SAMPLE-SCORE-V1',
            'scale': {'min': 300, 'max': 900},
            ...entry.value,
          }),
          isNull,
          reason: entry.key,
        );
      });
    }

    test('a score outside its own scale still draws inside the bar', () {
      final low = CreditProfile.fromJson({
        'score': 100,
        'score_model': 'M',
        'scale': {'min': 300, 'max': 900},
      })!;

      expect(low.positionOnScale, 0);
      expect(low.score, 100, reason: 'the reported score is not altered');
    });

    test('an unreadable scale never divides by zero', () {
      final flat = CreditProfile.fromJson({
        'score': 500,
        'score_model': 'M',
        'scale': {'min': 500, 'max': 500},
      })!;

      expect(flat.positionOnScale, 0);
    });
  });

  group('an unknown state is never a good one', () {
    test('a status this build does not know parses as unknown', () {
      final state = CreditState.fromJson({'status': 'something_new'});

      expect(state.status, CreditReportStatus.unknown);
      expect(state.hasReport, isFalse);
      expect(state.canCheck, isFalse);
    });

    test('available with an unreadable report is not a report', () {
      final state = CreditState.fromJson({
        'status': 'available',
        'profile': {'score': 742},
      });

      expect(state.status, CreditReportStatus.available);
      expect(
        state.hasReport,
        isFalse,
        reason: 'a report that cannot be read is not one FynnEdge holds',
      );
    });

    test('no bureau connected means nothing to check', () {
      final state = CreditState.fromJson({'status': 'not_configured'});

      expect(state.isUnavailable, isTrue);
      expect(state.canCheck, isFalse);
      expect(state.needsConsent, isFalse);
    });

    test('consent required is not the same as no bureau', () {
      final state = CreditState.fromJson({'status': 'consent_required'});

      expect(state.needsConsent, isTrue);
      expect(state.isUnavailable, isFalse);
      expect(state.canCheck, isFalse);
    });
  });

  // --- Mock mode -----------------------------------------------------------

  group('mock mode has no bureau and says so', () {
    test('the status is not_configured', () async {
      final state = await const MockCreditService().getStatus();

      expect(state.status, CreditReportStatus.notConfigured);
      expect(state.profile, isNull);
    });

    test('a check refuses rather than inventing a score', () async {
      // A fictional credit score shown in a demo is the exact confusion
      // this module exists to prevent.
      await expectLater(
        const MockCreditService().check(),
        throwsA(isA<CapabilityUnavailableException>()),
      );
    });
  });

  // --- The controller ------------------------------------------------------

  group('a bureau is asked only when the customer asks', () {
    test('loading the screen asks no bureau', () async {
      final service = ScriptedCreditService(
        status: const CreditState(status: CreditReportStatus.notRequested),
      );
      final container = await containerWith(service);

      container.read(creditControllerProvider);
      await pumpEventQueue();

      expect(service.statusCalls, 1);
      expect(
        service.checkCalls,
        0,
        reason: 'opening a screen must never cost the customer an enquiry',
      );
    });

    test('a tap makes exactly one request', () async {
      final service = ScriptedCreditService(
        status: const CreditState(status: CreditReportStatus.notRequested),
      )..checkResult = available();
      final container = await containerWith(service);

      container.read(creditControllerProvider);
      await pumpEventQueue();

      await container.read(creditControllerProvider.notifier).check();

      expect(service.checkCalls, 1);
      expect(container.read(creditControllerProvider).credit?.hasReport, isTrue);
    });

    test('tapping again while one is in flight does not queue a second',
        () async {
      final service = ScriptedCreditService(
        status: const CreditState(status: CreditReportStatus.notRequested),
      )..checkResult = available();
      final container = await containerWith(service);

      container.read(creditControllerProvider);
      await pumpEventQueue();

      final controller = container.read(creditControllerProvider.notifier);
      await Future.wait([controller.check(), controller.check()]);

      expect(service.checkCalls, 1);
    });
  });

  group('a failed check produces no information at all', () {
    Future<CreditScreenState> after(Object error, {CreditState? held}) async {
      final service = ScriptedCreditService(
        status: held ?? const CreditState(status: CreditReportStatus.notRequested),
      )..failCheck = error;
      final container = await containerWith(service);

      container.read(creditControllerProvider);
      await pumpEventQueue();
      await container.read(creditControllerProvider.notifier).check();

      return container.read(creditControllerProvider);
    }

    test('an unreachable bureau is not bad credit', () async {
      final state = await after(
        UpstreamUnavailableException('unreachable', reason: 'bureau_unavailable'),
      );

      expect(state.failure, CreditFailure.bureauUnavailable);
      expect(state.credit?.hasReport, isFalse);
      expect(state.credit?.profile, isNull);
    });

    test('a failure never overwrites a report already held', () async {
      final state = await after(
        UpstreamUnavailableException('unreachable'),
        held: available(),
      );

      // The report FynnEdge holds is unchanged: a failure is not new
      // information about the customer's credit.
      expect(state.credit?.profile?.score, 742);
      expect(state.failure, CreditFailure.bureauUnavailable);
    });

    test('missing consent is its own state, not a signed-out session',
        () async {
      final state = await after(
        PermissionRequiredException('needs consent', reason: 'consent_required'),
      );

      expect(state.failure, CreditFailure.consentRequired);
    });

    test('no bureau connected is its own state', () async {
      final state = await after(
        CapabilityUnavailableException('no bureau', reason: 'not_configured'),
      );

      expect(state.failure, CreditFailure.notConfigured);
    });

    test('too many checks is its own state', () async {
      final state = await after(RateLimitedException('slow down'));

      expect(state.failure, CreditFailure.tooManyChecks);
    });
  });

  // --- The distinction the module exists to protect ------------------------

  group('a bureau score is not a FynnScore', () {
    test('nothing converts one into the other', () {
      final profile = available().profile!;

      // CreditProfile offers no arithmetic beyond placing the score on its
      // own scale. If a future change adds a conversion, this list is where
      // it would have to be justified.
      expect(profile.positionOnScale, closeTo((742 - 300) / 600, 0.0001));
      expect(
        profile.positionOnScale,
        isNot(equals(profile.score / 100)),
        reason: 'a bureau score is not a percentage of anything',
      );
    });
  });
}
