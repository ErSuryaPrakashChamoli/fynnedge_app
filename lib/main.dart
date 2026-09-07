import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/services/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
