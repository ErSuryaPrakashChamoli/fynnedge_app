import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/home_repository.dart';
import '../data/repositories/application_documents_repository.dart';
import '../data/repositories/credit_repository.dart';
import '../data/repositories/kyc_repository.dart';
import '../data/repositories/scan_repository.dart';
import '../data/repositories/submission_repository.dart';
import '../data/repositories/misc_repositories.dart';
import '../data/repositories/profile_repository.dart';
import '../data/services/ai_service.dart';
import '../data/services/api_client.dart';
import '../data/services/application_documents_service.dart';
import '../data/services/api_config.dart';
import '../data/services/application_service.dart';
import '../data/services/auth_service.dart';
import '../data/services/catalog_service.dart';
import '../data/services/consent_service.dart';
import '../data/services/credit_service.dart';
import '../data/services/document_picker.dart';
import '../data/services/twin_service.dart';
import '../data/services/document_scan_service.dart';
import '../data/services/document_service.dart';
import '../data/services/finance_service.dart';
import '../data/services/home_service.dart';
import '../data/services/kyc_service.dart';
import '../data/services/local_store.dart';
import '../data/services/match_service.dart';
import '../data/services/notification_service.dart';
import '../data/services/profile_service.dart';
import '../data/services/submission_service.dart';

// ---------------------------------------------------------------------------
// THE SWAP POINT
//
// Every mock/real decision in FynnEdge is made in this file and nowhere else.
// Each service provider is a single ternary on ApiConfig.useMock. No screen,
// controller or repository knows which side it got.
// ---------------------------------------------------------------------------

/// How a failed provider behaves.
///
/// Riverpod retries a failing provider on its own, with backoff. That turns
/// an offline customer into someone watching a spinner: the screen's error
/// state, and the "Try again" button on it, are never reached because the
/// provider never settles on an error. FynnEdge surfaces the failure
/// instead — every loading screen already offers an explicit retry.
Duration? noAutoRetry(int retryCount, Object error) => null;

/// Overridden in main() once SharedPreferences has loaded.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider must be overridden'),
);

/// Raised whenever the server rejects our token, from anywhere in the app.
/// The router listens and sends the customer back to Welcome.
final sessionExpiredProvider = NotifierProvider<SessionExpiredNotifier, int>(
  SessionExpiredNotifier.new,
);

class SessionExpiredNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// A counter rather than a bool: two expiries in a row must both notify.
  void signal() => state = state + 1;
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    onUnauthorized: () => ref.read(sessionExpiredProvider.notifier).signal(),
  )..setToken(ref.watch(localStoreProvider).token);
  ref.onDispose(client.close);
  return client;
});

final financeServiceProvider = Provider<FinanceService>(
  (ref) => const FinanceService(),
);

// --------------------------------------------------------------- services
final authServiceProvider = Provider<AuthService>(
  (ref) => ApiConfig.useMock
      ? MockAuthService()
      : ApiAuthService(ref.watch(apiClientProvider)),
);

final profileServiceProvider = Provider<ProfileService>(
  (ref) => ApiConfig.useMock
      ? MockProfileService()
      : ApiProfileService(ref.watch(apiClientProvider)),
);

final homeServiceProvider = Provider<HomeService>(
  (ref) => ApiConfig.useMock
      ? const MockHomeService()
      : ApiHomeService(ref.watch(apiClientProvider)),
);

final catalogServiceProvider = Provider<CatalogService>(
  (ref) => ApiConfig.useMock
      ? const MockCatalogService()
      : ApiCatalogService(ref.watch(apiClientProvider)),
);

/// FynnMatch. In mock mode the same engine runs locally over the same
/// customer, so the two modes cannot disagree about a product.
final matchServiceProvider = Provider<MatchService>(
  (ref) => ApiConfig.useMock
      ? MockMatchService()
      : ApiMatchService(ref.watch(apiClientProvider)),
);

/// FynnTwin. Both sides run the same deterministic engine, so a projection
/// shown while the customer types matches the one the server returns.
final twinServiceProvider = Provider<TwinService>(
  (ref) => ApiConfig.useMock
      ? MockTwinService()
      : ApiTwinService(ref.watch(apiClientProvider)),
);

