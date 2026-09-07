import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/core/money/money.dart';

/// Mirrors tests/Unit/MoneyTest.php on the backend, case for case.
void main() {
  group('Parsing', () {
    test('decimal strings are exact', () {
      expect(Money.fromDecimalString('100000.55').paise, 10000055);
      expect(Money.fromDecimalString('1').paise, 100);
      expect(Money.fromDecimalString('0.1').paise, 10);
      expect(Money.fromDecimalString('0.01').paise, 1);
      expect(Money.fromDecimalString('0').paise, 0);
      expect(Money.fromDecimalString('-25.50').paise, -2550);
    });

    test('a third decimal rounds half up', () {
      expect(Money.fromDecimalString('10.005').paise, 1001);
      expect(Money.fromDecimalString('10.004').paise, 1000);
    });

    test('nonsense is rejected rather than silently zeroed', () {
      expect(
        () => Money.fromDecimalString('quite a lot'),
        throwsFormatException,
      );
    });

    test('a double input is read through its decimal text', () {
      // 0.29 is not exactly representable; multiplying by 100 gives
      // 28.999... which truncates to 28 paise.
      expect(Money.of(0.29).paise, 29);
      expect(Money.of(1.14).paise, 114);
    });

    test('ints, doubles, strings and null all parse', () {
      expect(Money.of(100).paise, 10000);
      expect(Money.of(100.5).paise, 10050);
      expect(Money.of('100.50').paise, 10050);
      expect(Money.of(null).paise, 0);
    });
  });

  group('Arithmetic', () {
    test('the classic float error does not occur', () {
      // 0.1 + 0.2 != 0.3 in binary floating point.
      expect(0.1 + 0.2 == 0.3, isFalse, reason: 'premise of this test');

      final sum = Money.of('0.10') + Money.of('0.20');
      expect(sum.paise, 30);
      expect(sum.toDecimalString(), '0.30');
    });

    test('repeated addition does not drift', () {
      var total = Money.zero;
      for (var i = 0; i < 10000; i++) {
        total = total + Money.of('0.01');
      }
      expect(total.toDecimalString(), '100.00');
    });

    test('division rounds half away from zero', () {
      expect(Money.divideHalfUp(400, 2), 200);
      expect(Money.divideHalfUp(500, 200), 3); // 2.5 -> 3
      expect(Money.divideHalfUp(249, 100), 2); // 2.49 -> 2
      expect(Money.divideHalfUp(251, 100), 3); // 2.51 -> 3
      expect(Money.divideHalfUp(100, 3), 33);
      expect(Money.divideHalfUp(200, 3), 67);
      expect(Money.divideHalfUp(-500, 200), -3);
      expect(Money.divideHalfUp(-100, 3), -33);
    });

    test('dividing by zero throws rather than producing infinity', () {
      expect(() => Money.of('100').dividedBy(0), throwsArgumentError);
    });

    test('large values stay exact', () {
      final big = Money.of('99999999.99');
      expect(big.paise, 9999999999);
      expect(big.toDecimalString(), '99999999.99');
      expect((big + Money.of('0.01')).toDecimalString(), '100000000.00');
    });

    test('clampedToZero never returns a negative', () {
      expect(Money.of('-500').clampedToZero.paise, 0);
      expect(Money.of('500').clampedToZero.paise, 50000);
    });
  });

  group('Ratio', () {
    test('a percentage of zero is zero, not an error', () {
      expect(Ratio.percentOf(Money.of('100'), Money.zero).value, 0);
      expect(Ratio.timesOver(Money.of('100'), Money.zero).value, 0);
    });

    test('percentages hold two decimals', () {
      // 10000 / 90000 = 11.111... -> 11.11
      expect(
        Ratio.percentOf(Money.of('10000'), Money.of('90000')).value,
        11.11,
      );
      expect(Ratio.percentOf(Money.of('20000'), Money.of('100000')).value, 20);
    });

    test('times-over holds two decimals', () {
      // 180000 / 70000 = 2.5714... -> 2.57
      expect(
        Ratio.timesOver(Money.of('180000'), Money.of('70000')).value,
        2.57,
      );
    });
  });
}
