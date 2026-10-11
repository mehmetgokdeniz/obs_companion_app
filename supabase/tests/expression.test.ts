import { assertEquals } from 'jsr:@std/assert';

import { solveExpression } from '../functions/_shared/expression.ts';

// server/test/captcha_solver_test.dart portu.

Deno.test('aritmetik ifadeyi cozer', () => {
  assertEquals(solveExpression('64+6=?'), 70);
  assertEquals(solveExpression('39+3=?'), 42);
  assertEquals(solveExpression('12+7=?'), 19);
});

Deno.test('bosluk ve esittigini yok sayar', () => {
  assertEquals(solveExpression('64 + 6 = ?'), 70);
  assertEquals(solveExpression('64+6='), 70);
});

Deno.test('operator okunamadiysa null doner (yanlis tahmin girisim harcar)', () => {
  // OCR "+"'ı kaçırıp "646" okursa toplamak 16 verir; doğru cevap 70.
  assertEquals(solveExpression('646'), null);
  assertEquals(solveExpression('70'), null);
});

Deno.test('eksik ifade null doner', () => {
  assertEquals(solveExpression('64+'), null);
  assertEquals(solveExpression('+6'), null);
});

Deno.test('cikarma ve carpmayi da destekler', () => {
  assertEquals(solveExpression('15-4=?'), 11);
  assertEquals(solveExpression('3*7=?'), 21);
});

Deno.test('bolme ve sifira bolme', () => {
  assertEquals(solveExpression('8/2=?'), 4);
  assertEquals(solveExpression('8/0=?'), null);
});

Deno.test('bos veya rakamsiz girdide null doner', () => {
  assertEquals(solveExpression(''), null);
  assertEquals(solveExpression('abc'), null);
  assertEquals(solveExpression('=?'), null);
});