/// Device file selection. Platform code lives behind this and nowhere else,
/// so tests and mock mode swap it like any other service.
final documentPickerProvider = Provider<DocumentPicker>(
  (ref) => const PlatformDocumentPicker(),
);

/// FynnScan. Both sides report the same thing today — that no
/// document-understanding provider is connected.
final documentScanServiceProvider = Provider<DocumentScanService>(
  (ref) => ApiConfig.useMock
      ? const MockDocumentScanService()
      : ApiDocumentScanService(ref.watch(apiClientProvider)),
);

/// Privacy and consent. The same catalogue on both sides, including which
/// entries are not on offer yet.
final consentServiceProvider = Provider<ConsentService>(
  (ref) => ApiConfig.useMock
      ? MockConsentService()
      : ApiConsentService(ref.watch(apiClientProvider)),
);

/// Credit information. NO LIVE BUREAU IS CONNECTED: the mock reports that
/// no bureau exists, and the API's own default driver is `none`.
final creditServiceProvider = Provider<CreditService>(
  (ref) => ApiConfig.useMock
      ? const MockCreditService()
      : ApiCreditService(ref.watch(apiClientProvider)),
);

final applicationServiceProvider = Provider<ApplicationService>(
  (ref) => ApiConfig.useMock
      ? MockApplicationService()
      : ApiApplicationService(ref.watch(apiClientProvider)),
);

final documentServiceProvider = Provider<DocumentService>(
  (ref) => ApiConfig.useMock
      ? MockDocumentService()
      : ApiDocumentService(ref.watch(apiClientProvider)),
);

final aiServiceProvider = Provider<AiService>(
  (ref) => ApiConfig.useMock
      ? MockAiService()
      : ApiAiService(ref.watch(apiClientProvider)),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => ApiConfig.useMock
      ? MockNotificationService()
      : ApiNotificationService(ref.watch(apiClientProvider)),
);

// ----------------------------------------------------------- repositories
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(authServiceProvider),
    ref.watch(localStoreProvider),
    ref.watch(apiClientProvider),
  ),
);

/// Identity verification. NO LIVE KYC PROVIDER IS CONNECTED: the mock
/// reports that none exists, and the API's own default driver is `none`.
/// External submission. NO LIVE PROVIDER IS CONNECTED: the mock reports that
/// none exists, and the API's own default driver is `none`.
/// Preparing an application's documents. Nothing in this seam sends anything
/// anywhere; external submission is its own boundary below.
final applicationDocumentsServiceProvider =
    Provider<ApplicationDocumentsService>(
      (ref) => ApiConfig.useMock
          ? MockApplicationDocumentsService()
          : ApiApplicationDocumentsService(ref.watch(apiClientProvider)),
    );

final applicationDocumentsRepositoryProvider =
    Provider<ApplicationDocumentsRepository>(
      (ref) => ApplicationDocumentsRepository(
        ref.watch(applicationDocumentsServiceProvider),
      ),
    );

final submissionServiceProvider = Provider<SubmissionService>(
  (ref) => ApiConfig.useMock
      ? const MockSubmissionService()
      : ApiSubmissionService(ref.watch(apiClientProvider)),
);

final submissionRepositoryProvider = Provider<SubmissionRepository>(
  (ref) => SubmissionRepository(ref.watch(submissionServiceProvider)),
);

final kycServiceProvider = Provider<KycService>(
  (ref) => ApiConfig.useMock
      ? const MockKycService()
      : ApiKycService(ref.watch(apiClientProvider)),
);

final kycRepositoryProvider = Provider<KycRepository>(
  (ref) => KycRepository(ref.watch(kycServiceProvider)),
);

final scanRepositoryProvider = Provider<ScanRepository>(
  (ref) => ScanRepository(ref.watch(documentScanServiceProvider)),
);

final creditRepositoryProvider = Provider<CreditRepository>(
  (ref) => CreditRepository(ref.watch(creditServiceProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(
    ref.watch(profileServiceProvider),
    ref.watch(localStoreProvider),
  ),
);

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepository(ref.watch(homeServiceProvider)),
);

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DocumentRepository(ref.watch(documentServiceProvider)),
);

final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepository(ref.watch(aiServiceProvider)),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(notificationServiceProvider)),
);
