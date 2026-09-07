import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/application.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/application_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/applications/application_controller.dart';
import 'package:fynnedge/features/applications/application_detail_screen.dart';
import 'package:fynnedge/features/applications/application_review_screen.dart';
import 'package:fynnedge/features/applications/applications_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fynnedge/data/models/match.dart';
import 'package:fynnedge/features/loans/loan_controller.dart';
import 'package:fynnedge/features/profile/profile_controller.dart';

import 'support/harness.dart';

/// The match a customer would have tapped, from the same providers the app
/// uses.
Future<ProductMatch> matchFor(ProviderContainer container, String id) async =>
    (await container.read(fynnMatchProvider.future)).byId(id)!;

/// A service that records what it was asked and can be made to fail.
class RecordingApplicationService implements ApplicationService {
  RecordingApplicationService([MockApplicationService? inner])
    : _inner = inner ?? MockApplicationService();

  final MockApplicationService _inner;

  int createCalls = 0;
  int submitCalls = 0;
  final List<String> keys = [];
  ApplicationDraft? lastDraft;
  Object? failCreate;
  Object? failSubmit;

  @override
  Future<List<LoanApplication>> getApplications() => _inner.getApplications();

  @override
  Future<LoanApplication> getApplication(String id) =>
      _inner.getApplication(id);

  @override
  Future<LoanApplication> create(
    ApplicationDraft draft, {
    required String idempotencyKey,
  }) async {
    createCalls++;
    keys.add(idempotencyKey);
    lastDraft = draft;
    if (failCreate != null) throw failCreate!;
    return _inner.create(draft, idempotencyKey: idempotencyKey);
  }

  @override
  Future<LoanApplication> update(
    String id, {
    double? amount,
    int? tenureMonths,
  }) => _inner.update(id, amount: amount, tenureMonths: tenureMonths);

  @override
  Future<LoanApplication> submit(String id) async {
    submitCalls++;
    if (failSubmit != null) throw failSubmit!;
    return _inner.submit(id);
  }

  @override
  Future<LoanApplication> cancel(String id) => _inner.cancel(id);
}

Future<ProviderContainer> appContainer(ApplicationService service) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      applicationServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

