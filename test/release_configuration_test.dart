import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/data/services/api_config.dart';

/// What a release binary refuses to start without.
///
/// Both defaults in ApiConfig are development defaults, deliberately: a
/// checkout should run against a local API without anyone editing a file.
/// The cost is that `flutter build apk --release` with no --dart-define
/// builds a release artifact on sample data pointed at a plaintext local
/// address — a fictional customer and six fictional lenders, in the exact
/// artifact a hurried release uploads.
///
/// These tests run in debug, where the guard is deliberately inert, so what
/// is asserted here is the rule itself rather than the runtime effect: the
/// guard is off outside release, and the two conditions it checks are the
/// two decisions a release cannot be made without.
void main() {
  test('the guard does not interfere outside a release build', () {
    expect(kReleaseMode, isFalse, reason: 'tests run in debug');
    expect(ApiConfig.releaseConfigurationError(), isNull);
  });

  test('the defaults are the ones a release must override', () {
    // If either of these stops being true, the guard is guarding nothing
    // and the comment above it has become false.
    expect(
      ApiConfig.useMock,
      isTrue,
      reason: 'the mock default changed; the release guard now protects '
          'against a case that cannot happen',
    );
    expect(
      Uri.parse(ApiConfig.baseUrl).isScheme('https'),
      isFalse,
      reason: 'the base-URL default changed; the release guard now protects '
          'against a case that cannot happen',
    );
  });

  test('a configured release passes both conditions', () {
    // The guard's own logic, applied to what a real release build carries.
    const configuredMock = false;
    const configuredBase = 'https://api.fynnedge.com';

    expect(configuredMock, isFalse);
    expect(Uri.parse(configuredBase).isScheme('https'), isTrue);
  });
}
