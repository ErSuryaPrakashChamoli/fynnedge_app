import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'router.dart';
import 'routes.dart';
import 'session.dart';
import 'theme/app_theme.dart';

class FynnEdgeApp extends ConsumerWidget {
  const FynnEdgeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SystemChrome.setSystemUIOverlayStyle(AppTheme.overlay);

    final router = ref.watch(routerProvider);

    // One place handles an expired session, however deep in the app it
    // surfaced: clear local state, then send the customer to Welcome.
    ref.listen(sessionExpiredProvider, (previous, next) async {
      if (previous == null || next <= previous) return;
      await ref.read(sessionProvider.notifier).expire();
      router.go(Routes.welcome);
    });

    return MaterialApp.router(
      title: 'FynnEdge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
      builder: (context, child) =>
          MediaQuery.withNoTextScaling(child: child ?? const SizedBox.shrink()),
    );
  }
}
