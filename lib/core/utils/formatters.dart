import 'package:intl/intl.dart';

import 'clock.dart';

/// Indian-format money + number helpers. All currency in the app goes
/// through here so we never scatter ₹ signs and lakh/crore logic around.
class Fmt {
  const Fmt._();

  static final NumberFormat _inr = NumberFormat.decimalPattern('en_IN');

  /// ₹1,00,000, and -₹25,000 rather than ₹-25,000.
  ///
  /// The sign leads the symbol because a negative figure is read as a
  /// shortfall, not as a currency called "minus rupees".
  static String money(num value, {bool symbol = true}) {
    final rounded = value.round();
    final s = _inr.format(rounded.abs());
    final sign = rounded < 0 ? '-' : '';
    return symbol ? '$sign₹$s' : '$sign$s';
  }

  /// ₹10 L / ₹1.2 Cr — for headline figures where precision hurts readability.
  static String compactMoney(num value) {
    final v = value.abs();
    final sign = value < 0 ? '-' : '';
    if (v >= 10000000) {
      return '$sign₹${_trim(v / 10000000)} Cr';
    }
    if (v >= 100000) {
      return '$sign₹${_trim(v / 100000)} L';
    }
    if (v >= 1000) {
      return '$sign₹${_trim(v / 1000)} K';
    }
    return '$sign₹${v.round()}';
  }

  /// "10 lakh" style words, used in conversational copy.
  static String words(num value) {
    if (value >= 10000000) return '${_trim(value / 10000000)} crore';
    if (value >= 100000) return '${_trim(value / 100000)} lakh';
    if (value >= 1000) return '${_trim(value / 1000)} thousand';
    return value.round().toString();
  }

  static String percent(num value, {int decimals = 2}) =>
      '${value.toStringAsFixed(decimals)}%';

  /// A ratio to at most two decimals, trailing zeros trimmed.
  ///
  /// The same shape the engines use inside their own sentences, so a figure
  /// shown in a table and the same figure inside a sentence beside it never
  /// look like two different numbers.
  /// A number to at most two decimals, trailing zeros trimmed.
  ///
  /// The same shape the engines use inside their sentences, so a figure in a
  /// table and the same figure in the text beside it agree.
  static String trimmed(num value) {
    var text = value.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }

  static String ratio(num value) => '${trimmed(value)}%';

  /// How many months of outgoings a savings buffer covers, e.g. "2.53 mo".
  ///
  /// Trimmed to the two decimals the engine's Ratio carries. Screens used to
  /// render this three different ways — 2.5m, 2.5 months and 2.53 mo — so
  /// the same customer saw the same figure at two precisions depending on
  /// which screen they were on.
  static String monthsCovered(num value) => '${trimmed(value)} mo';

  static String months(int m) {
    if (m < 12) return '$m mo';
    final years = m ~/ 12;
    final rem = m % 12;
    return rem == 0 ? '$years yr' : '$years yr $rem mo';
  }

  static String date(DateTime d) => DateFormat('d MMM yyyy').format(d);

  static String shortDate(DateTime d) => DateFormat('d MMM').format(d);

  static String relative(DateTime d) {
    final diff = AppClock.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return shortDate(d);
  }

  static String greeting([DateTime? now]) {
    final h = (now ?? AppClock.now()).hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String _trim(double v) {
    final s = v.toStringAsFixed(v % 1 == 0 ? 0 : (v < 10 ? 2 : 1));
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
