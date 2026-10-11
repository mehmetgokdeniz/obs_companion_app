/// OBS'in CAPTCHA görselindeki aritmetik ifadeyi çözer.
/// server/lib/captcha_solver.dart#solveExpression portu.

/// OCR çıktısındaki aritmetik ifadeyi hesaplar.
///
/// OBS'in CAPTCHA'sı "64+6=?" biçiminde bir işlem sorusudur; rakamları
/// toplamak değil, ifadeyi hesaplamak gerekir (aksi halde 6+4+6=16 gibi
/// yanlış sonuç çıkar ve bir girişim boşa harcanır).
///
/// Operatör okunamadıysa ya da ifade eksikse null döner: çağırıcı taze
/// görselle yeniden dener, en sonunda manel fallback'e geçer. Yanlış
/// tahmin sıfırdan daha güvenlidir.
export function solveExpression(raw: string): number | null {
  const cleaned = raw.replace(/\s+/g, '');
  if (cleaned.length === 0) return null;

  const tokens = [...cleaned.matchAll(/\d+|[+\-*/]/g)].map((m) => m[0]);

  // "64+6" -> [64, +, 6]: ilk eleman sayı, sonrası operatör-sayı çifti.
  if (tokens.length < 3) return null;

  const first = parseTokenInt(tokens[0]);
  if (first === null) return null;
  let total = first;

  let i = 1;
  while (i < tokens.length) {
    const op = tokens[i];
    if (i + 1 >= tokens.length) return null; // Sağ operand eksik.
    const right = parseTokenInt(tokens[i + 1]);
    if (right === null) return null;

    switch (op) {
      case '+':
        total += right;
        break;
      case '-':
        total -= right;
        break;
      case '*':
        total *= right;
        break;
      case '/':
        if (right === 0) return null;
        total = Math.trunc(total / right);
        break;
      default:
        return null;
    }
    i += 2;
  }
  return total;
}

function parseTokenInt(token: string): number | null {
  return /^\d+$/.test(token) ? Number(token) : null;
}
