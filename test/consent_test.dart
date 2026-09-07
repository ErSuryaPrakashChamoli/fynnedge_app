import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/mock/mock_consents.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/consent.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/consent_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/profile/consent_controller.dart';
import 'package:fynnedge/features/profile/privacy_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// A service that can be made to fail, wrapping the real mock one.
class FlakyConsentService implements ConsentService {
  FlakyConsentService([MockConsentService? inner])
    : _inner = inner ?? MockConsentService();

  final MockConsentService _inner;
  Object? failLoad;
  Object? failWrite;
  int loadCalls = 0;

  @override
  Future<ConsentState> getConsents() async {
    loadCalls++;
    if (failLoad != null) throw failLoad!;
    return _inner.getConsents();
  }

  @override
  Future<List<ConsentRecord>> getHistory() async {
    if (failLoad != null) throw failLoad!;
    return _inner.getHistory();
  }

  @override
  Future<ConsentState> grant(
    ConsentType type, {
    String source = 'privacy_screen',
  }) async {
    if (failWrite != null) throw failWrite!;
    return _inner.grant(type, source: source);
  }

  @override
  Future<ConsentState> withdraw(
    ConsentType type, {
    String source = 'privacy_screen',
  }) async {
    if (failWrite != null) throw failWrite!;
    return _inner.withdraw(type, source: source);
  }
}

Future<ProviderContainer> containerWith(ConsentService service) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      consentServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

