import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/services/api_config.dart';
import 'data/services/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /*
   * A release build that was never configured does not start.
   *
   * `flutter build apk --release` with no --dart-define produces a release
   * artifact on sample data pointed at a local plaintext address, and that
   * is precisely the build somebody uploads in a hurry. Failing here is
   * loud, immediate and names the missing flag; the alternative is a
   * customer being shown six fictional lenders that look entirely real.
   *
   * Debug and profile builds are untouched: running the checkout against a
   * local API without editing a file is the point of those defaults.
   */
  final misconfigured = ApiConfig.releaseConfigurationError();

  if (misconfigured != null) {
    throw StateError(misconfigured);
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final store = await LocalStore.open();

  runApp(
    ProviderScope(
      retry: noAutoRetry,
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const FynnEdgeApp(),
    ),
  );
}
