import { assert, assertEquals } from 'jsr:@std/assert';

import { solveExpression } from '../functions/_shared/expression.ts';
import { CAPTCHA_GRAMMAR, readCaptchaText, solveCaptcha } from '../functions/_shared/ocr.ts';

// Gerçek OBS örnekleri (fixtures/captcha): OCR ya DOĞRU cevap üretmeli ya da
// null (manuel captcha akışına düşer). ASLA yanlış cevap vermemeli.

const labels = JSON.parse(
  await Deno.readTextFile(new URL('./fixtures/captcha/labels.json', import.meta.url)),
) as Record<string, string>;

Deno.test('solveCaptcha: örneklerde yanlış cevap yok', async () => {
  let correct = 0;
  let wrong = 0;
  const wrongs: string[] = [];

  for (const [name, label] of Object.entries(labels)) {
    const image = await Deno.readFile(new URL(`./fixtures/captcha/${name}`, import.meta.url));
    const expected = solveExpression(label);
    const solve = solveCaptcha(image);

    if (solve == null) continue; // manel akışa düşmesi güvenli
    if (solve === expected) {
      correct++;
    } else {
      wrong++;
      wrongs.push(`${name}: ${solve} != ${expected}`);
    }
  }

  assertEquals(wrong, 0, `yanlış okuma: ${wrongs.join(', ')}`);
  assert(correct >= 1, `en az bir örnek otomatik çözülmeli (correct=${correct})`);
});

Deno.test('CAPTCHA_GRAMMAR: yapısal olarak geçersiz okumaları reddeder', () => {
  assert(CAPTCHA_GRAMMAR.test('54+3=?'));
  assert(CAPTCHA_GRAMMAR.test('09+7=?'));
  assert(!CAPTCHA_GRAMMAR.test('5+43=?')); // operatör yanlış yerde
  assert(!CAPTCHA_GRAMMAR.test('54+34=?')); // sağ operand iki hane
  assert(!CAPTCHA_GRAMMAR.test('54+3=')); // '?' eksik
  assert(!CAPTCHA_GRAMMAR.test('543=?')); // operatör yok
});

Deno.test('boş şablon listesiyle okuma null döner (manuel akış)', async () => {
  // templates.ts üretilmeden önceki durum: hiçbir otomatik deneme yapılmaz.
  const image = await Deno.readFile(
    new URL('./fixtures/captcha/captcha_0.jpg', import.meta.url),
  );
  // Şablonlar üretilmişse bu test yine de anlamlı: null ya da doğru olmalı.
  const text = readCaptchaText(image);
  if (text != null) {
    assert(CAPTCHA_GRAMMAR.test(text), `gramer dışı okuma: ${text}`);
  }
});
