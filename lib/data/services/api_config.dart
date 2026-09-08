import 'package:flutter/foundation.dart';

/// Single switch that decides where every repository gets its data.
///
/// To go live against the real backend:
///   flutter run --dart-define=FYNN_USE_MOCK=false \
///               --dart-define=FYNN_API_BASE=https://api.fynnedge.com
///
/// No UI or controller code changes when this flips.
class ApiConfig {
  const ApiConfig._();

  static const bool useMock = bool.fromEnvironment(
    'FYNN_USE_MOCK',
    defaultValue: true,
  );

  static const String baseUrl = String.fromEnvironment(
    'FYNN_API_BASE',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const String apiPrefix = '/api/v1';

  /// How long a single request may take before it is treated as a network
  /// failure. Deliberately short: a customer staring at a spinner is worse
  /// than a clear "try again".
  static const Duration timeout = Duration(seconds: 20);

  /// Artificial latency for mock services so loading states are real.
  ///
  /// It exists to make the prototype feel like a network, which is a
  /// property of the demo rather than of any behaviour worth testing. A test
  /// that needs a loading state gives its own fake a delay instead.
  static bool simulateLatency = true;

  static Duration get mockLatency =>
      simulateLatency ? const Duration(milliseconds: 420) : Duration.zero;

  static Duration get mockFastLatency =>
      simulateLatency ? const Duration(milliseconds: 180) : Duration.zero;

  /// The pause a mock service takes before answering.
  ///
  /// With latency off this schedules no timer at all — it completes on the
  /// microtask queue. A zero-duration `Future.delayed` would still create a
  /// timer, and inside a widget test fake time does not advance until the
  /// tree is pumped, so anything awaiting one before the first pump waits
  /// forever.
  static Future<void> pause() => _pause(mockLatency);

  static Future<void> pauseFast() => _pause(mockFastLatency);

  static Future<void> _pause(Duration delay) async {
    if (delay == Duration.zero) return;
    await Future<void>.delayed(delay);
  }

  static Uri uri(String path, [Map<String, dynamic>? query]) => Uri.parse(
    '$baseUrl$apiPrefix$path',
  ).replace(queryParameters: query?.map((k, v) => MapEntry(k, v.toString())));

  /// Why a release build must not start, or null when it may.
  ///
  /// Both defaults here are development defaults, and they have to be: a
  /// checkout should run against a local API without anyone editing a file.
  /// The consequence is that `flutter build apk --release` with no
  /// --dart-define produces a *release* artifact running entirely on mock
  /// data — a fictional customer, six fictional lenders and a score
  /// calculated from invented figures — and that is exactly the build a
  /// hurried release would upload.
  ///
  /// So a release binary refuses to run unless the two decisions have been
  /// made. It is the same choice LogOtpSender makes on the server: a build
  /// that reaches production without being configured should fail loudly
  /// rather than quietly hand out something that looks real.
  ///
  /// Checked at startup rather than at compile time because Dart cannot
  /// fail a build on a const value; the failure is as early as it can be,
  /// and it names what is missing.
  static String? releaseConfigurationError() {
    if (!kReleaseMode) return null;

    if (useMock) {
      return 'This release build is running on sample data. Build with '
          '--dart-define=FYNN_USE_MOCK=false.';
    }

    if (!Uri.parse(baseUrl).isScheme('https')) {
      return 'This release build would send customer data to $baseUrl over '
          'an unencrypted connection. Build with '
          '--dart-define=FYNN_API_BASE=https://...';
    }

    return null;
  }
}