void main() {
  setUpAll(initTestEnvironment);
  setUp(MockStore.instance.reset);

  const draft = ApplicationDraft(
    productId: 'prod_bl_b',
    amount: 1000000,
    tenureMonths: 60,
  );

  // --- The lifecycle ------------------------------------------------------

  group('lifecycle', () {
    test('a new application starts, and starts nowhere else', () async {
      final application = await MockApplicationService().create(
        draft,
        idempotencyKey: 'k1',
      );

      expect(application.status, ApplicationStatus.started);
      expect(application.canSubmit, isTrue);
      expect(application.isEditable, isTrue);
      // Nothing has been sent, and the record says so.
      expect(application.isSimulated, isFalse);
      expect(application.submittedAt, isNull);
      expect(application.acknowledgedAt, isNull);
      expect(application.gateway, isNull);
      expect(application.events.single.source, EventSource.fynnedge);
    });

    test('it is priced by the engine, at what the customer chose', () async {
      final application = await MockApplicationService().create(
        draft,
        idempotencyKey: 'k1',
      );

      expect(application.amount, 1000000);
      expect(application.tenureMonths, 60);
      expect(application.productId, 'prod_bl_b');
      expect(application.emi, 22447.11);
      expect(application.projectedEmiRatio, 42.45);
      expect(application.processingFee, 10000);
    });

    test(
      'submission records a simulated acknowledgement, and no more',
      () async {
        final service = MockApplicationService();
        final started = await service.create(draft, idempotencyKey: 'k1');
        final submitted = await service.submit(started.id);

        expect(submitted.status, ApplicationStatus.submitted);
        expect(submitted.submittedAt, isNotNull);
        expect(submitted.acknowledgedAt, isNotNull);
        expect(submitted.isSimulated, isTrue);
        expect(submitted.gateway, 'mock');
        expect(submitted.providerReference, isNull);

        // Never a provider decision, and never a provider's voice.
        expect(submitted.status.isProviderDecision, isFalse);
        expect(submitted.hasProviderEvents, isFalse);
        expect(submitted.events.last.isSimulated, isTrue);
        expect(submitted.events.last.detail, contains('No provider'));
      },
    );

    test('submitting twice submits once', () async {
      final service = MockApplicationService();
      final started = await service.create(draft, idempotencyKey: 'k1');

      final first = await service.submit(started.id);
      final second = await service.submit(started.id);

      expect(second.submittedAt, first.submittedAt);
      expect(second.events.where((e) => e.label == 'Submitted'), hasLength(1));
    });

    test('the same key creates one application', () async {
      final service = MockApplicationService();

      final first = await service.create(draft, idempotencyKey: 'same');
      final second = await service.create(draft, idempotencyKey: 'same');

      expect(second.id, first.id);
      expect(MockStore.instance.applications, hasLength(1));
    });

    test('a submitted application can no longer be edited', () async {
      final service = MockApplicationService();
      final started = await service.create(draft, idempotencyKey: 'k1');
      await service.submit(started.id);

      await expectLater(
        service.update(started.id, amount: 500000),
        throwsA(isA<ApiException>()),
      );
      expect((await service.getApplication(started.id)).amount, 1000000);
    });

    test('editing a draft reprices it', () async {
      final service = MockApplicationService();
      final started = await service.create(draft, idempotencyKey: 'k1');

      final updated = await service.update(
        started.id,
        amount: 2000000,
        tenureMonths: 84,
      );

      expect(updated.amount, 2000000);
      expect(updated.tenureMonths, 84);
      expect(updated.emi, 35734.72);
    });

    test('cancelling closes it', () async {
      final service = MockApplicationService();
      final started = await service.create(draft, idempotencyKey: 'k1');

      final cancelled = await service.cancel(started.id);

      expect(cancelled.status, ApplicationStatus.cancelled);
      expect(cancelled.canSubmit, isFalse);
      expect(cancelled.canCancel, isFalse);
      expect(cancelled.status.isTerminal, isTrue);

      await expectLater(
        service.submit(started.id),
        throwsA(isA<ApiException>()),
      );
    });

    test('a missing application is a 404, not an empty one', () async {
      await expectLater(
        MockApplicationService().getApplication('app_nope'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('the list is newest first', () async {
      final service = MockApplicationService();
      final first = await service.create(draft, idempotencyKey: 'k1');
      final second = await service.create(draft, idempotencyKey: 'k2');

      expect((await service.getApplications()).map((a) => a.id), [
        second.id,
        first.id,
      ]);
    });
  });

  // --- Exact preservation --------------------------------------------------

  group('the figures are the customer\'s', () {
    test('an awkward amount and tenure survive the whole journey', () async {
      final service = MockApplicationService();

      final started = await service.create(
        const ApplicationDraft(
          productId: 'prod_bl_b',
          amount: 1234567.89,
          // A term this product does not offer: recorded as asked, not
          // quietly corrected.
          tenureMonths: 7,
        ),
        idempotencyKey: 'k1',
      );
      final submitted = await service.submit(started.id);
      final fetched = await service.getApplication(started.id);
      final listed = (await service.getApplications()).single;

      for (final application in [started, submitted, fetched, listed]) {
        expect(application.amount, 1234567.89);
        expect(application.tenureMonths, 7);
        expect(application.productId, 'prod_bl_b');
      }
    });

    test(
      'the product stays the same product from match to application',
      () async {
        final service = MockApplicationService();
        final application = await service.create(
          const ApplicationDraft(
            productId: 'prod_pl_a',
            amount: 800000,
            tenureMonths: 48,
          ),
          idempotencyKey: 'k1',
        );

        expect(application.productId, 'prod_pl_a');
        expect(application.lender, 'Meridian Bank');
        expect(application.productName, 'Personal Loan A');
        expect(application.interestRate, 11.5);
      },
    );

    test('an unknown product cannot be applied for', () async {
      await expectLater(
        MockApplicationService().create(
          const ApplicationDraft(
            productId: 'prod_nope',
            amount: 100000,
            tenureMonths: 12,
          ),
          idempotencyKey: 'k1',
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  // --- The flow controller -------------------------------------------------

  group('review and submit', () {
    test('submission is refused until the acknowledgement is made', () async {
      final service = RecordingApplicationService();
      final container = await appContainer(service);
      final controller = container.read(applicationFlowProvider.notifier);

      final match = await matchFor(container, 'prod_bl_b');
      await controller.start(match);

      expect(await controller.submit(), isFalse);
      expect(service.submitCalls, 0);

      controller.setAcknowledged(true);
      expect(await controller.submit(), isTrue);
      expect(service.submitCalls, 1);
    });

    test('a repeated submit uses one key and one application', () async {
      final service = RecordingApplicationService();
      final container = await appContainer(service);
      final controller = container.read(applicationFlowProvider.notifier);
      final match = await matchFor(container, 'prod_bl_b');

      controller.setAcknowledged(true);

      // Five taps in a row, as fast as they can be made.
      await Future.wait([for (var i = 0; i < 5; i++) controller.start(match)]);
      await Future.wait([for (var i = 0; i < 5; i++) controller.submit()]);

      expect(service.keys.toSet(), hasLength(1));
      expect(MockStore.instance.applications, hasLength(1));
      expect(
        MockStore.instance.applications.single.events.where(
          (e) => e.label == 'Submitted',
        ),
        hasLength(1),
      );
    });

    test('a failed submission never reads as success', () async {
      final service = RecordingApplicationService()
        ..failSubmit = NetworkException();
      final container = await appContainer(service);
      final controller = container.read(applicationFlowProvider.notifier);
      final match = await matchFor(container, 'prod_bl_b');

      await controller.start(match);
      controller.setAcknowledged(true);

      expect(await controller.submit(), isFalse);

      final state = container.read(applicationFlowProvider);
      expect(state.isSubmitted, isFalse);
      expect(state.error, contains('Could not reach FynnEdge'));
      // The application is untouched: still a draft, still submittable.
      expect(state.application!.status, ApplicationStatus.started);
      expect(state.busy, isFalse);
    });

    test('a failed create surfaces and submits nothing', () async {
      final service = RecordingApplicationService()
        ..failCreate = ApiException('That product is no longer available.');
      final container = await appContainer(service);
      final controller = container.read(applicationFlowProvider.notifier);
      final match = await matchFor(container, 'prod_bl_b');

      expect(await controller.start(match), isNull);
      expect(
        container.read(applicationFlowProvider).error,
        contains('no longer available'),
      );
      expect(await controller.submit(), isFalse);
      expect(service.submitCalls, 0);
    });

    test('an expired session surfaces as an error', () async {
      final service = RecordingApplicationService()
        ..failCreate = UnauthorizedException();
      final container = await appContainer(service);
      final controller = container.read(applicationFlowProvider.notifier);

      await controller.start(await matchFor(container, 'prod_bl_b'));

      expect(
        container.read(applicationFlowProvider).error,
        contains('sign in again'),
      );
    });

    test('submitting refreshes the list and Home, and nothing else', () async {
      final service = RecordingApplicationService();
      final container = await appContainer(service);
      final controller = container.read(applicationFlowProvider.notifier);

      // Read the score and the matches first, so a rebuild would be visible.
      final scoreBefore = await container.read(fynnScoreProvider.future);

      expect(container.read(applicationsProvider.future), completes);
      await container.read(applicationsProvider.future);

      final match = await matchFor(container, 'prod_bl_b');
      await controller.start(match);
      controller.setAcknowledged(true);
      await controller.submit();

      // The list is rebuilt and now carries the application.
      final applications = await container.read(applicationsProvider.future);
      expect(applications, hasLength(1));
      expect(applications.single.status, ApplicationStatus.submitted);

      // FynnScore is untouched: an application does not change the
      // customer's financial profile.
      final scoreAfter = await container.read(fynnScoreProvider.future);
      expect(scoreAfter.score, scoreBefore.score);
      expect(scoreAfter.hasScore, scoreBefore.hasScore);
    });
  });

  // --- Screens -------------------------------------------------------------

  group('screens', () {
    testWidgets('the list is empty until the customer applies', (tester) async {
      await pumpScreen(tester, const ApplicationsScreen());
      await settle(tester);

      expect(find.text('Nothing in progress'), findsOneWidget);
      expect(find.text('Explore options'), findsOneWidget);
    });

    testWidgets('an application the customer started is listed', (
      tester,
    ) async {
      await seedApplication();

      await pumpScreen(tester, const ApplicationsScreen());
      await settle(tester);

      expect(find.text('Nothing in progress'), findsNothing);
      expect(find.text('SME Term Loan'), findsOneWidget);
      expect(find.textContaining('FE-'), findsOneWidget);
    });

    testWidgets('a load failure offers a retry', (tester) async {
      final service = _FailingService();

      await pumpScreen(
        tester,
        const ApplicationsScreen(),
        overrides: [applicationServiceProvider.overrideWithValue(service)],
      );
      await settle(tester);

      expect(find.textContaining('Could not reach FynnEdge'), findsOneWidget);
      expect(find.textContaining('ApiException'), findsNothing);

      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(service.calls, 2);
    });

    testWidgets('an unknown application says so rather than blanking', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ApplicationDetailScreen(id: 'app_missing'),
      );
      await settle(tester);

      expect(find.textContaining('could not be found'), findsOneWidget);
    });

    testWidgets('review shows the product, the ask and the cost', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ApplicationReviewScreen(productId: 'prod_bl_b'),
        size: const Size(420, 2000),
      );
      await settle(tester);

      expect(find.text('United Credit Bank'), findsOneWidget);
      expect(find.text('Good Match'), findsOneWidget);
      expect(find.text('₹10,00,000'), findsOneWidget);
      expect(find.text('₹22,447'), findsOneWidget);
      expect(find.text('ESTIMATE'), findsOneWidget);
      expect(find.text('12.40%'), findsOneWidget);
      // And what submitting does — and does not — do.
      expect(find.textContaining('no credit check'), findsOneWidget);
    });

    testWidgets('submit is disabled until both statements are confirmed', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ApplicationReviewScreen(productId: 'prod_bl_b'),
        size: const Size(420, 2000),
      );
      await settle(tester);

      bool submitEnabled() => tester
          .widget<Semantics>(
            find
                .ancestor(
                  of: find.text('Submit application'),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .enabled!;

      expect(submitEnabled(), isFalse);

      await tester.tap(find.textContaining('accurate to the best'));
      await settle(tester);

      expect(submitEnabled(), isTrue);
    });

    testWidgets('submitting shows the reference and what actually happened', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const ApplicationReviewScreen(productId: 'prod_bl_b'),
        size: const Size(420, 2000),
      );
      await settle(tester);

      await tester.tap(find.textContaining('accurate to the best'));
      await settle(tester);
      await tester.tap(find.text('Submit application'));
      await settle(tester);

      expect(find.text('Application recorded'), findsOneWidget);
      expect(find.textContaining('FE-'), findsOneWidget);
      expect(
        find.textContaining('no provider has received it'),
        findsOneWidget,
      );
      expect(MockStore.instance.applications, hasLength(1));
    });

    testWidgets('the detail screen shows the real application', (tester) async {
      final application = await tester.runAsync(
        () => seedApplication(submit: true),
      );

      await pumpScreen(
        tester,
        ApplicationDetailScreen(id: application!.id),
        size: const Size(420, 1400),
      );
      await settle(tester);

      expect(find.text(application.reference), findsWidgets);
      // The banner now shows the server's customer-status label, which says
      // what is actually true: complete in FynnEdge, and sent nowhere.
      expect(find.text('READY IN FYNNEDGE'), findsOneWidget);
      expect(find.text('₹10,00,000'), findsOneWidget);
      expect(find.text('SIMULATED'), findsOneWidget);
      expect(find.textContaining('sent to no provider'), findsOneWidget);
      // History, not a forecast of steps that have not happened.
      expect(find.text('Started'), findsWidgets);
      expect(find.text('Submitted'), findsWidgets);
      expect(find.textContaining('Decision'), findsNothing);
      expect(find.textContaining('Expected within'), findsNothing);
    });
  });
}

class _FailingService implements ApplicationService {
  int calls = 0;

  @override
  Future<List<LoanApplication>> getApplications() async {
    calls++;
    throw NetworkException();
  }

  @override
  Future<LoanApplication> getApplication(String id) async =>
      throw NetworkException();

  @override
  Future<LoanApplication> create(
    ApplicationDraft draft, {
    required String idempotencyKey,
  }) async => throw NetworkException();

  @override
  Future<LoanApplication> update(
    String id, {
    double? amount,
    int? tenureMonths,
  }) async => throw NetworkException();

  @override
  Future<LoanApplication> submit(String id) async => throw NetworkException();

  @override
  Future<LoanApplication> cancel(String id) async => throw NetworkException();
}
