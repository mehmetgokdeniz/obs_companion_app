import 'package:obs_api_server/captcha_solver.dart';
import 'package:test/test.dart';

void main() {
  group('solveExpression', () {
    test('aritmetik ifadeyi cozer', () {
      expect(CaptchaSolver.solveExpression('64+6=?'), 70);
      expect(CaptchaSolver.solveExpression('39+3=?'), 42);
      expect(CaptchaSolver.solveExpression('12+7=?'), 19);
    });

    test('bosluk ve esittigini yok sayar', () {
      expect(CaptchaSolver.solveExpression('64 + 6 = ?'), 70);
      expect(CaptchaSolver.solveExpression('64+6='), 70);
    });

    test('operatör okunamadıysa null döner (yanlış tahmin girişim harcar)', () {
      // OCR "+"'ı kaçırıp "646" okursa toplamak 16 verir; doğru cevap 70.
      expect(CaptchaSolver.solveExpression('646'), isNull);
      expect(CaptchaSolver.solveExpression('70'), isNull);
    });

    test('eksik ifade null döner', () {
      expect(CaptchaSolver.solveExpression('64+'), isNull);
      expect(CaptchaSolver.solveExpression('+6'), isNull);
    });

    test('cikarma ve carpmayi da destekler', () {
      expect(CaptchaSolver.solveExpression('15-4=?'), 11);
      expect(CaptchaSolver.solveExpression('3*7=?'), 21);
    });

    test('bölme ve sıfıra bölme', () {
      expect(CaptchaSolver.solveExpression('8/2=?'), 4);
      expect(CaptchaSolver.solveExpression('8/0=?'), isNull);
    });

    test('bos veya rakamsiz girdide null doner', () {
      expect(CaptchaSolver.solveExpression(''), isNull);
      expect(CaptchaSolver.solveExpression('abc'), isNull);
      expect(CaptchaSolver.solveExpression('=?'), isNull);
    });
  });
}
