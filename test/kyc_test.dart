import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/models/kyc.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/kyc_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/vault/kyc_controller.dart';
import 'package:fynnedge/features/vault/kyc_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// Identity verification on the customer's side.
///
/// NO LIVE KYC PROVIDER IS CONNECTED. Every value here is synthetic and no
/// real person, PAN, Aadhaar number or date of birth is involved.
class ScriptedKycService implements KycService {
  ScriptedKycService(this.state);

  KycVerification state;
  Object? failVerify;
  Object? failResolve;

  int statusCalls = 0;
  int verifyCalls = 0;
  int resolveCalls = 0;

  String? lastField;
  ResolutionDecision? lastDecision;
  bool lastForce = false;

  @override
  Future<KycVerification> statusFor(String documentId) async {
    statusCalls++;
    return state;
  }

  @override
  Future<KycVerification> verify(String documentId, {bool force = false}) async {
    verifyCalls++;
    lastForce = force;
    if (failVerify != null) throw failVerify!;
    return state;
  }

  @override
  Future<KycVerification> resolve(
    String documentId, {
    required String field,
    required ResolutionDecision decision,
  }) async {
    resolveCalls++;
    lastField = field;
    lastDecision = decision;
    if (failResolve != null) throw failResolve!;
    return state;
  }
}

KycVerification result({
  VerificationStatus status = VerificationStatus.verified,
  String documentResult = 'passed',
  String identityResult = 'passed',
  bool mismatch = false,
  bool isStale = false,
}) => KycVerification.fromJson({
  'document_id': 'doc_1',
  'verification_id': 'kyc_1',
  'status': status.id,
  'is_supported': true,
  'is_sample': true,
  'is_stale': isStale,
  'verification_type': 'identity_document',
  'method': 'The verification service ran its own checks on the document.',
  'document_result': documentResult,
  'identity_result': identityResult,
  'masked_reference': 'XXXXXX000A',
  'expires_at': null,
  'field_matches': [
    mismatch
        ? {
            'field': 'name',
            'label': 'Name',
            'status': 'mismatched',
            'profile_value': 'Sample Customer',
            'verified_value': 'Sample Customer Verma',
          }
        : {'field': 'name', 'label': 'Name', 'status': 'matched'},
    {
      'field': 'date_of_birth',
      'label': 'Date of birth',
      'status': 'unable_to_compare',
      'reason': 'FynnEdge does not hold your date of birth.',
    },
  ],
  'disclaimer': 'A verification result says what a verification service '
      'established about a document. It is not a lending decision, it is not '
      'approval, and it does not change anything on your profile.',
});

Future<ProviderContainer> containerWith(KycService service) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      kycServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

