/// Defensive readers for JSON coming off the wire.
///
/// A backend is allowed to omit an optional field, send `null`, return `[]`
/// where an object was expected (PHP does this for empty associative arrays),
/// or serialise a number as a string. None of that should take down a screen,
/// so every model reads through these instead of casting directly.
class J {
  const J._();

  static Map<String, dynamic> map(Object? value) =>
      value is Map<String, dynamic>
      ? value
      : value is Map
      ? value.map((k, v) => MapEntry(k.toString(), v))
      : const {};

  static List<Object?> list(Object? value) => value is List ? value : const [];

  /// Maps a list of JSON objects, skipping anything that is not an object.
  static List<T> objects<T>(
    Object? value,
    T Function(Map<String, dynamic>) parse,
  ) => list(value).whereType<Map>().map((e) => parse(map(e))).toList();

  static List<String> strings(Object? value) =>
      list(value).where((e) => e != null).map((e) => e.toString()).toList();

  static String str(Object? value, [String fallback = '']) =>
      value == null ? fallback : value.toString();

  static String? strOrNull(Object? value) {
    if (value == null) return null;
    final s = value.toString();
    return s.isEmpty ? null : s;
  }

  static double dbl(Object? value, [double fallback = 0]) => switch (value) {
    num n => n.toDouble(),
    String s => double.tryParse(s) ?? fallback,
    _ => fallback,
  };

  static double? dblOrNull(Object? value) => switch (value) {
    num n => n.toDouble(),
    String s => double.tryParse(s),
    _ => null,
  };

  static int integer(Object? value, [int fallback = 0]) => switch (value) {
    num n => n.toInt(),
    String s => int.tryParse(s) ?? fallback,
    _ => fallback,
  };

  static int? intOrNull(Object? value) => switch (value) {
    num n => n.toInt(),
    String s => int.tryParse(s),
    _ => null,
  };

  /// Accepts real booleans plus the 1/0 and "true"/"false" a JSON API may send.
  static bool boolean(Object? value) => switch (value) {
    bool b => b,
    num n => n != 0,
    String s => s == 'true' || s == '1',
    _ => false,
  };

  static DateTime? date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  /// A string map, tolerating `[]` from PHP and null members.
  static Map<String, String> stringMap(Object? value) => value is Map
      ? value.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
      : const {};

  /// Looks up an enum-like value by id with a guaranteed fallback.
  static T enumById<T>(
    Iterable<T> values,
    String? id,
    String Function(T) idOf,
    T fallback,
  ) {
    if (id == null) return fallback;
    for (final v in values) {
      if (idOf(v) == id) return v;
    }
    return fallback;
  }
}
