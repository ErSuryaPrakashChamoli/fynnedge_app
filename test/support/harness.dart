import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/app.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/app/theme/app_theme.dart';
import 'package:fynnedge/core/utils/clock.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/application.dart';
import 'package:fynnedge/data/services/application_service.dart';
import 'package:fynnedge/data/services/api_config.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phone-sized canvas so goldens match what ships.
const Size kPhone = Size(420, 900);

/// The device sizes FynnEdge must survive. Small is the one that hurts.
const Size kSmallPhone = Size(360, 640);
const Size kNormalPhone = Size(390, 844);
const Size kLargePhone = Size(430, 932);

/// A taller-than-real canvas, so a long screen fits into one golden instead
/// of being reviewed a third at a time.
const Size kTallPhone = Size(420, 2400);

/// A fixed instant so greetings, relative timestamps and mock data dates do
/// not drift with the wall clock. Mid-morning on a weekday.
final DateTime kTestNow = DateTime(2026, 9, 5, 10, 30);

/// Registers the bundled Manrope faces so rendered screens use real type
/// instead of the test framework's placeholder font.
/// For suites that do not render widgets: freezes the clock only, so there is
/// no dependency on the widget binding or the asset bundle.
void initUnitTestEnvironment() {
  AppClock.freeze(kTestNow);
  ApiConfig.simulateLatency = false;
}

/// Call from setUpAll in every suite that renders UI.
Future<void> initTestEnvironment() async {
  AppClock.freeze(kTestNow);

  // The mock services' artificial delay is a demo device. Left on, a test
  // that seeds data before pumping waits on a timer that fake time will
  // never advance.
  ApiConfig.simulateLatency = false;

  await loadAppFonts();
}

Future<void> loadAppFonts() async {
  final loader = FontLoader('Manrope');
  for (final weight in [400, 500, 600, 700, 800]) {
    loader.addFont(rootBundle.load('assets/fonts/Manrope-$weight.ttf'));
  }
  await loader.load();

  // Icons ship with the SDK rather than the app bundle, so goldens would
  // otherwise show empty boxes wherever the UI uses an Icon.
  final iconFile = File(
    '${Platform.environment['FLUTTER_ROOT'] ?? _flutterRoot()}'
    '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (iconFile.existsSync()) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(iconFile.readAsBytesSync().buffer.asByteData()));
    await icons.load();
  }
}

/// Derives the SDK root from the running Dart executable when FLUTTER_ROOT
/// is not exported (the usual case under `flutter test`).
String _flutterRoot() {
  final dart = File(Platform.resolvedExecutable).parent.path;
  return Directory(dart).parent.parent.path;
}

/// Wraps a screen in the same theme + provider graph the real app uses.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  Size size = kPhone,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      // The same retry policy the app ships with, so a test sees the error
      // state a customer would see rather than an endless spinner.
      retry: noAutoRetry,
      overrides: [localStoreProvider.overrideWithValue(store), ...overrides],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: screen,
        builder: (context, child) {
          final wrapped = MediaQuery.withNoTextScaling(
            child: child ?? const SizedBox.shrink(),
          );
          if (viewInsets == EdgeInsets.zero) return wrapped;
          // Simulates a raised software keyboard.
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(viewInsets: viewInsets),
            child: wrapped,
          );
        },
      ),
    ),
  );
}

/// Advances animations frame by frame. A single large pump would jump past
/// delayed callbacks without ever rendering the frames they trigger, and
/// pumpAndSettle never returns because several screens animate on a loop.
/// The default covers mock latency (~420ms) plus the longest entrance
/// animation (~1100ms), so counters land on their final value.
Future<void> settle(
  WidgetTester tester, [
  Duration d = const Duration(milliseconds: 2200),
]) async {
  const frame = Duration(milliseconds: 32);
  final frames = d.inMilliseconds ~/ frame.inMilliseconds;
  await tester.pump();
  for (var i = 0; i < frames; i++) {
    await tester.pump(frame);
  }
}

/// Mounts the whole app, router included. Use for screens that navigate on a
/// timer or that need real route transitions.
Future<void> pumpApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Size size = kPhone,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      retry: noAutoRetry,
      overrides: [localStoreProvider.overrideWithValue(store), ...overrides],
      child: const FynnEdgeApp(),
    ),
  );
}

/// Captures a golden for [type] under a stable file name.
Future<void> golden(WidgetTester tester, Type type, String name) async {
  await expectLater(find.byType(type), matchesGoldenFile('goldens/$name.png'));
}

/// Declares a render-and-capture test for one screen. Building without
/// throwing is itself the assertion — a screen that overflows or reads a
/// missing provider fails here.
void screenTest(
  String name,
  Widget Function() build,
  Type type, {

  /// Runs before the screen is pumped, for screens whose content only exists
  /// once the customer has done something.
  Future<void> Function()? setUp,
}) {
  testWidgets(name.replaceAll('_', ' '), (tester) async {
    await setUp?.call();
    await pumpScreen(tester, build());
    await settle(tester);
    await golden(tester, type, name);
  });
}

/// Creates one application the way the app creates one, for screens that
/// have nothing to show until the customer has applied for something.
///
/// Returns the application so a caller can assert against its real figures
/// rather than against numbers written into a test.
Future<LoanApplication> seedApplication({
  String productId = 'prod_bl_b',
  double amount = 1000000,
  int tenureMonths = 60,
  bool submit = false,
}) async {
  MockStore.instance.reset();
  final service = MockApplicationService();

  final application = await service.create(
    ApplicationDraft(
      productId: productId,
      amount: amount,
      tenureMonths: tenureMonths,
    ),
    idempotencyKey: 'seed-$productId-$amount-$tenureMonths',
  );

  return submit ? service.submit(application.id) : application;
}
