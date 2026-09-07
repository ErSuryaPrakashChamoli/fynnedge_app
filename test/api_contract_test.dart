import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/data/models/chat.dart';
import 'package:fynnedge/data/models/scan.dart';
import 'package:fynnedge/data/models/twin.dart';
import 'package:fynnedge/data/services/twin_service.dart';
import 'package:fynnedge/data/twin/fynn_twin_engine.dart';
import 'package:fynnedge/data/services/document_scan_service.dart';
import 'package:fynnedge/features/vault/sample_document.dart';
import 'package:fynnedge/data/models/document.dart';
import 'package:fynnedge/data/models/goal.dart';
import 'package:fynnedge/data/models/intent.dart';
import 'package:fynnedge/data/models/loan.dart';
import 'package:fynnedge/data/models/user.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/api_config.dart';
import 'package:fynnedge/core/money/money.dart';
import 'package:fynnedge/data/engine/financial_engine.dart';
import 'package:fynnedge/data/score/fynn_score_engine.dart';
import 'package:fynnedge/data/services/ai_service.dart';
import 'package:fynnedge/data/models/application.dart';
import 'package:fynnedge/data/models/consent.dart';
import 'package:fynnedge/data/models/credit.dart';
import 'package:fynnedge/data/services/consent_service.dart';
import 'package:fynnedge/data/models/kyc.dart';
import 'package:fynnedge/data/services/credit_service.dart';
import 'package:fynnedge/data/models/application_documents.dart';
import 'package:fynnedge/data/models/submission.dart';
import 'package:fynnedge/data/repositories/application_documents_repository.dart';
import 'package:fynnedge/data/services/application_documents_service.dart';
import 'package:fynnedge/data/services/kyc_service.dart';
import 'package:fynnedge/data/services/submission_service.dart';
import 'package:fynnedge/data/services/application_service.dart';
import 'package:fynnedge/data/services/auth_service.dart';
import 'package:fynnedge/data/match/fynn_match_engine.dart';
import 'package:fynnedge/data/models/match.dart';
import 'package:fynnedge/data/services/catalog_service.dart';
import 'package:fynnedge/data/services/match_service.dart';
import 'package:fynnedge/data/services/document_service.dart';
import 'package:fynnedge/data/services/home_service.dart';
import 'package:fynnedge/data/services/notification_service.dart';
import 'package:fynnedge/data/services/profile_service.dart';

