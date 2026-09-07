import 'package:flutter/foundation.dart';

/// The one source of "now" in FynnEdge.
///
/// Anything the customer *sees* that depends on the current time — greetings,
/// relative timestamps, mock data dates — must read it from here. Calling
/// `DateTime.now()` directly makes screens untestable and golden images drift
/// with the wall clock.
///
/// Ids and cache keys may still use `DateTime.now()`; they are never rendered.
class AppClock {
  const AppClock._();

  static DateTime Function() _source = DateTime.now;

  static DateTime now() => _source();

  /// Pins the clock so tests are deterministic.
  @visibleForTesting
  static void freeze(DateTime at) => _source = () => at;

  @visibleForTesting
  static void unfreeze() => _source = DateTime.now;
}
