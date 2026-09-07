import 'package:flutter/material.dart';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/data/models/application.dart';
import 'package:fynnedge/data/services/application_service.dart';
import 'package:fynnedge/features/applications/application_detail_screen.dart';

import 'support/harness.dart';

/// Serves exactly the applications a test hands it, so a screen can be shown
/// in a state only a provider event could produce.
class ScriptedApplicationService implements ApplicationService {
  ScriptedApplicationService(this.applications);

  final List<LoanApplication> applications;

  @override
  Future<List<LoanApplication>> getApplications() async => applications;

  @override
  Future<LoanApplication> getApplication(String id) async =>
      applications.firstWhere((a) => a.id == id);

  @override
  Future<LoanApplication> create(
    ApplicationDraft draft, {
    required String idempotencyKey,
  }) async => applications.first;

  @override
  Future<LoanApplication> update(
    String id, {
    double? amount,
    int? tenureMonths,
  }) async => applications.first;

  @override
  Future<LoanApplication> submit(String id) async => applications.first;

  @override
  Future<LoanApplication> cancel(String id) async => applications.first;
}

List<Override> applicationOverrides(List<LoanApplication> applications) => [
  applicationServiceProvider.overrideWithValue(
    ScriptedApplicationService(applications),
  ),
];

/// What the customer is told about where their application stands.
///
/// NO LIVE PROVIDER EVENT SOURCE IS CONNECTED. Every provider-derived state
/// below is a fixture, and none of it may read as a real lender's word
/// unless the server said it came from one.
LoanApplication built({
  required String code,
  required String label,
  required String description,
  ApplicationStatus status = ApplicationStatus.submitted,
  bool isSimulated = false,
  List<ApplicationEvent> events = const [],
}) => LoanApplication.fromJson({
  'id': 'app_1',
  'reference': 'FE-2026-000123',
  'product_id': 'prod_bl_b',
  'product_name': 'SME Term Loan',
  'lender': 'United Credit Bank',
  'product_category': 'business',
  'amount': 1000000,
  'tenure_months': 60,
  'interest_rate': 12.4,
  'emi': 22447,
  'total_interest': 356827,
  'total_payable': 1356827,
  'processing_fee': 15000,
  'match_category': 'strong_match',
  'status': status.id,
  'status_label': status.label,
  'customer_status': {
    'code': code,
    'label': label,
    'description': description,
  },
  'next_action': '',
  'can_submit': false,
  'can_cancel': true,
  'is_editable': false,
  'is_simulated': isSimulated,
  'created_at': '2026-09-05T10:00:00+05:30',
  'events': events.map((e) => e.toJson()).toList(),
});