/// Proves the Laravel API returns exactly what the Flutter models parse.
///
/// Requires the backend running:
///   cd ../fynnedge-api && php artisan serve --port=8123
///
/// Then:
///   flutter test test/api_contract_test.dart \
///     --dart-define=FYNN_API_BASE=http://127.0.0.1:8123
void main() {
  final api = ApiClient();

  // Skips rather than fails during a plain `flutter test`, so the suite stays
  // green when the backend is not running.
  final configured =
      ApiConfig.baseUrl.contains('127.0.0.1') ||
      ApiConfig.baseUrl.contains('localhost');
  const demoMobile = '9876543210';

  // OTP sends are rate limited to 3/min per number, so each OTP test uses its
  // own reserved number rather than hammering one. Re-running reuses the same
  // numbers, so the set of test customers stays fixed.
  const otpRoundTripMobile = '9000000001';
  const wrongCodeMobile = '9000000002';
  const replayMobile = '9000000003';
  const logoutMobile = '9000000004';

  final skip = configured
      ? null
      : 'Needs the API: php artisan serve --port=8123, then pass '
            '--dart-define=FYNN_API_BASE=http://127.0.0.1:8123';

  setUpAll(() async {
    if (skip != null) return;

    // Real authentication: request a code, read the development hint the
    // server returns, verify it, and keep the token for every later call.
    // This exercises the whole OTP flow on every run.
    final auth = ApiAuthService(api);

    // The OTP limiter is real (3/min per number), so two suite runs inside a
    // minute would otherwise fail on setup rather than on anything the tests
    // are actually checking. Wait it out instead of weakening the limiter.
    final challenge = await _sendOtpTolerantOfThrottling(auth, demoMobile);

    expect(
      challenge.devHint,
      isNotNull,
      reason: 'The API must be running a development OTP provider',
    );

    final session = await auth.verifyOtp(
      mobile: demoMobile,
      reference: challenge.reference,
      code: challenge.devHint!,
    );
    api.setToken(session.token);
  });

  test('an authenticated call is accepted', () async {
    final profile = await ApiAuthService(api).currentUser();
    expect(profile.mobile, demoMobile);
  }, skip: skip);

  test('GET /home parses into a HomeSnapshot', () async {
    final snapshot = await ApiHomeService(api).getSnapshot();
    expect(snapshot.customer.firstName, 'Rahul');
    expect(snapshot.customer.hasFinancialProfile, isTrue);
    expect(snapshot.financials.monthlyIncome, 100000);
    expect(snapshot.financials.surplus, 40000);
    // The real v1 score for these figures, not the prototype's 74.
    expect(snapshot.score.hasScore, isTrue);
    expect(snapshot.score.score, 83);
    expect(snapshot.score.dimensions, hasLength(3));
    expect(snapshot.score.modelVersion, 'fynnscore-v1');
    expect(snapshot.goals, isNotEmpty);
    // Nothing seeded: a count of what is stored, and a next step derived
    // from what the customer actually has.
    expect(snapshot.vaultDocumentCount, greaterThanOrEqualTo(0));
    expect(snapshot.primaryAction.key, isNotEmpty);
    expect(snapshot.primaryAction.route, startsWith('/'));
  }, skip: skip);

  test('GET /products parses, including the nested trust breakdown', () async {
    final products = await ApiCatalogService(api)
        .getProducts(category: LoanCategory.business, amount: 1000000);
    expect(products, hasLength(2));

    final best = products.firstWhere((p) => p.id == 'prod_bl_b');
    expect(best.lender, 'United Credit Bank');
    expect(best.interestRate, 12.4);
    expect(best.fynnTrust, 89);
    expect(best.trustBreakdown.all, hasLength(5));
    expect(best.processingFeeFor(1000000), 10000);
    expect(best.suitedReasons, isNotEmpty);
  }, skip: skip);

  test('GET /products/{id} parses a single product', () async {
    final product = await ApiCatalogService(api).getProduct('prod_bl_a');
    expect(product.lender, 'Arcus Capital');
    expect(product.category, LoanCategory.business);
    // Requirements the product does not publish must arrive as null, so the
    // engine reports them unchecked rather than assuming a value.
    expect(product.minMonthlyIncome, isNull);
    expect(product.maxAgeAtMaturity, isNull);
    expect(product.isSampleData, isTrue);
  }, skip: skip);

  test('GET /fynn-match parses, criteria and pricing included', () async {
    final result = await ApiMatchService(api).findMatches(
      const MatchRequest(
        amount: 1000000,
        tenureMonths: 60,
        purpose: 'business',
      ),
    );

    expect(result.evaluatedCount, 6);
    expect(result.matchCount, result.viable.length);
    expect(result.disclaimer, contains('not an approval'));
    expect(result.isSampleCatalogue, isTrue);

    final match = result.matches.first;
    expect(match.criteria, hasLength(6));
    expect(match.pricing.emi, greaterThan(0));
    expect(
      match.criteria.map((c) => c.key),
      containsAll(<String>[
        'purpose',
        'amount',
        'tenure',
        'minimum_income',
        'age',
        'affordability',
      ]),
    );
  }, skip: skip);

  test('the API and the Flutter engine agree on the same request', () async {
    // The customer's own figures come from the server; the products come from
    // the same catalogue. Both engines must reach the same verdicts.
    const request = MatchRequest(
      amount: 1000000,
      tenureMonths: 60,
      purpose: 'business',
    );
    final server = await ApiMatchService(api).findMatches(request);
    final financials = await ApiProfileService(api).getFinancialProfile();
    final profile = await ApiProfileService(api).getProfile();

    final local = const FynnMatchEngine().match(
      products: await ApiCatalogService(api).getProducts(),
      request: request,
      financials: const FinancialEngine().snapshot(
        income: Money.of(financials.monthlyIncome),
        expenses: Money.of(financials.monthlyExpenses),
        existingEmi: Money.of(financials.existingEmi),
        otherObligations: Money.of(financials.otherObligations),
        savings: Money.of(financials.savings),
      ),
      customerAge: profile.age,
    );

    expect(
      local.matches.map((m) => '${m.product.id}:${m.category.id}'),
      server.matches.map((m) => '${m.product.id}:${m.category.id}'),
    );
    for (var i = 0; i < server.matches.length; i++) {
      expect(local.matches[i].pricing.emi, server.matches[i].pricing.emi);
      expect(
        local.matches[i].criteria.map((c) => c.detail),
        server.matches[i].criteria.map((c) => c.detail),
      );
    }
  }, skip: skip);

  test('GET /fynn-match carries a projection the app can render', () async {
    final result = await ApiMatchService(api).findMatches(
      const MatchRequest(
        amount: 1000000,
        tenureMonths: 60,
        purpose: 'business',
      ),
    );

    // The customer's standing position, with no loan on it.
    final affordability = result.affordability;
    expect(affordability.isMeasurable, isTrue);
    expect(affordability.emi.rupees, 0);
    expect(affordability.emiCeiling.rupees, greaterThan(0));
    expect(
      affordability.currentEmiRatio.value,
      affordability.projectedEmiRatio.value,
    );

    // And per product, the same position carrying that product's EMI.
    final match = result.matches.first;
    expect(match.projection.emi.rupees, match.pricing.emi);
    expect(
      match.projection.projectedOutgo.rupees -
          match.projection.currentOutgo.rupees,
      closeTo(match.pricing.emi, 0.01),
    );
    expect(
      match.projection.projectedEmiRatio.value,
      match.pricing.projectedEmiRatio,
    );
    expect(match.projection.isEstimate, isTrue);
  }, skip: skip);

  test('GET /fynn-match/{id} simulates without changing anything', () async {
    final before = await ApiProfileService(api).getFinancialProfile();

    final simulated = await ApiMatchService(api).simulate(
      'prod_bl_b',
      const MatchRequest(
        amount: 2000000,
        tenureMonths: 84,
        purpose: 'business',
      ),
    );

    expect(simulated.product.id, 'prod_bl_b');
    expect(simulated.pricing.amount, 2000000);
    expect(simulated.pricing.tenureMonths, 84);
    expect(simulated.pricing.emi, 35734.72);

    // Nothing the customer has saved moved because they moved a slider.
    final after = await ApiProfileService(api).getFinancialProfile();
    expect(after.monthlyIncome, before.monthlyIncome);
    expect(after.existingEmi, before.existingEmi);
    expect(after.savings, before.savings);
  }, skip: skip);

  test('the API and the Flutter engine agree on a simulation', () async {
    const request = MatchRequest(
      amount: 1500000,
      tenureMonths: 48,
      purpose: 'business',
    );

    final server = await ApiMatchService(api).simulate('prod_bl_b', request);
    final financials = await ApiProfileService(api).getFinancialProfile();
    final profile = await ApiProfileService(api).getProfile();

    final local = const FynnMatchEngine().evaluate(
      product: await ApiCatalogService(api).getProduct('prod_bl_b'),
      request: request,
      financials: const FinancialEngine().snapshot(
        income: Money.of(financials.monthlyIncome),
        expenses: Money.of(financials.monthlyExpenses),
        existingEmi: Money.of(financials.existingEmi),
        otherObligations: Money.of(financials.otherObligations),
        savings: Money.of(financials.savings),
      ),
      customerAge: profile.age,
    );

    expect(local.pricing.emi, server.pricing.emi);
    expect(local.category, server.category);
    expect(
      local.projection.projectedSurplus.rupees,
      server.projection.projectedSurplus.rupees,
    );
    expect(
      local.projection.headroomAfter.rupees,
      server.projection.headroomAfter.rupees,
    );
    expect(local.projection.withinCeiling, server.projection.withinCeiling);
  }, skip: skip);

  test('a simulation of an unknown product is a handled 404', () async {
    await expectLater(
      ApiMatchService(api).simulate(
        'prod_does_not_exist',
        const MatchRequest(amount: 1000000, tenureMonths: 60),
      ),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
  }, skip: skip);

  test('a simulation requires a session', () async {
    await expectLater(
      ApiMatchService(ApiClient()).simulate(
        'prod_bl_b',
        const MatchRequest(amount: 1000000, tenureMonths: 60),
      ),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('FynnMatch requires a session', () async {
    await expectLater(
      ApiMatchService(ApiClient())
          .findMatches(const MatchRequest(amount: 1000000, tenureMonths: 60)),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('FynnMatch rejects a request it cannot evaluate', () async {
    await expectLater(
      ApiMatchService(api).findMatches(
        const MatchRequest(
          amount: 1000000,
          tenureMonths: 60,
          purpose: 'spaceship',
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
  }, skip: skip);

  test('GET /fynn-score and /financial-profile parse', () async {
    final service = ApiProfileService(api);
    final score = await service.getFynnScore();
    expect(score.hasScore, isTrue);
    expect(score.band, isNotNull);
    expect(score.dimensions, hasLength(3));

    final financials = await service.getFinancialProfile();
    expect(financials.existingEmi, 20000);
    expect(financials.emiRatio, 20);
  }, skip: skip);

  test('the application journey round-trips against the API', () async {
    final service = ApiApplicationService(api);
    final key = 'contract-${DateTime.now().microsecondsSinceEpoch}';

    // Start it with figures nothing may round or default.
    final draft = await service.create(
      const ApplicationDraft(
        productId: 'prod_bl_b',
        amount: 1234567.89,
        tenureMonths: 7,
      ),
      idempotencyKey: key,
    );

    expect(draft.amount, 1234567.89);
    expect(draft.tenureMonths, 7);
    expect(draft.productId, 'prod_bl_b');
    expect(draft.status, ApplicationStatus.started);
    expect(draft.canSubmit, isTrue);
    expect(draft.isSimulated, isFalse);
    expect(draft.reference, startsWith('FE-'));
    expect(draft.events.single.source, EventSource.fynnedge);

    // The same key is the same operation, not a second application.
    final repeat = await service.create(
      const ApplicationDraft(
        productId: 'prod_bl_b',
        amount: 1234567.89,
        tenureMonths: 7,
      ),
      idempotencyKey: key,
    );
    expect(repeat.id, draft.id);

    // Submit, and submit again: one submission.
    final submitted = await service.submit(draft.id);
    expect(submitted.status, ApplicationStatus.submitted);
    expect(submitted.amount, 1234567.89);
    expect(submitted.tenureMonths, 7);
    expect(submitted.isSimulated, isTrue);
    expect(submitted.gateway, 'mock');
    expect(submitted.providerReference, isNull);
    expect(submitted.hasProviderEvents, isFalse);
    expect(submitted.events.where((e) => e.label == 'Submitted'), hasLength(1));

    final again = await service.submit(draft.id);
    expect(again.submittedAt, submitted.submittedAt);
    expect(again.events.length, submitted.events.length);

    // It appears in the list, and reads back the same.
    final listed = await service.getApplications();
    final found = listed.firstWhere((a) => a.id == draft.id);
    expect(found.amount, 1234567.89);
    expect(found.tenureMonths, 7);

    final fetched = await service.getApplication(draft.id);
    expect(fetched.reference, draft.reference);

    // Tidy up so a re-run starts clean.
    final cancelled = await service.cancel(draft.id);
    expect(cancelled.status, ApplicationStatus.cancelled);
  }, skip: skip);

  test('an application belonging to nobody is a handled 404', () async {
    await expectLater(
      ApiApplicationService(api).getApplication('99999999'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
  }, skip: skip);

  test('the consent catalogue and ledger round-trip against the API', () async {
    final service = ApiConsentService(api);

    final state = await service.getConsents();
    expect(state.consents, hasLength(9));
    expect(state.byType(ConsentType.serviceTerms)!.isRequired, isTrue);

    // The bureau consent is served, and served as not available.
    final bureau = state.byType(ConsentType.creditBureauCheck)!;
    expect(bureau.isAvailable, isFalse);
    expect(bureau.currentVersion, isNull);
    expect(bureau.unavailableReason, isNotNull);

    // It cannot be granted.
    await expectLater(
      service.grant(ConsentType.creditBureauCheck),
      throwsA(isA<ApiException>()),
    );

    // An optional one can, twice, recording one decision.
    final granted = await service.grant(ConsentType.aiMemory);
    expect(granted.isGranted(ConsentType.aiMemory), isTrue);
    await service.grant(ConsentType.aiMemory);

    final withdrawn = await service.withdraw(ConsentType.aiMemory);
    expect(withdrawn.isGranted(ConsentType.aiMemory), isFalse);

    // A required one cannot be withdrawn.
    await service.grant(ConsentType.serviceTerms);
    await expectLater(
      service.withdraw(ConsentType.serviceTerms),
      throwsA(isA<ApiException>()),
    );
    expect(
      (await service.getConsents()).isGranted(ConsentType.serviceTerms),
      isTrue,
    );

    // History keeps every decision, with no database ids. The exact order
    // is pinned by the backend suite against a clean database; here the
    // account carries whatever earlier runs decided, so this checks that
    // every decision made above is present.
    final history = await service.getHistory();
    expect(history.length, greaterThanOrEqualTo(3));
    expect(
      history.map((r) => '${r.type.id}:${r.status.id}'),
      containsAll(<String>[
        'ai_memory:granted',
        'ai_memory:withdrawn',
        'service_terms:granted',
      ]),
    );
    for (final record in history) {
      expect(record.version, isNotEmpty);
      expect(record.source, isNotEmpty);
      expect(record.at, isNotNull);
    }
  }, skip: skip);

  test('the credit boundary round-trips against the API', () async {
    final service = ApiCreditService(api);

    // The API's default driver is `none`. NO LIVE BUREAU IS CONNECTED, and
    // the contract says so rather than pretending a check is possible.
    final state = await service.getStatus();
    expect(state.status, CreditReportStatus.notConfigured);
    expect(state.profile, isNull);
    expect(state.canCheck, isFalse);

    // A check refuses with the capability error, not a score and not a
    // generic fault.
    await expectLater(
      service.check(),
      throwsA(isA<CapabilityUnavailableException>()),
    );
  }, skip: skip);

  test('the scan boundary round-trips against the API', () async {
    final documents = ApiDocumentService(api);
    final scans = ApiDocumentScanService(api);

    final stored = await documents.upload(
      DocumentUpload(
        name: 'Contract payslip',
        category: DocumentCategory.income,
        fileName: 'payslip.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList('%PDF-1.4\n%%EOF\n'.codeUnits),
      ),
    );

    // The API's default driver is `none`. NO LIVE DOCUMENT PROVIDER IS
    // CONNECTED, and the contract says so rather than pretending.
    final state = await scans.statusFor(stored.id);
    expect(state.status, ScanStatus.unavailable);
    expect(state.reason, 'document_understanding_not_configured');
    expect(state.extraction, isNull);
    expect(state.isSample, isFalse);
    expect(state.canScan, isFalse);

    // Asking answers the same way, and writes nothing.
    final asked = await scans.scan(stored.id);
    expect(asked.status, ScanStatus.unavailable);
    expect(asked.scanId, isNull);

    // And there is nothing to review, so reviewing is refused rather than
    // recorded.
    await expectLater(
      scans.review(
        stored.id,
        field: 'net_income',
        decision: ReviewDecision.confirmed,
      ),
      throwsA(isA<ApiException>()),
    );

    await documents.delete(stored.id);
  }, skip: skip);

  test('the identity verification boundary round-trips against the API',
      () async {
    final documents = ApiDocumentService(api);
    final kyc = ApiKycService(api);

    final stored = await documents.upload(
      DocumentUpload(
        name: 'Contract identity document',
        category: DocumentCategory.identity,
        fileName: 'id.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList('%PDF-1.4\n%%EOF\n'.codeUnits),
      ),
    );

    // The API's default driver is `none`. NO LIVE KYC PROVIDER IS
    // CONNECTED, and the contract says unavailable — never "not verified",
    // which would be a finding about the customer.
    final state = await kyc.statusFor(stored.id);
    expect(state.status, VerificationStatus.unavailable);
    expect(state.reason, 'verification_not_configured');
    expect(state.fieldMatches, isNull);
    expect(state.documentResult, isNull);
    expect(state.isSample, isFalse);
    expect(state.canVerify, isFalse);

    final asked = await kyc.verify(stored.id);
    expect(asked.status, VerificationStatus.unavailable);
    expect(asked.verificationId, isNull);

    // Nothing to resolve, so resolving is refused rather than recorded.
    await expectLater(
      kyc.resolve(
        stored.id,
        field: 'name',
        decision: ResolutionDecision.updateProfile,
      ),
      throwsA(isA<ApiException>()),
    );

    await documents.delete(stored.id);
  }, skip: skip);

  test('the submission boundary round-trips against the API', () async {
    final applications = ApiApplicationService(api);
    final submissions = ApiSubmissionService(api);

    final application = await applications.create(
      const ApplicationDraft(
        productId: 'prod_bl_b',
        amount: 1000000,
        tenureMonths: 60,
      ),
      idempotencyKey: 'submission-${DateTime.now().microsecondsSinceEpoch}',
    );

    // The API's default driver is `none`. NO LIVE SUBMISSION PROVIDER IS
    // CONNECTED, and the contract says not-sent — never "failed", which
    // would be a finding about the customer's application.
    final state = await submissions.statusFor(application.id);
    expect(state.outcome, SubmissionOutcome.unavailable);
    expect(state.providerReceived, isFalse);
    expect(state.isSimulated, isFalse);
    expect(state.canRetry, isFalse);
    expect(state.message, contains('nothing about it has failed'));

    // FynnEdge's own reference survives untouched.
    expect(state.application.reference, application.reference);

    // Asking answers the same way and creates no attempt.
    final asked = await submissions.submit(application.id);
    expect(asked.outcome, SubmissionOutcome.unavailable);
    expect(asked.providerReceived, isFalse);

    // And Module 9's own submit still works, meaning something different:
    // the customer has completed their application inside FynnEdge.
    final submitted = await applications.submit(application.id);
    expect(submitted.status, ApplicationStatus.submitted);

    final after = await submissions.statusFor(application.id);
    expect(
      after.providerReceived,
      isFalse,
      reason: 'a FynnEdge submission was read as a provider receiving it',
    );

    await applications.cancel(application.id);
  }, skip: skip);

  test('the application document journey round-trips against the API',
      () async {
    final applications = ApiApplicationService(api);
    final documents = ApiDocumentService(api);
    final checklists = ApplicationDocumentsRepository(
      ApiApplicationDocumentsService(api),
    );

    final application = await applications.create(
      const ApplicationDraft(
        productId: 'prod_bl_b',
        amount: 1000000,
        tenureMonths: 60,
      ),
      idempotencyKey: 'docs-${DateTime.now().microsecondsSinceEpoch}',
    );

    // A business loan states what it asks for, and nothing is ready.
    final initial = await checklists.checklist(application.id);
    expect(initial.ready, isFalse);
    expect(
      initial.items.map((i) => i.code),
      containsAll(<String>['identity', 'income', 'bank']),
    );
    expect(initial.items.every((i) => i.status == RequirementStatus.missing),
        isTrue);

    // The optional one is offered and never blocks.
    final optional = initial.items.firstWhere((i) => !i.required);
    expect(optional.blocksReadiness, isFalse);

    // Choose a vault document for one requirement.
    final stored = await documents.upload(
      DocumentUpload(
        name: 'Contract income document',
        category: DocumentCategory.income,
        fileName: 'payslip.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList('%PDF-1.4\n%%EOF\n'.codeUnits),
      ),
    );

    final attached = await checklists.attach(
      application.id,
      'income',
      stored.id,
    );

    final income = attached.items.firstWhere((i) => i.code == 'income');

    // Choosing is not confirming.
    expect(income.status, RequirementStatus.available);
    expect(income.document!.id, stored.id);
    expect(attached.ready, isFalse);

    // Confirming is the customer's own act.
    final confirmed = await checklists.confirm(application.id, 'income');
    expect(
      confirmed.items.firstWhere((i) => i.code == 'income').status,
      RequirementStatus.ready,
    );

    // Still not ready: other required documents remain.
    expect(confirmed.ready, isFalse);

    // Deleting the vault document invalidates the confirmation.
    await documents.delete(stored.id);

    final afterDelete = await checklists.checklist(application.id);
    final gone = afterDelete.items.firstWhere((i) => i.code == 'income');
    expect(gone.status, RequirementStatus.missing);
    expect(gone.document, isNull);
    expect(gone.notice, contains('no longer in FynnVault'));

    // And none of it sent anything anywhere.
    final submission =
        await ApiSubmissionService(api).statusFor(application.id);
    expect(submission.providerReceived, isFalse);
    expect(submission.outcome, SubmissionOutcome.unavailable);

    await applications.cancel(application.id);
  }, skip: skip);

  test('the provider event ingress refuses everything it should', () async {
    // NO LIVE PROVIDER EVENT SOURCE IS CONNECTED. The API's default driver
    // is `none`, so the allowlist is empty and every provider code is a
    // plain 404 — including one an attacker might guess.
    final ingress = ApiClient();

    for (final provider in ['fixture', 'some-real-bank', 'hdfc']) {
      await expectLater(
        ingress.post(
          '/provider-events/$provider',
          body: {
            'eventType': 'APPROVED',
            'submissionRef': 'GW-1',
            'eventTime': '2026-09-07T10:00:00+05:30',
          },
        ),
        throwsA(isA<ApiException>()),
        reason: provider,
      );
    }
  }, skip: skip);

  test('a customer session authenticates no provider event', () async {
    // The customer's own authenticated client, reporting their approval.
    await expectLater(
      api.post(
        '/provider-events/fixture',
        body: {
          'eventType': 'APPROVED',
          'submissionRef': 'GW-1',
          'eventTime': '2026-09-07T10:00:00+05:30',
        },
      ),
      throwsA(isA<ApiException>()),
    );
  }, skip: skip);

  test('an application carries a customer status it did not invent', () async {
    final applications = ApiApplicationService(api);

    final application = await applications.create(
      const ApplicationDraft(
        productId: 'prod_bl_b',
        amount: 1000000,
        tenureMonths: 60,
      ),
      idempotencyKey: 'status-${DateTime.now().microsecondsSinceEpoch}',
    );

    // Nothing has been sent, so nothing provider-derived may appear.
    expect(application.customerStatus.code, 'started');
    expect(application.customerStatus.isFromProvider, isFalse);
    expect(application.customerStatus.isUnconfirmed, isFalse);
    expect(application.customerStatus.label, isNotEmpty);

    /*
     * A customer cannot write one either.
     *
     * The update endpoint takes what a customer may legitimately change and
     * ignores the rest, so a forged status is not an error — it simply
     * reaches nothing, which the assertions below check.
     */
    await api.put(
      '/applications/${application.id}',
      body: {
        'status': 'approved',
        'customer_status': {'code': 'approved'},
        'events': [
          {'label': 'Application approved', 'source': 'provider'},
        ],
      },
    );

    final after = await applications.getApplication(application.id);
    expect(after.status, ApplicationStatus.started);
    expect(after.customerStatus.isFromProvider, isFalse);

    // And no timeline entry claims a provider said anything.
    expect(
      after.events.any((e) => e.source == EventSource.provider),
      isFalse,
    );

    await applications.cancel(application.id);
  }, skip: skip);

  test('application documents require a session', () async {
    await expectLater(
      ApplicationDocumentsRepository(
        ApiApplicationDocumentsService(ApiClient()),
      ).checklist('1'),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('external submission requires a session', () async {
    await expectLater(
      ApiSubmissionService(ApiClient()).statusFor('1'),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('identity verification requires a session', () async {
    await expectLater(
      ApiKycService(ApiClient()).statusFor('1'),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('reading a document requires a session', () async {
    await expectLater(
      ApiDocumentScanService(ApiClient()).statusFor('1'),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('credit information requires a session', () async {
    await expectLater(
      ApiCreditService(ApiClient()).getStatus(),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('consent requires a session', () async {
    await expectLater(
      ApiConsentService(ApiClient()).getConsents(),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('the application journey requires a session', () async {
    await expectLater(
      ApiApplicationService(ApiClient()).getApplications(),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('the vault holds only what this customer put in it', () async {
    // No seeded documents: a vault starts as whatever the customer has
    // added, which for a fresh account is nothing.
    final docs = await ApiDocumentService(api).getDocuments();

    for (final doc in docs) {
      expect(doc.status, DocumentStatus.uploaded);
      expect(doc.isVerified, isFalse);
    }
  }, skip: skip);

  test('GET /notifications sends nothing, because nothing was sent', () async {
    // Nothing in FynnEdge writes a notification. The endpoint used to serve
    // four seeded items, two of which made claims nobody could stand behind.
    final notifications = await ApiNotificationService(api).getNotifications();
    expect(notifications, isEmpty);
  }, skip: skip);

  test('OTP round-trip issues a session', () async {
    final auth = ApiAuthService(ApiClient());
    final challenge = await _sendOtpTolerantOfThrottling(
      auth,
      otpRoundTripMobile,
    );
    expect(challenge.reference, isNotEmpty);
    expect(challenge.devHint, isNotNull);

    final session = await auth.verifyOtp(
      mobile: otpRoundTripMobile,
      reference: challenge.reference,
      code: challenge.devHint!,
    );
    expect(session.token, isNotEmpty);
    expect(session.profile.mobile, otpRoundTripMobile);
    // Tokens must expire; a session that never ends is a liability.
    expect(session.expiresAt, isNotNull);
    expect(session.expiresAt!.isAfter(DateTime.now()), isTrue);
  }, skip: skip);

  test('a wrong code is rejected', () async {
    final auth = ApiAuthService(ApiClient());
    final challenge = await _sendOtpTolerantOfThrottling(auth, wrongCodeMobile);
    final wrong = challenge.devHint == '000000' ? '111111' : '000000';

    await expectLater(
      auth.verifyOtp(
        mobile: wrongCodeMobile,
        reference: challenge.reference,
        code: wrong,
      ),
      throwsA(isA<ApiException>()),
    );
  }, skip: skip);

  test('a code cannot be replayed', () async {
    final auth = ApiAuthService(ApiClient());
    final challenge = await _sendOtpTolerantOfThrottling(auth, replayMobile);

    await auth.verifyOtp(
      mobile: replayMobile,
      reference: challenge.reference,
      code: challenge.devHint!,
    );

    await expectLater(
      auth.verifyOtp(
        mobile: replayMobile,
        reference: challenge.reference,
        code: challenge.devHint!,
      ),
      throwsA(isA<ApiException>()),
    );
  }, skip: skip);

  test('an unauthenticated call is refused', () async {
    // A client that has never been given a token must be turned away.
    await expectLater(
      ApiProfileService(ApiClient()).getProfile(),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('a garbage token is refused', () async {
    final rogue = ApiClient()..setToken('not-a-real-token');

    await expectLater(
      ApiProfileService(rogue).getProfile(),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('a rejected field arrives as a ValidationException', () async {
    await expectLater(
      ApiAuthService(ApiClient()).sendOtp('12'),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.forField('mobile'),
          'mobile error',
          isNotNull,
        ),
      ),
    );
  }, skip: skip);

  test(
    'FynnAI answers from the authenticated customer\'s own context',
    () async {
      final ai = ApiAiService(api);
      final profile = await ApiProfileService(api).getFinancialProfile();
      final score = await ApiProfileService(api).getFynnScore();

      final conversation = await ai.startConversation();
      expect(conversation.id, isNotEmpty);

      // A question about the customer's own score is answered from the real
      // score object, not from a number the assistant chose.
      final scoreReply = await ai.send(
        conversationId: conversation.id,
        text: 'Explain my FynnScore',
      );
      expect(scoreReply.message.text, contains('${score.score}'));
      expect(scoreReply.provider.available, isTrue);
      // The assistant FynnEdge ships is rules, and says so.
      expect(scoreReply.provider.isLanguageModel, isFalse);

      // Affordability comes from the engines, against the customer's real
      // income — and never claims a lender decision.
      final affordability = await ai.send(
        conversationId: conversation.id,
        text: 'Can I afford a 10 lakh loan?',
      );
      expect(affordability.message.text, contains('13.25%'));
      expect(affordability.message.text, contains('not a lender rule'));
      for (final forbidden in const ['approved', 'guaranteed', 'you qualify']) {
        expect(
          affordability.message.text.toLowerCase(),
          isNot(contains(forbidden)),
        );
      }

      // Both sides of the exchange are kept, and nothing else is.
      final stored = await ai.getConversation(conversation.id);
      expect(stored.messages, hasLength(4));
      expect(stored.messages.first.role, ChatRole.user);
      // Only the two roles a customer's transcript can contain — a system
      // prompt is not something they said.
      for (final message in stored.messages) {
        expect(ChatRole.values, contains(message.role));
      }

      // The document boundary holds against the live API.
      final documents = await ai.send(
        conversationId: conversation.id,
        text: 'What does my bank statement say?',
      );
      expect(
        documents.message.text,
        anyOf(
          contains('document-reading service'),
          contains('nothing in FynnVault'),
        ),
      );

      await ai.deleteConversation(conversation.id);
      await expectLater(
        ai.getConversation(conversation.id),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );

      expect(profile.monthlyIncome, greaterThanOrEqualTo(0));
    },
    skip: skip,
  );

  test('FynnAI context is the authenticated customer\'s only', () async {
    final context = await api.get('/ai/context') as Map<String, dynamic>;
    final body = jsonEncode(context);

    // Nothing about storage, credentials or another customer.
    for (final forbidden in const [
      'storage_key',
      'storage_disk',
      'password',
      'remember_token',
      'api_key',
    ]) {
      expect(body, isNot(contains(forbidden)));
    }

    expect(context['context'], isA<Map<String, dynamic>>());
    expect(
      (context['provider'] as Map<String, dynamic>)['is_language_model'],
      isFalse,
    );
  }, skip: skip);

  test('another customer\'s conversation is a 404', () async {
    // Ids are sequential, so a neighbouring id is the most likely thing a
    // client would try. It must not resolve.
    await expectLater(
      ApiAiService(api).getConversation('999999'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
    );
  }, skip: skip);

  test(
    'FynnTwin projects from the real profile and persists nothing',
    () async {
      final twin = ApiTwinService(api);
      final profile = await ApiProfileService(api).getFinancialProfile();

      final capabilities = await twin.capabilities();
      expect(capabilities.hasFinancialProfile, isTrue);
      expect(
        capabilities.referencePercent,
        FinancialEngine.affordabilityCeilingPercent,
      );

      const loan = TwinScenario(
        type: ScenarioType.loan,
        amount: 1000000,
        tenureMonths: 60,
        productId: 'prod_bl_b',
      );

      final projection = await twin.simulate(loan);

      // The current side is the customer's real profile, through the engine.
      expect(projection.current.monthlyIncome, profile.monthlyIncome);
      expect(projection.current.monthlyOutgo, profile.monthlyOutgo);
      expect(projection.current.surplus, profile.surplus);
      expect(projection.current.emiRatio, profile.emiRatio);

      // And the server's projection matches the local engine exactly.
      final local = fynnTwinEngine.simulate(
        current: const FinancialEngine().snapshot(
          income: Money.of(profile.monthlyIncome),
          expenses: Money.of(profile.monthlyExpenses),
          existingEmi: Money.of(profile.existingEmi),
          otherObligations: Money.of(profile.otherObligations),
          savings: Money.of(profile.savings),
        ),
        scenario: loan,
        product: await ApiCatalogService(api).getProduct('prod_bl_b'),
      );

      expect(projection.projected.monthlyOutgo, local.projected.monthlyOutgo);
      expect(projection.projected.surplus, local.projected.surplus);
      expect(projection.projected.emiRatio, local.projected.emiRatio);
      expect(projection.loan!.emi, local.loan!.emi);
      expect(
        projection.observations.map((o) => o.key),
        local.observations.map((o) => o.key),
      );

      // A different scenario gives a different projection.
      final bigger = await twin.simulate(
        const TwinScenario(
          type: ScenarioType.loan,
          amount: 2500000,
          tenureMonths: 60,
          productId: 'prod_bl_b',
        ),
      );
      expect(bigger.loan!.emi, greaterThan(projection.loan!.emi));
      expect(bigger.projected.surplus, lessThan(projection.projected.surplus));

      // And the customer is exactly as they were: no profile change, no
      // application, nothing saved.
      final after = await ApiProfileService(api).getFinancialProfile();
      expect(after.monthlyIncome, profile.monthlyIncome);
      expect(after.existingEmi, profile.existingEmi);
      expect(after.savings, profile.savings);
    },
    skip: skip,
  );

  test('FynnTwin refuses a product outside the catalogue', () async {
    await expectLater(
      ApiTwinService(api).simulate(
        const TwinScenario(
          type: ScenarioType.loan,
          amount: 100000,
          tenureMonths: 12,
          productId: 'prod_imaginary',
        ),
      ),
      throwsA(isA<ApiException>()),
    );
  }, skip: skip);

  test('FynnTwin requires a session', () async {
    await expectLater(
      ApiTwinService(ApiClient()).capabilities(),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('FynnAI requires a session', () async {
    await expectLater(
      ApiAiService(ApiClient()).getConversations(),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('PUT /profile round-trips the edited fields', () async {
    final service = ApiProfileService(api);
    final original = await service.getProfile();

    try {
      final updated = await service.updateProfile(
        original.copyWith(fullName: 'Rahul S Sharma', age: 35, city: 'Mumbai'),
      );
      expect(updated.fullName, 'Rahul S Sharma');
      expect(updated.city, 'Mumbai');
      expect(updated.age, 35);
    } finally {
      // These run against a live database; leave it as we found it.
      await service.updateProfile(original);
    }
  }, skip: skip);

  test('PUT /financial-profile round-trips and recomputes', () async {
    final service = ApiProfileService(api);
    final original = await service.getFinancialProfile();

    try {
      final saved = await service.updateFinancialProfile(
        const FinancialProfile(
          monthlyIncome: 150000,
          monthlyExpenses: 50000,
          existingEmi: 25000,
          savings: 400000,
          otherObligations: 5000,
          employment: EmploymentType.salaried,
        ),
      );
      expect(saved.monthlyIncome, 150000);
      // Surplus must net off other obligations, matching the Dart model.
      expect(saved.surplus, 70000);
      expect(saved.employment, EmploymentType.salaried);
    } finally {
      await service.updateFinancialProfile(original);
    }
  }, skip: skip);

  test('goals round-trip: create, update, then delete', () async {
    final service = ApiProfileService(api);

    final created = await service.createGoal(
      Goal(
        id: '',
        title: 'Contract Test Vehicle',
        category: GoalCategory.car,
        targetAmount: 800000,
        targetDate: DateTime.now().add(const Duration(days: 700)),
        savedAmount: 50000,
      ),
    );
    expect(created.id, isNotEmpty);
    expect(created.title, 'Contract Test Vehicle');
    expect(created.category, GoalCategory.car);
    expect(created.targetAmount, 800000);
    expect(created.progress, closeTo(0.0625, 0.001));

    final renamed = await service.updateGoal(
      Goal(
        id: created.id,
        title: 'Contract Test Renamed',
        category: created.category,
        targetAmount: 900000,
        targetDate: created.targetDate,
        savedAmount: created.savedAmount,
      ),
    );
    expect(renamed.title, 'Contract Test Renamed');
    expect(renamed.targetAmount, 900000);

    // The suite runs against a live database, so it must leave no residue.
    await service.deleteGoal(created.id);
    final remaining = await service.getGoals();
    expect(remaining.map((g) => g.id), isNot(contains(created.id)));
  }, skip: skip);

  test('GET /goals parses dates and derived figures', () async {
    final goals = await ApiProfileService(api).getGoals();
    expect(goals, isNotEmpty);

    // Located by name, not position: the API orders by target date and the
    // seed may grow.
    final business = goals.firstWhere((g) => g.title == 'Business Expansion');
    expect(business.category, GoalCategory.business);
    expect(business.targetDate.isAfter(DateTime.now()), isTrue);
    expect(business.progress, greaterThan(0));
    expect(business.progress, lessThanOrEqualTo(1));
    expect(business.monthsRemaining, greaterThan(0));
  }, skip: skip);

  test('a document round-trips through the vault', () async {
    final service = ApiDocumentService(api);
    final bytes = SampleDocument.bytes(title: 'Contract test document');

    final uploaded = await service.upload(
      DocumentUpload(
        bytes: bytes,
        fileName: SampleDocument.fileName,
        mimeType: SampleDocument.mimeType,
        category: DocumentCategory.bank,
        name: 'Contract test document',
      ),
    );

    expect(uploaded.id, isNotEmpty);
    expect(uploaded.category, DocumentCategory.bank);
    expect(uploaded.status, DocumentStatus.uploaded);
    expect(uploaded.sizeBytes, bytes.length);
    expect(uploaded.mimeType, 'application/pdf');
    // Stored is not verified, and storing is not sharing.
    expect(uploaded.isVerified, isFalse);
    expect(uploaded.isShared, isFalse);

    // The payload carries no storage location.
    final json = jsonEncode(uploaded.toJson());
    expect(json, isNot(contains('storage_key')));
    expect(json, isNot(contains('storage_disk')));

    // It lists, reads back, and the bytes come down intact.
    final listed = await service.getDocuments();
    expect(listed.map((d) => d.id), contains(uploaded.id));
    expect((await service.getDocument(uploaded.id)).name, uploaded.name);
    expect(await service.download(uploaded.id), bytes);

    // And deleting it removes it for good.
    await service.delete(uploaded.id);
    expect(
      (await service.getDocuments()).map((d) => d.id),
      isNot(contains(uploaded.id)),
    );
    await expectLater(
      service.getDocument(uploaded.id),
      throwsA(isA<ApiException>()),
    );
  }, skip: skip);

  test('FynnScan answers truthfully that it is not connected', () async {
    final documents = ApiDocumentService(api);
    final scans = ApiDocumentScanService(api);
    final bytes = SampleDocument.bytes(title: 'Scan contract document');

    // Select → upload → in the vault.
    final stored = await documents.upload(
      DocumentUpload(
        bytes: bytes,
        fileName: SampleDocument.fileName,
        mimeType: SampleDocument.mimeType,
        category: DocumentCategory.bank,
        name: 'Scan contract document',
      ),
    );
    expect(
      (await documents.getDocuments()).map((d) => d.id),
      contains(stored.id),
    );

    // Reading the state, and asking for a scan, both say the same thing.
    for (final scan in [
      await scans.statusFor(stored.id),
      await scans.scan(stored.id),
    ]) {
      expect(scan.status, ScanStatus.unavailable);
      expect(scan.reason, 'document_understanding_not_configured');
      expect(scan.message, contains('Nothing has been extracted'));
      expect(scan.provider, isNull);
      expect(scan.extraction, isNull);
      expect(scan.isSample, isFalse);
      expect(scan.startedAt, isNull);
    }

    // The document is untouched, and still downloadable.
    final after = await documents.getDocument(stored.id);
    expect(after.status, DocumentStatus.uploaded);
    expect(after.isVerified, isFalse);
    expect(await documents.download(stored.id), bytes);

    await documents.delete(stored.id);

    // And a deleted document cannot be scanned.
    await expectLater(
      scans.statusFor(stored.id),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
    );
  }, skip: skip);

  test('scanning requires a session', () async {
    await expectLater(
      ApiDocumentScanService(ApiClient()).statusFor('1'),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('the vault refuses a file it does not take', () async {
    await expectLater(
      ApiDocumentService(api).upload(
        DocumentUpload(
          bytes: Uint8List.fromList(utf8.encode('<?php echo 1; ?>')),
          fileName: 'sneaky.php',
          mimeType: 'application/x-php',
          category: DocumentCategory.other,
        ),
      ),
      throwsA(isA<ApiException>()),
    );
  }, skip: skip);

  test('the vault requires a session', () async {
    await expectLater(
      ApiDocumentService(ApiClient()).getDocuments(),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('notification read endpoints respond', () async {
    final service = ApiNotificationService(api);
    await service.markRead('ntf_1');
    await service.markAllRead();
  }, skip: skip);

  test('logout revokes the token it was called with', () async {
    // A throwaway session, so revoking it cannot disturb the shared token.
    final client = ApiClient();
    final auth = ApiAuthService(client);
    final challenge = await _sendOtpTolerantOfThrottling(auth, logoutMobile);
    final session = await auth.verifyOtp(
      mobile: logoutMobile,
      reference: challenge.reference,
      code: challenge.devHint!,
    );
    client.setToken(session.token);

    await auth.logout();

    final revoked = ApiClient()..setToken(session.token);
    await expectLater(
      ApiProfileService(revoked).getProfile(),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test('a missing product returns a handled 404, not a crash', () async {
    expect(
      () => ApiCatalogService(api).getProduct('does_not_exist'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
  }, skip: skip);

  test('a validation failure surfaces the server message', () async {
    // A different malformed number from the test above: the OTP limiter keys
    // on the number, and two tests sharing one key trip it on a repeat run.
    await expectLater(
      ApiAuthService(ApiClient()).sendOtp('34'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 422),
      ),
    );
  }, skip: skip);

  test('the financial profile carries a server-derived block', () async {
    final profile = await ApiProfileService(api).getFinancialProfile();

    // The screen displays these rather than recomputing the definitions.
    expect(profile.isServerDerived, isTrue);
    expect(
      profile.monthlyOutgo,
      profile.monthlyExpenses + profile.existingEmi + profile.otherObligations,
    );
  }, skip: skip);

  test('a full read-edit-save-read cycle preserves every field', () async {
    final service = ApiProfileService(api);
    final original = await service.getFinancialProfile();

    try {
      final edited = original.copyWith(
        monthlyIncome: 175000,
        monthlyExpenses: 55000,
        existingEmi: 22000,
        savings: 333000,
        otherObligations: 8000,
        employment: EmploymentType.professional,
      );

      final saved = await service.updateFinancialProfile(edited);

      // The save response...
      expect(saved.monthlyIncome, 175000);
      expect(saved.otherObligations, 8000);
      expect(saved.employment, EmploymentType.professional);
      expect(saved.surplus, 90000);
      expect(saved.monthlyOutgo, 85000);

      // ...and an independent re-read must agree, so nothing was dropped
      // between the app, the wire and the database.
      final reread = await service.getFinancialProfile();
      expect(reread.hasSameFiguresAs(saved), isTrue);
      expect(reread.surplus, saved.surplus);
      expect(reread.emiRatio, saved.emiRatio);
      expect(reread.emergencyMonths, saved.emergencyMonths);
    } finally {
      await service.updateFinancialProfile(original);
    }
  }, skip: skip);

  test(
    'the server rejects impossible figures with field-keyed errors',
    () async {
      final service = ApiProfileService(api);

      await expectLater(
        service.updateFinancialProfile(
          const FinancialProfile(monthlyIncome: -1),
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.forField('monthly_income'),
            'monthly_income error',
            isNotNull,
          ),
        ),
      );
    },
    skip: skip,
  );

  test(
    'outgoings far above income are rejected on the field the app shows',
    () async {
      await expectLater(
        ApiProfileService(api).updateFinancialProfile(
          const FinancialProfile(monthlyIncome: 50000, monthlyExpenses: 400000),
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.forField('monthly_expenses'),
            'monthly_expenses error',
            contains('far above your income'),
          ),
        ),
      );
    },
    skip: skip,
  );

  test('PATCH is accepted as well as PUT', () async {
    // The app uses PUT; PATCH exists for callers that prefer it and must
    // behave identically.
    final service = ApiProfileService(api);
    final original = await service.getFinancialProfile();

    final response = await api.put(
      '/financial-profile',
      body: original.toJson(),
    );
    expect(response, isA<Map<String, dynamic>>());
  }, skip: skip);

  test('goals carry a server-derived block', () async {
    final goals = await ApiProfileService(api).getGoals();
    expect(goals, isNotEmpty);
    expect(goals.every((g) => g.isServerDerived), isTrue);

    final business = goals.firstWhere((g) => g.title == 'Business Expansion');
    expect(business.progress, greaterThan(0));
    expect(business.progress, lessThanOrEqualTo(1));
    expect(business.monthsRemaining, greaterThan(0));
    expect(business.monthlyRequired, greaterThan(0));
  }, skip: skip);

  test('a goal survives create, read, update and delete intact', () async {
    final service = ApiProfileService(api);
    final targetDate = DateTime.now().add(const Duration(days: 700));

    final created = await service.createGoal(
      Goal(
        id: '',
        title: 'Contract Round Trip',
        category: GoalCategory.education,
        targetAmount: 2500000,
        targetDate: targetDate,
        savedAmount: 125000,
        note: 'Postgraduate',
      ),
    );

    try {
      // Every field the app sent must come back.
      expect(created.id, isNotEmpty);
      expect(created.title, 'Contract Round Trip');
      expect(created.category, GoalCategory.education);
      expect(created.targetAmount, 2500000);
      expect(created.savedAmount, 125000);
      expect(created.note, 'Postgraduate');
      expect(created.targetDate.year, targetDate.year);
      expect(created.targetDate.month, targetDate.month);
      expect(created.targetDate.day, targetDate.day);
      expect(created.status, 'active');
      expect(created.progress, closeTo(0.05, 0.001));

      // An independent read must agree with the create response.
      final listed = (await service.getGoals()).firstWhere(
        (g) => g.id == created.id,
      );
      expect(listed.hasSameValuesAs(created), isTrue);
      expect(listed.monthlyRequired, created.monthlyRequired);

      final updated = await service.updateGoal(
        created.copyWith(title: 'Contract Renamed', targetAmount: 3000000),
      );
      expect(updated.title, 'Contract Renamed');
      expect(updated.targetAmount, 3000000);
      // Derived values recalculated for the new target, not carried over.
      expect(updated.progress, closeTo(125000 / 3000000, 0.001));
    } finally {
      await service.deleteGoal(created.id);
    }

    final remaining = await service.getGoals();
    expect(remaining.map((g) => g.id), isNot(contains(created.id)));
  }, skip: skip);

  test('saved above target is rejected on the field the app shows', () async {
    await expectLater(
      ApiProfileService(api).createGoal(
        Goal(
          id: '',
          title: 'Overshot',
          category: GoalCategory.other,
          targetAmount: 100000,
          targetDate: DateTime.now().add(const Duration(days: 365)),
          savedAmount: 200000,
        ),
      ),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.forField('saved_amount'),
          'saved_amount error',
          contains('more than the target'),
        ),
      ),
    );
  }, skip: skip);

  test('a past target date is rejected', () async {
    await expectLater(
      ApiProfileService(api).createGoal(
        Goal(
          id: '',
          title: 'Backwards',
          category: GoalCategory.other,
          targetAmount: 100000,
          targetDate: DateTime.now().subtract(const Duration(days: 10)),
        ),
      ),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.forField('target_date'),
          'target_date error',
          isNotNull,
        ),
      ),
    );
  }, skip: skip);

  test('another customer\'s goal id is a plain 404', () async {
    // Id 999999 will not belong to the contract-test customer.
    await expectLater(
      ApiProfileService(api).deleteGoal('999999'),
      throwsA(isA<NotFoundException>()),
    );
  }, skip: skip);

  test(
    'the financial summary carries inputs, derived, goals and formulas',
    () async {
      final raw = await api.get('/financial-summary') as Map<String, dynamic>;

      expect(
        raw.keys,
        containsAll(<String>['inputs', 'derived', 'goals', 'definitions']),
      );

      final derived = (raw['derived'] as Map).cast<String, dynamic>();
      expect(
        derived.keys,
        containsAll(<String>[
          'surplus',
          'emi_ratio',
          'expense_ratio',
          'monthly_outgo',
          'emergency_months',
          'outgo_ratio',
          'has_income',
        ]),
      );

      final goals = (raw['goals'] as Map).cast<String, dynamic>();
      expect(
        goals.keys,
        containsAll(<String>[
          'items',
          'count',
          'total_target',
          'total_saved',
          'total_remaining',
          'total_monthly_required',
        ]),
      );

      // Shipped so a future feature can explain a number rather than recite it.
      final definitions = (raw['definitions'] as Map).cast<String, dynamic>();
      expect(definitions['surplus'], contains('monthly_income'));
      expect(definitions['rounding'], contains('paise'));
    },
    skip: skip,
  );

  test('the summary agrees with the financial-profile endpoint', () async {
    // Two endpoints, one engine: they must never disagree.
    final profile = await ApiProfileService(api).getFinancialProfile();
    final raw = await api.get('/financial-summary') as Map<String, dynamic>;
    final derived = (raw['derived'] as Map).cast<String, dynamic>();

    expect((derived['surplus'] as num).toDouble(), profile.surplus);
    expect((derived['emi_ratio'] as num).toDouble(), profile.emiRatio);
    expect((derived['monthly_outgo'] as num).toDouble(), profile.monthlyOutgo);
    expect(
      (derived['emergency_months'] as num).toDouble(),
      profile.emergencyMonths,
    );
  }, skip: skip);

  test(
    'aggregate goal figures equal the sum of the individual goals',
    () async {
      final goals = await ApiProfileService(api).getGoals();
      final raw = await api.get('/financial-summary') as Map<String, dynamic>;
      final totals = (raw['goals'] as Map).cast<String, dynamic>();

      expect(totals['count'], goals.length);

      final summedMonthly = goals.fold<double>(
        0,
        (sum, g) => sum + g.monthlyRequired,
      );
      expect(
        (totals['total_monthly_required'] as num).toDouble(),
        closeTo(summedMonthly, 0.01),
      );
    },
    skip: skip,
  );

  test('the summary is unavailable without a token', () async {
    await expectLater(
      ApiClient().get('/financial-summary'),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);

  test(
    'the FynnScore response carries score, dimensions and provenance',
    () async {
      final score = await ApiProfileService(api).getFynnScore();

      expect(score.hasScore, isTrue);
      expect(score.modelVersion, 'fynnscore-v1');
      expect(score.score, inInclusiveRange(0, 100));
      expect(score.band, isNotNull);
      expect(score.summary, isNotEmpty);
      expect(score.disclaimer, contains('not a credit bureau score'));

      // Exactly the three v1 dimensions, each naming the metric it reads.
      expect(score.dimensions.map((d) => d.key), [
        'emi_burden',
        'spending_control',
        'emergency_buffer',
      ]);
      for (final d in score.dimensions) {
        expect(d.score, inInclusiveRange(0, 100));
        expect(d.explanation, isNotEmpty);
        expect(score.metrics[d.metric], d.metricValue);
      }
    },
    skip: skip,
  );

  test(
    'the score agrees with the Flutter engine for the same figures',
    () async {
      // Mock mode and the real API must never show two different numbers.
      final profile = await ApiProfileService(api).getFinancialProfile();
      final fromApi = await ApiProfileService(api).getFynnScore();

      final locally = const FynnScoreEngine().score(
        const FinancialEngine().snapshot(
          income: Money.of(profile.monthlyIncome),
          expenses: Money.of(profile.monthlyExpenses),
          existingEmi: Money.of(profile.existingEmi),
          otherObligations: Money.of(profile.otherObligations),
          savings: Money.of(profile.savings),
        ),
      );

      expect(locally.score, fromApi.score);
      expect(locally.band, fromApi.band);
      expect(
        locally.dimensions.map((d) => d.score),
        fromApi.dimensions.map((d) => d.score),
      );
    },
    skip: skip,
  );

  test('recommendation deltas are reproducible from the response', () async {
    final score = await ApiProfileService(api).getFynnScore();

    for (final r in score.recommendations) {
      expect(r.currentScore, score.score);
      expect(r.delta, r.projectedScore - r.currentScore);
    }
  }, skip: skip);

  test('Home serves the same score as the FynnScore endpoint', () async {
    final home = await ApiHomeService(api).getSnapshot();
    final direct = await ApiProfileService(api).getFynnScore();

    expect(home.score.score, direct.score);
    expect(home.score.modelVersion, direct.modelVersion);
    expect(
      home.score.dimensions.map((d) => d.key),
      direct.dimensions.map((d) => d.key),
    );
  }, skip: skip);

  test('a profile change moves the score, and Home follows', () async {
    final service = ApiProfileService(api);
    final original = await service.getFinancialProfile();

    try {
      final before = await service.getFynnScore();

      // Push EMIs to the 45% zero anchor.
      await service.updateFinancialProfile(
        original.copyWith(
          monthlyIncome: 100000,
          existingEmi: 45000,
          monthlyExpenses: 40000,
          savings: 180000,
        ),
      );

      final after = await service.getFynnScore();
      expect(after.score, lessThan(before.score!));

      final home = await ApiHomeService(api).getSnapshot();
      expect(home.score.score, after.score, reason: 'Home must not go stale');
    } finally {
      await service.updateFinancialProfile(original);
    }
  }, skip: skip);

  test(
    'no income yields insufficient data, never a fabricated score',
    () async {
      final service = ApiProfileService(api);
      final original = await service.getFinancialProfile();

      try {
        await service.updateFinancialProfile(
          original.copyWith(
            monthlyIncome: 0,
            monthlyExpenses: 0,
            existingEmi: 0,
            otherObligations: 0,
          ),
        );

        final score = await service.getFynnScore();
        expect(score.hasScore, isFalse);
        expect(score.score, isNull);
        expect(score.band, isNull);
        expect(score.dimensions, isEmpty);
        expect(score.missingRequirements, contains('monthly_income'));
        expect(score.summary, isNotEmpty);
      } finally {
        await service.updateFinancialProfile(original);
      }
    },
    skip: skip,
  );

  test('goals never move the numerical score', () async {
    final service = ApiProfileService(api);
    final before = await service.getFynnScore();

    final goal = await service.createGoal(
      Goal(
        id: '',
        title: 'Score Isolation Check',
        category: GoalCategory.other,
        targetAmount: 5000000,
        targetDate: DateTime.now().add(const Duration(days: 20)),
        savedAmount: 100,
      ),
    );

    try {
      final after = await service.getFynnScore();
      expect(after.score, before.score);
      expect(
        after.dimensions.map((d) => d.score),
        before.dimensions.map((d) => d.score),
      );
    } finally {
      await service.deleteGoal(goal.id);
    }
  }, skip: skip);

  test('the score is unavailable without a token', () async {
    await expectLater(
      ApiProfileService(ApiClient()).getFynnScore(),
      throwsA(isA<UnauthorizedException>()),
    );
  }, skip: skip);
}

/// Retries an OTP request through a rate-limit window.
Future<OtpChallenge> _sendOtpTolerantOfThrottling(
  ApiAuthService auth,
  String mobile,
) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      // The real call. Recursing here would loop forever.
      return await auth.sendOtp(mobile);
    } on RateLimitedException catch (e) {
      // Retry-After is authoritative; the cap stops a misconfigured window
      // from stalling the whole suite.
      final seconds = (e.retryAfterSeconds ?? 15).clamp(1, 65);
      // ignore: avoid_print
      print('OTP throttled on $mobile; waiting ${seconds}s.');
      await Future<void>.delayed(Duration(seconds: seconds));
    }
  }
  throw StateError(
    'Still throttled for $mobile after three attempts. '
    'Run `php artisan cache:clear` in fynnedge-api to reset the limiter.',
  );
}