void main() {
  setUpAll(initTestEnvironment);

  // --- Reading a result ----------------------------------------------------

  group('the server is authoritative about what was established', () {
    test('the two findings arrive apart', () {
      final verification = result(
        status: VerificationStatus.needsReview,
        identityResult: 'failed',
        mismatch: true,
      );

      // A document can pass its own checks while naming somebody else.
      expect(verification.documentResult, CheckOutcome.passed);
      expect(verification.identityResult, CheckOutcome.failed);
      expect(verification.differences, hasLength(1));
    });

    test('an unknown status is never taken for a pass', () {
      final verification = KycVerification.fromJson(const {
        'document_id': '1',
        'status': 'identity_confirmed_by_our_ai',
      });

      expect(verification.status, VerificationStatus.unavailable);
      expect(verification.status.hasResult, isFalse);
      expect(verification.canVerify, isFalse);
    });

    test('an unknown outcome is null rather than passed', () {
      final verification = KycVerification.fromJson(const {
        'document_id': '1',
        'status': 'verified',
        'document_result': 'probably_fine',
      });

      expect(verification.documentResult, isNull);
    });

    test('null and empty field matches are different answers', () {
      expect(
        KycVerification.fromJson(const {
          'document_id': '1',
          'status': 'not_started',
        }).fieldMatches,
        isNull,
      );

      expect(
        KycVerification.fromJson(const {
          'document_id': '1',
          'status': 'verified',
          'field_matches': [],
        }).fieldMatches,
        isEmpty,
      );
    });

    test('a matched field carries no values', () {
      final name = result().fieldMatches!.first;

      expect(name.status, MatchStatus.matched);
      expect(name.profileValue, isNull);
      expect(name.verifiedValue, isNull);
      expect(name.isDifference, isFalse);
    });

    test('unable to compare is not a mismatch', () {
      final dob = result().fieldMatches!.last;

      expect(dob.status, MatchStatus.unableToCompare);
      expect(dob.isDifference, isFalse);
      expect(result().differences, isEmpty);
    });

    test('no expiry is invented', () {
      expect(result().expiresAt, isNull);
    });
  });

  // --- Mock mode -----------------------------------------------------------

  group('mock mode has no verification service and says so', () {
    test('the status is unavailable, never not_verified', () async {
      final verification = await const MockKycService().statusFor('doc_1');

      expect(verification.status, VerificationStatus.unavailable);
      expect(verification.status, isNot(VerificationStatus.notVerified));
      expect(verification.fieldMatches, isNull);
      expect(verification.message, contains('not available yet'));
    });

    test('a check invents no pass', () async {
      final verification = await const MockKycService().verify('doc_1');

      expect(verification.status, VerificationStatus.unavailable);
      expect(verification.isSample, isFalse);
      expect(verification.documentResult, isNull);
    });

    test('resolving refuses rather than pretending to record one', () async {
      await expectLater(
        const MockKycService().resolve(
          'doc_1',
          field: 'name',
          decision: ResolutionDecision.updateProfile,
        ),
        throwsA(isA<CapabilityUnavailableException>()),
      );
    });
  });

  // --- Nothing is sent unasked ---------------------------------------------

  group('a document is sent only when the customer asks', () {
    test('opening the screen reads state and sends nothing', () async {
      final service = ScriptedKycService(
        result(status: VerificationStatus.notStarted),
      );
      final container = await containerWith(service);

      container.read(kycControllerProvider('doc_1'));
      await pumpEventQueue();

      expect(service.statusCalls, 1);
      expect(
        service.verifyCalls,
        0,
        reason: 'opening a screen must never send a document anywhere',
      );
    });

    test('a tap sends it exactly once', () async {
      final service = ScriptedKycService(
        result(status: VerificationStatus.notStarted),
      );
      final container = await containerWith(service);

      container.read(kycControllerProvider('doc_1'));
      await pumpEventQueue();

      final controller = container.read(kycControllerProvider('doc_1').notifier);
      await Future.wait([controller.verify(), controller.verify()]);

      expect(service.verifyCalls, 1);
    });
  });

  // --- Failures conclude nothing -------------------------------------------

  group('a failed check is never a finding about the customer', () {
    Future<KycScreenState> after(Object error) async {
      final service = ScriptedKycService(
        result(status: VerificationStatus.notStarted),
      )..failVerify = error;
      final container = await containerWith(service);

      container.read(kycControllerProvider('doc_1'));
      await pumpEventQueue();
      await container.read(kycControllerProvider('doc_1').notifier).verify();

      return container.read(kycControllerProvider('doc_1'));
    }

    test('an unreachable service is its own state', () async {
      final state = await after(UpstreamUnavailableException('down'));

      expect(state.failure, KycFailure.providerUnavailable);
      expect(state.verification?.status, isNot(VerificationStatus.notVerified));
    });

    test('missing consent is its own state, not a signed-out session',
        () async {
      expect(
        (await after(PermissionRequiredException(
          'needs consent',
          reason: 'consent_required',
        ))).failure,
        KycFailure.consentRequired,
      );
    });

    test('an unverifiable document type is distinct from no provider',
        () async {
      expect(
        (await after(CapabilityUnavailableException(
          'not checked',
          reason: 'document_type_not_verifiable',
        ))).failure,
        KycFailure.unsupportedDocument,
      );

      expect(
        (await after(CapabilityUnavailableException(
          'no provider',
          reason: 'verification_not_configured',
        ))).failure,
        KycFailure.notConfigured,
      );
    });

    test('too many checks is its own state', () async {
      expect(
        (await after(RateLimitedException('slow down'))).failure,
        KycFailure.tooManyChecks,
      );
    });
  });

  // --- The customer decides ------------------------------------------------

  group('a difference is the customer\'s to resolve', () {
    test('keeping the profile sends that decision', () async {
      final service = ScriptedKycService(
        result(status: VerificationStatus.needsReview, mismatch: true),
      );
      final container = await containerWith(service);

      container.read(kycControllerProvider('doc_1'));
      await pumpEventQueue();

      await container
          .read(kycControllerProvider('doc_1').notifier)
          .keepProfile('name');

      expect(service.lastDecision, ResolutionDecision.keepProfile);
      expect(service.lastField, 'name');
    });

    test('updating the profile is a separate, explicit decision', () async {
      final service = ScriptedKycService(
        result(status: VerificationStatus.needsReview, mismatch: true),
      );
      final container = await containerWith(service);

      container.read(kycControllerProvider('doc_1'));
      await pumpEventQueue();

      await container
          .read(kycControllerProvider('doc_1').notifier)
          .updateProfile('name');

      expect(service.lastDecision, ResolutionDecision.updateProfile);
    });

    test('a second decision while one is in flight is ignored', () async {
      final service = ScriptedKycService(
        result(status: VerificationStatus.needsReview, mismatch: true),
      );
      final container = await containerWith(service);

      container.read(kycControllerProvider('doc_1'));
      await pumpEventQueue();

      final controller = container.read(kycControllerProvider('doc_1').notifier);
      await Future.wait([
        controller.updateProfile('name'),
        controller.updateProfile('name'),
      ]);

      expect(service.resolveCalls, 1);
    });
  });

  // --- What the screen says -------------------------------------------------

  group('the screen is precise about what was established', () {
    Future<void> pumpWith(WidgetTester tester, KycVerification verification) async {
      await pumpScreen(
        tester,
        const KycScreen(documentId: 'doc_1'),
        overrides: [
          kycServiceProvider.overrideWithValue(ScriptedKycService(verification)),
        ],
      );
      await settle(tester);
    }

    testWidgets('a pass names the method and the two findings',
        (tester) async {
      await pumpWith(tester, result());

      expect(find.text('Identity verification passed'), findsOneWidget);
      expect(find.text('What was checked'), findsOneWidget);
      expect(find.text('The document itself'), findsOneWidget);
      expect(find.text('The details on it'), findsOneWidget);

      // A synthetic check is labelled as one.
      expect(find.text('Sample check'), findsOneWidget);

      // Only a masked tail is ever shown.
      expect(find.text('XXXXXX000A'), findsOneWidget);

      await golden(tester, KycScreen, 'kyc/verified');
    });

    testWidgets('a difference is shown with both sides and neither chosen',
        (tester) async {
      await pumpWith(
        tester,
        result(
          status: VerificationStatus.needsReview,
          identityResult: 'failed',
          mismatch: true,
        ),
      );

      expect(find.text('We found a difference'), findsOneWidget);
      expect(find.text('Sample Customer'), findsOneWidget);
      expect(find.text('Sample Customer Verma'), findsOneWidget);
      expect(find.text('Keep what is on my profile'), findsOneWidget);
      expect(find.text('Update my profile to match'), findsOneWidget);
      expect(
        find.textContaining('FynnEdge has not changed your profile'),
        findsOneWidget,
      );

      await golden(tester, KycScreen, 'kyc/mismatch');
    });

    testWidgets('a failed document check names no fraud', (tester) async {
      await pumpWith(
        tester,
        result(
          status: VerificationStatus.notVerified,
          documentResult: 'failed',
          identityResult: 'not_performed',
        ),
      );

      expect(find.textContaining("We couldn't establish this"), findsOneWidget);
      expect(
        find.textContaining('a finding about this document, not about you'),
        findsOneWidget,
      );

      await golden(tester, KycScreen, 'kyc/not_verified');
    });

    testWidgets('no provider says unavailable, never not verified',
        (tester) async {
      await pumpWith(
        tester,
        KycVerification.fromJson(const {
          'document_id': 'doc_1',
          'status': 'unavailable',
          'reason': 'verification_not_configured',
          'message': 'Identity verification is not available yet.',
        }),
      );

      expect(find.text("Identity checks aren't available yet"), findsOneWidget);

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ')
          .toLowerCase();

      // The sentence a customer must never see when nothing was checked.
      expect(text.contains('could not be established'), isFalse);
      expect(text.contains('did not pass'), isFalse);

      await golden(tester, KycScreen, 'kyc/unavailable');
    });

    testWidgets('consent required explains it is a separate permission',
        (tester) async {
      await pumpWith(
        tester,
        KycVerification.fromJson(const {
          'document_id': 'doc_1',
          'status': 'consent_required',
          'is_supported': true,
        }),
      );

      expect(find.text('Your permission comes first'), findsOneWidget);
      expect(
        find.textContaining('separate permission from letting FynnEdge read'),
        findsOneWidget,
      );

      await golden(tester, KycScreen, 'kyc/consent_required');
    });

    testWidgets('no state claims approval, proof or a genuine person',
        (tester) async {
      for (final verification in [
        result(),
        result(status: VerificationStatus.needsReview, mismatch: true),
        result(
          status: VerificationStatus.notVerified,
          documentResult: 'failed',
          identityResult: 'not_performed',
        ),
        KycVerification.fromJson(const {
          'document_id': 'doc_1',
          'status': 'unavailable',
          'reason': 'verification_not_configured',
        }),
        KycVerification.fromJson(const {
          'document_id': 'doc_1',
          'status': 'failed',
          'is_supported': true,
        }),
      ]) {
        await pumpWith(tester, verification);

        final text = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join(' ')
            .toLowerCase();

        for (final claim in [
          // Verification is not a lending decision.
          'approved', 'pre-approved', 'you qualify', 'eligible',
          // A document signal is not a fraud determination.
          'fraud', 'fraudulent', 'forged', 'fake',
          // A check establishes a criterion, not a person.
          'legitimate person', 'genuine person', 'proves', 'proof of identity',
          'guaranteed genuine',
          // FynnEdge does not do Aadhaar.
          'aadhaar',
        ]) {
          expect(
            text.contains(claim),
            isFalse,
            reason: '${verification.status.id} said: $claim',
          );
        }
      }
    });

    testWidgets('no progress percentage is invented while checking',
        (tester) async {
      await pumpWith(
        tester,
        KycVerification.fromJson(const {
          'document_id': 'doc_1',
          'status': 'processing',
          'is_supported': true,
        }),
      );

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');

      expect(text, contains('Checking your document'));
      expect(text.contains('%'), isFalse);
    });
  });
}
