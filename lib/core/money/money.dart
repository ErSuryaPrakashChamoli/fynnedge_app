/// An exact rupee amount, held as an integer number of paise.
///
/// Money is never a double in FynnEdge. 0.1 + 0.2 is not 0.3 in binary
/// floating point, and a customer who sees their surplus drift by a paisa
/// stops trusting every other number on the screen.
///
/// This mirrors App\Domain\Money on the backend field for field, so both
/// engines produce identical results. A committed fixture
/// (test/fixtures/financial_parity.json) proves they still do.
///
/// Rounding happens only where this class says it does: division rounds half
/// away from zero, to the nearest paise. Everything else is exact.
extension type const Money._(int paise) {
  static const Money zero = Money._(0);

  const Money.fromPaise(this.paise);

  /// Parses "100000.55" without ever constructing a double.
  factory Money.fromDecimalString(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return zero;

    final match = RegExp(r'^(-?)(\d+)(?:\.(\d*))?$').firstMatch(trimmed);
    if (match == null) {
      throw FormatException('Not a decimal amount: $value');
    }

    final negative = match.group(1) == '-';
    final whole = int.parse(match.group(2)!);
    // Pad or truncate to three digits so the third can drive half-up
    // rounding, exactly as the backend does.
    final fraction = (match.group(3) ?? '').padRight(3, '0').substring(0, 3);

    var paise = whole * 100 + int.parse(fraction.substring(0, 2));
    if (int.parse(fraction[2]) >= 5) paise++;

    return Money._(negative ? -paise : paise);
  }

  /// Accepts whatever arrives from JSON or a form: an int, a double that
  /// came off the wire, or a decimal string.
  factory Money.of(Object? value) {
    if (value == null) return zero;
    if (value is int) return Money._(value * 100);
    if (value is double) {
      // Convert through decimal text rather than multiplying, so 0.29 does
      // not land on 28 paise.
      return Money.fromDecimalString(value.toStringAsFixed(2));
    }
    if (value is String) return Money.fromDecimalString(value);
    throw ArgumentError('Cannot read money from $value');
  }

  Money operator +(Money other) => Money._(paise + other.paise);

  Money operator -(Money other) => Money._(paise - other.paise);

  Money times(int factor) => Money._(paise * factor);

  /// Rounds half away from zero, to the nearest paise.
  Money dividedBy(int divisor) => Money._(divideHalfUp(paise, divisor));

  bool get isZero => paise == 0;

  bool get isPositive => paise > 0;

  bool get isNegative => paise < 0;

  /// Never below zero — used where a negative shortfall is meaningless.
  Money get clampedToZero => paise < 0 ? zero : this;

  /// The rupee value for display and for the API. This is the one place a
  /// double appears, after all arithmetic is finished.
  double get rupees => paise / 100;

  /// Indian digit grouping — ₹3,00,000 rather than ₹300,000.
  ///
  /// Mirrors Money::toIndianString on the server, so a figure quoted by an
  /// engine and the same figure quoted on a screen are grouped identically.
  String toIndianString() {
    final whole = divideHalfUp(paise, 100).abs().toString();
    if (whole.length <= 3) return '₹$whole';

    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final parts = <String>[];

    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);

    return '₹${parts.join(',')},$last3';
  }

  /// "100000.55" — the exact value.
  String toDecimalString() {
    final sign = paise < 0 ? '-' : '';
    final abs = paise.abs();
    return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }

  /// Integer division rounding half away from zero.
  ///
  /// Written out rather than using round(), which goes through a double and
  /// would reintroduce exactly the imprecision this type exists to avoid.
  static int divideHalfUp(int numerator, int denominator) {
    if (denominator == 0) {
      throw ArgumentError('Division by zero');
    }

    final negative = (numerator < 0) != (denominator < 0);
    final n = numerator.abs();
    final d = denominator.abs();
    final result = (2 * n + d) ~/ (2 * d);

    return negative ? -result : result;
  }
}

/// A percentage or multiple held to two decimal places, as an integer number
/// of hundredths — the same reasoning as Money.
extension type const Ratio._(int hundredths) {
  static const Ratio zero = Ratio._(0);

  /// part / whole as a percentage. A zero or negative whole yields zero:
  /// "what share of no income is this EMI" has no meaningful answer.
  factory Ratio.percentOf(Money part, Money whole) {
    if (whole.paise <= 0) return zero;
    return Ratio._(Money.divideHalfUp(part.paise * 10000, whole.paise));
  }

  /// A percentage already computed elsewhere — parsing a server value, not
  /// deriving a new one.
  factory Ratio.ofPercent(double percent) =>
      Ratio._((percent * 100).round());

  /// How many times [unit] fits into [total], to two decimals.
  factory Ratio.timesOver(Money total, Money unit) {
    if (unit.paise <= 0) return zero;
    return Ratio._(Money.divideHalfUp(total.paise * 100, unit.paise));
  }

  double get value => hundredths / 100;
}