void main() {
  setUpAll(initTestEnvironment);

  // --- The model carries the server's answer -------------------------------

  group('the server owns the sentence', () {
    test('it is parsed, not derived', () {
      final app = built(
        code: 'under_review',
        label: 'Application under review',
        description: 'The provider has told us your application is being '
            'reviewed.',
      );

      expect(app.customerStatus.code, 'under_review');
      expect(app.customerStatus.label, 'Application under review');
      expect(app.customerStatus.isFromProvider, isTrue);
    });

    test('an unconfirmed submission is recognised and is not a failure', () {
      final app = built(
        code: 'submission_unconfirmed',
        label: 'Submission status needs confirmation',
        description: 'We could not confirm whether the provider received '
            'your application.',
      );

      expect(app.customerStatus.isUnconfirmed, isTrue);

      // It is not a provider having said anything: FynnEdge simply does
      // not know.
      expect(app.customerStatus.isFromProvider, isFalse);
    });

    test('a missing customer status falls back rather than inventing one', () {
      final app = LoanApplication.fromJson(const {
        'id': '1',
        'reference': 'FE-2026-000001',
        'product_id': 'p',
        'product_name': 'p',
        'lender': 'l',
        'amount': 1,
        'tenure_months': 1,
        'status': 'started',
        'created_at': '2026-09-05T10:00:00+05:30',
      });

      expect(app.customerStatus.code, 'started');
      expect(app.customerStatus.isFromProvider, isFalse);
    });

    test('a status this build does not know is not treated as a provider one',
        () {
      final app = built(
        code: 'bank_said_yes',
        label: 'Something',
        description: 'Something.',
      );

      expect(app.customerStatus.isFromProvider, isFalse);
    });
  });

  // --- What the screen shows -----------------------------------------------

  group('application detail shows the server\'s words', () {
    Future<void> pumpWith(
      WidgetTester tester,
      LoanApplication app, {
      Size size = const Size(390, 1800),
    }) async {
      await pumpScreen(
        tester,
        const ApplicationDetailScreen(id: 'app_1'),
        size: size,
        overrides: applicationOverrides([app]),
      );
      await settle(tester);
    }

    testWidgets('a provider receipt is stated as the provider\'s word',
        (tester) async {
      await pumpWith(
        tester,
        built(
          code: 'provider_received',
          label: 'Application received',
          description: 'The provider has confirmed it has your application. '
              'Nothing has been decided yet.',
          events: const [
            ApplicationEvent(
              label: 'Application received',
              detail: 'The provider confirmed it has your application.',
              source: EventSource.provider,
            ),
          ],
        ),
      );

      expect(find.text('APPLICATION RECEIVED'), findsOneWidget);

      // The header specifically: the timeline legitimately echoes the same
      // fact, so the finder names the one under test.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('application_status_explanation')))
            .data,
        contains('confirmed it has your application'),
      );

      await golden(tester, ApplicationDetailScreen, 'status/provider_received');
    });

    testWidgets('an unconfirmed submission never says failed, and offers no retry',
        (tester) async {
      await pumpWith(
        tester,
        built(
          code: 'submission_unconfirmed',
          label: 'Submission status needs confirmation',
          description: 'We could not confirm whether the provider received '
              'your application. Please do not submit it again until we '
              'know — contact support and we will check.',
        ),
      );

      expect(
        find.text('SUBMISSION STATUS NEEDS CONFIRMATION'),
        findsOneWidget,
      );
      expect(find.text('Please do not submit this again'), findsOneWidget);
      expect(find.text('Contact support'), findsOneWidget);

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ')
          .toLowerCase();

      for (final wrong in [
        'your application failed',
        'rejected',
        'try submitting again',
        'submit again?',
      ]) {
        expect(text.contains(wrong), isFalse, reason: wrong);
      }

      await golden(tester, ApplicationDetailScreen, 'status/unconfirmed');
    });

    testWidgets('under review is attributed to the provider', (tester) async {
      await pumpWith(
        tester,
        built(
          code: 'under_review',
          label: 'Application under review',
          description: 'The provider has told us your application is being '
              'reviewed. They decide what happens next.',
          status: ApplicationStatus.underReview,
        ),
      );

      expect(
        tester
            .widget<Text>(find.byKey(const Key('application_status_explanation')))
            .data,
        contains('The provider has told us'),
      );

      await golden(tester, ApplicationDetailScreen, 'status/under_review');
    });

    testWidgets('approved says who approved it', (tester) async {
      await pumpWith(
        tester,
        built(
          code: 'approved',
          label: 'Application approved',
          description: 'The provider has approved your application.',
          status: ApplicationStatus.approved,
        ),
      );

      expect(find.text('APPLICATION APPROVED'), findsOneWidget);

      await golden(tester, ApplicationDetailScreen, 'status/approved');
    });

    testWidgets('declined is the provider\'s decision, not FynnEdge\'s',
        (tester) async {
      await pumpWith(
        tester,
        built(
          code: 'declined',
          label: 'Application declined',
          description: 'The provider has declined your application. This is '
              'their decision, not FynnEdge\'s.',
          status: ApplicationStatus.declined,
        ),
      );

      expect(
        tester
            .widget<Text>(find.byKey(const Key('application_status_explanation')))
            .data,
        contains('not FynnEdge'),
      );

      await golden(tester, ApplicationDetailScreen, 'status/declined');
    });

    testWidgets('a simulated application says so prominently', (tester) async {
      await pumpWith(
        tester,
        built(
          code: 'simulated',
          label: 'Simulated — not sent to any provider',
          description: 'This was a simulated submission. No lender or '
              'provider received this application.',
          isSimulated: true,
          events: const [
            ApplicationEvent(
              label: 'Application received',
              detail: 'The provider confirmed it has your application.',
              source: EventSource.simulated,
            ),
          ],
        ),
      );

      expect(
        find.textContaining('Simulated submission'),
        findsOneWidget,
      );

      await golden(tester, ApplicationDetailScreen, 'status/simulated');
    });

    testWidgets('no state overclaims what a provider said', (tester) async {
      for (final app in [
        built(
          code: 'started',
          label: 'Application started',
          description: 'Your application is saved here.',
          status: ApplicationStatus.started,
        ),
        built(
          code: 'submission_unconfirmed',
          label: 'Submission status needs confirmation',
          description: 'We could not confirm whether the provider received '
              'your application.',
        ),
        built(
          code: 'provider_received',
          label: 'Application received',
          description: 'The provider has confirmed it has your application.',
        ),
        built(
          code: 'under_review',
          label: 'Application under review',
          description: 'The provider has told us your application is being '
              'reviewed.',
          status: ApplicationStatus.underReview,
        ),
      ]) {
        await pumpWith(tester, app);

        final text = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join(' ')
            .toLowerCase();

        for (final claim in [
          'approval guaranteed', 'almost approved', 'bank approved',
          'guaranteed', 'pre-approved', 'you qualify',
          "we're processing your loan", 'loan confirmed',
        ]) {
          expect(
            text.contains(claim),
            isFalse,
            reason: '${app.customerStatus.code} said: $claim',
          );
        }
      }
    });

    testWidgets('it fits every supported width', (tester) async {
      for (final width in [360.0, 390.0, 420.0, 430.0]) {
        await pumpWith(
          tester,
          built(
            code: 'submission_unconfirmed',
            label: 'Submission status needs confirmation',
            description: 'We could not confirm whether the provider received '
                'your application. Please do not submit it again until we '
                'know — contact support and we will check.',
          ),
          size: Size(width, 2000),
        );
        expect(tester.takeException(), isNull, reason: '$width');
      }
    });
  });
}