void main() {
  setUpAll(initTestEnvironment);
  setUp(MockStore.instance.reset);

  // --- The catalogue -------------------------------------------------------

  group('catalogue', () {
    test('nothing is consented to on the customer\'s behalf', () async {
      final state = await MockConsentService().getConsents();

      for (final consent in state.consents) {
        expect(
          consent.isGranted,
          isFalse,
          reason: '${consent.type} was assumed',
        );
      }
      expect(state.outstandingRequired, [
        ConsentType.serviceTerms,
        ConsentType.privacyNotice,
      ]);
    });

    test('required and optional are distinguished', () async {
      final state = await MockConsentService().getConsents();

      expect(state.byType(ConsentType.serviceTerms)!.isRequired, isTrue);
      expect(state.byType(ConsentType.privacyNotice)!.isRequired, isTrue);
      expect(state.byType(ConsentType.aiMemory)!.isRequired, isFalse);
    });

    test('an unknown type from the server is never grantable', () {
      final item = ConsentItem.fromJson(const {
        'type': 'something_new',
        'label': 'Something new',
        'is_available': true,
      });

      expect(item.type, ConsentType.unknown);
    });
  });

  // --- No fake bureau consent ---------------------------------------------

  group('no consent for what FynnEdge cannot do', () {
    test('the bureau consent is not available', () async {
      final state = await MockConsentService().getConsents();
      final bureau = state.byType(ConsentType.creditBureauCheck)!;

      expect(bureau.isAvailable, isFalse);
      expect(bureau.isGranted, isFalse);
      expect(bureau.currentVersion, isNull);
      expect(bureau.unavailableReason, isNotNull);
    });

    test('granting an unavailable consent is refused', () async {
      final service = MockConsentService();

      for (final type in const [
        ConsentType.creditBureauCheck,
        ConsentType.lenderDataSharing,
        ConsentType.aiTraining,
        ConsentType.marketingMessages,
      ]) {
        await expectLater(
          service.grant(type),
          throwsA(isA<ApiException>()),
          reason: '$type must not be grantable',
        );
      }

      expect(MockStore.instance.consentHistory, isEmpty);
    });

    test(
      'no grantable consent mentions a capability that does not exist',
      () async {
        final state = await MockConsentService().getConsents();

        for (final consent in state.available) {
          final text = '${consent.label} ${consent.description}'.toLowerCase();

          for (final forbidden in const [
            'credit report',
            'credit check',
            'bureau',
            'cibil',
          ]) {
            expect(
              text,
              isNot(contains(forbidden)),
              reason: '${consent.type} refers to $forbidden',
            );
          }
        }
      },
    );
  });

  // --- Granting and withdrawing -------------------------------------------

  group('decisions', () {
    test('granting records type, version and source', () async {
      final service = MockConsentService();
      await service.grant(ConsentType.aiMemory, source: 'onboarding');

      final record = MockStore.instance.consentHistory.single;
      expect(record.type, ConsentType.aiMemory);
      expect(record.version, 'v1');
      expect(record.status, ConsentStatus.granted);
      expect(record.source, 'onboarding');
      expect(record.at, isNotNull);
    });

    test('granting twice records one decision', () async {
      final service = MockConsentService();

      await service.grant(ConsentType.aiMemory);
      await service.grant(ConsentType.aiMemory);
      await service.grant(ConsentType.aiMemory);

      expect(MockStore.instance.consentHistory, hasLength(1));
      expect(
        (await service.getConsents()).isGranted(ConsentType.aiMemory),
        isTrue,
      );
    });

    test('withdrawing appends rather than erasing', () async {
      final service = MockConsentService();
      await service.grant(ConsentType.aiMemory);
      final state = await service.withdraw(ConsentType.aiMemory);

      expect(state.isGranted(ConsentType.aiMemory), isFalse);
      expect(MockStore.instance.consentHistory, hasLength(2));
      // The grant is still on the record.
      expect(
        MockStore.instance.consentHistory.last.status,
        ConsentStatus.granted,
      );
    });

    test('a required consent cannot be withdrawn', () async {
      final service = MockConsentService();
      await service.grant(ConsentType.serviceTerms);

      await expectLater(
        service.withdraw(ConsentType.serviceTerms),
        throwsA(isA<ApiException>()),
      );

      expect(
        (await service.getConsents()).isGranted(ConsentType.serviceTerms),
        isTrue,
      );
    });

    test('withdrawing an optional consent leaves the service on', () async {
      final service = MockConsentService();
      await service.grant(ConsentType.serviceTerms);
      await service.grant(ConsentType.privacyNotice);
      await service.grant(ConsentType.aiMemory);

      final state = await service.withdraw(ConsentType.aiMemory);

      expect(state.isGranted(ConsentType.aiMemory), isFalse);
      expect(state.isGranted(ConsentType.serviceTerms), isTrue);
      expect(state.isGranted(ConsentType.privacyNotice), isTrue);
    });

    test('withdrawing something never granted is refused', () async {
      await expectLater(
        MockConsentService().withdraw(ConsentType.aiMemory),
        throwsA(isA<ApiException>()),
      );
    });

    test('history is newest first and keeps everything', () async {
      final service = MockConsentService();
      await service.grant(ConsentType.serviceTerms);
      await service.grant(ConsentType.aiMemory);
      await service.withdraw(ConsentType.aiMemory);

      final history = await service.getHistory();

      expect(history.map((r) => '${r.type.id}:${r.status.id}').toList(), [
        'ai_memory:withdrawn',
        'ai_memory:granted',
        'service_terms:granted',
      ]);
    });

    test('mock state survives within the session', () async {
      await MockConsentService().grant(ConsentType.aiMemory);

      // A second service instance, as a later screen would create.
      final later = await MockConsentService().getConsents();
      expect(later.isGranted(ConsentType.aiMemory), isTrue);
    });
  });

  // --- Serialization -------------------------------------------------------

  group('serialization', () {
    test('a state survives a round trip', () async {
      final service = MockConsentService();
      await service.grant(ConsentType.aiMemory);
      final original = await service.getConsents();

      final restored = ConsentState.fromJson(original.toJson());

      expect(restored.consents.length, original.consents.length);
      expect(restored.isGranted(ConsentType.aiMemory), isTrue);
      expect(restored.outstandingRequired, original.outstandingRequired);

      for (var i = 0; i < original.consents.length; i++) {
        expect(restored.consents[i].toJson(), original.consents[i].toJson());
      }
    });

    test('a missing field never reads as granted or available', () {
      final item = ConsentItem.fromJson(const {'type': 'ai_memory'});

      expect(item.isGranted, isFalse);
      expect(item.isAvailable, isFalse);
      expect(item.isRequired, isFalse);
      expect(item.needsReconfirmation, isFalse);
    });

    test('a history record round-trips', () async {
      final service = MockConsentService();
      await service.grant(ConsentType.aiMemory);

      final record = (await service.getHistory()).single;
      final restored = ConsentRecord.fromJson(record.toJson());

      expect(restored.type, record.type);
      expect(restored.version, record.version);
      expect(restored.status, record.status);
      expect(restored.source, record.source);
    });
  });

  // --- The controller ------------------------------------------------------

  group('controller', () {
    test('it loads the catalogue', () async {
      final container = await containerWith(MockConsentService());
      final controller = container.read(consentControllerProvider.notifier);

      await controller.load();
      final state = container.read(consentControllerProvider);

      expect(state.loading, isFalse);
      expect(state.state!.consents, isNotEmpty);
      expect(state.loadError, isNull);
    });

    test('a load failure keeps the error for a retry', () async {
      final service = FlakyConsentService()..failLoad = NetworkException();
      final container = await containerWith(service);
      final controller = container.read(consentControllerProvider.notifier);

      await controller.load();
      expect(container.read(consentControllerProvider).loadError, isNotNull);

      service.failLoad = null;
      await controller.load();

      final state = container.read(consentControllerProvider);
      expect(state.loadError, isNull);
      expect(state.state, isNotNull);
    });

    test(
      'a refused change leaves the switch where the server has it',
      () async {
        final service = FlakyConsentService();
        final container = await containerWith(service);
        final controller = container.read(consentControllerProvider.notifier);
        await controller.load();

        service.failWrite = NetworkException();
        expect(await controller.set(ConsentType.aiMemory, true), isFalse);

        final state = container.read(consentControllerProvider);
        expect(state.actionError, contains('Could not reach FynnEdge'));
        expect(state.state!.isGranted(ConsentType.aiMemory), isFalse);
        expect(MockStore.instance.consentHistory, isEmpty);
      },
    );

    test('an expired session surfaces as an error', () async {
      final service = FlakyConsentService()
        ..failWrite = UnauthorizedException();
      final container = await containerWith(service);
      final controller = container.read(consentControllerProvider.notifier);
      await controller.load();

      await controller.set(ConsentType.aiMemory, true);

      expect(
        container.read(consentControllerProvider).actionError,
        contains('sign in again'),
      );
    });

    test('granting then withdrawing moves the state both ways', () async {
      final container = await containerWith(MockConsentService());
      final controller = container.read(consentControllerProvider.notifier);
      await controller.load();

      expect(await controller.set(ConsentType.aiMemory, true), isTrue);
      expect(
        container
            .read(consentControllerProvider)
            .state!
            .isGranted(ConsentType.aiMemory),
        isTrue,
      );

      expect(await controller.set(ConsentType.aiMemory, false), isTrue);
      expect(
        container
            .read(consentControllerProvider)
            .state!
            .isGranted(ConsentType.aiMemory),
        isFalse,
      );
    });

    test('withdrawing a required consent is refused with a reason', () async {
      final container = await containerWith(MockConsentService());
      final controller = container.read(consentControllerProvider.notifier);
      await controller.load();
      await controller.set(ConsentType.serviceTerms, true);

      expect(await controller.set(ConsentType.serviceTerms, false), isFalse);

      final state = container.read(consentControllerProvider);
      expect(state.actionError, contains('cannot be switched off'));
      expect(state.state!.isGranted(ConsentType.serviceTerms), isTrue);
    });
  });

  // --- Mock and real offer the same thing ----------------------------------

  group('catalogue parity', () {
    final file = File('test/fixtures/consent_catalogue.json');

    test('the mock catalogue matches the one the API serves', () {
      if (!file.existsSync()) {
        fail(
          'test/fixtures/consent_catalogue.json is missing. Regenerate:\n'
          '  cd ../fynnedge-api && php artisan fynn:parity-fixture',
        );
      }

      final fixture =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final expected = (fixture['types'] as List).cast<Map<String, dynamic>>();
      final actual = MockConsents.catalogue();

      expect(
        actual.map((c) => c.type.id).toList(),
        expected.map((e) => e['type']).toList(),
        reason: 'the two catalogues list different consents',
      );

      for (var i = 0; i < expected.length; i++) {
        final want = expected[i];
        final got = actual[i];
        final where = want['type'];

        expect(got.label, want['label'], reason: where);
        expect(got.description, want['description'], reason: where);
        expect(got.isRequired, want['is_required'], reason: where);
        expect(got.isAvailable, want['is_available'], reason: where);
        expect(
          got.unavailableReason,
          want['unavailable_reason'],
          reason: where,
        );
        expect(got.currentVersion, want['current_version'], reason: where);
      }
    });

    test('the missing legal copy is flagged, not hidden', () {
      final fixture =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      // The note travels with the fixture so nobody mistakes these
      // descriptions for reviewed policy wording.
      expect(fixture['_legal_note'], contains('No privacy policy'));
    });
  });

  // --- The screen ----------------------------------------------------------

  group('screen', () {
    testWidgets('it shows required, optional and unavailable', (tester) async {
      await pumpScreen(
        tester,
        const PrivacyScreen(),
        size: const Size(420, 2400),
      );
      await settle(tester);

      expect(find.text('Using FynnEdge'), findsNWidgets(2)); // heading + tile
      expect(find.text('Optional'), findsOneWidget);
      expect(find.text('Not available yet'), findsOneWidget);
      expect(find.text('REQUIRED'), findsNWidgets(2));
      expect(find.text('NOT AVAILABLE'), findsNWidgets(6));

      // The bureau entry is visible but has no switch to turn on.
      expect(find.text('Credit information check'), findsOneWidget);
      expect(find.textContaining('no bureau connection'), findsOneWidget);
    });

    testWidgets('a switch is only offered where consent is possible', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const PrivacyScreen(),
        size: const Size(420, 2400),
      );
      await settle(tester);

      // Three grantable consents, three switches. The four unavailable ones
      // have none.
      expect(find.byType(Switch), findsNWidgets(3));
    });

    testWidgets('granting persists and shows when it was given', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const PrivacyScreen(),
        size: const Size(420, 2400),
      );
      await settle(tester);

      await tester.tap(find.byType(Switch).at(2));
      await settle(tester);

      expect(MockStore.instance.consentHistory, hasLength(1));
      expect(find.textContaining('On since'), findsOneWidget);
    });

    testWidgets('a load failure offers a retry', (tester) async {
      final service = FlakyConsentService()..failLoad = NetworkException();

      await pumpScreen(
        tester,
        const PrivacyScreen(),
        overrides: [consentServiceProvider.overrideWithValue(service)],
      );
      await settle(tester);

      expect(find.textContaining('Could not reach FynnEdge'), findsOneWidget);
      expect(find.textContaining('ApiException'), findsNothing);

      service.failLoad = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);

      expect(find.text('Not available yet'), findsOneWidget);
    });

    testWidgets('history shows every decision and no database ids', (
      tester,
    ) async {
      final service = MockConsentService();
      await service.grant(ConsentType.aiMemory);
      await service.withdraw(ConsentType.aiMemory);

      await pumpScreen(
        tester,
        const PrivacyScreen(),
        size: const Size(420, 2400),
      );
      await settle(tester);

      await tester.tap(find.text('Consent history'));
      await settle(tester);

      expect(find.text('Consent history'), findsWidgets);
      expect(find.textContaining('Granted · version v1'), findsOneWidget);
      expect(find.textContaining('Withdrawn · version v1'), findsOneWidget);
      expect(find.textContaining('from Privacy & Consent'), findsWidgets);
    });
  });
}
