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
}
