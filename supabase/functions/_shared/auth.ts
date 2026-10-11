/// Bearer token doğrulama, rate-limit, CORS ve JSON yanıt yardımcıları.
/// server/lib/api.dart ile aynı davranış.

const RATE_WINDOW_MS = 60_000;
const RATE_MAX_REQUESTS = 60;
const RATE_MAX_IPS = 1000;

/// IP -> son istek zamanları (kayan pencere). Isolate belleği paylaşılmadığı
/// için en iyi ihtimalle tahminidir; asıl koruma token'dadır.
const hits = new Map<string, number[]>();

export function secureEquals(a: string, b: string): boolean {
  const ab = new TextEncoder().encode(a);
  const bb = new TextEncoder().encode(b);
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

export function clientIp(req: Request): string {
  const forwarded = req.headers.get('x-forwarded-for');
  if (forwarded != null && forwarded.length > 0) {
    return forwarded.split(',')[0].trim();
  }
  return 'unknown';
}

function rateOk(req: Request): boolean {
  const now = Date.now();
  const ip = clientIp(req);

  let list = hits.get(ip);
  if (list == null) {
    list = [];
    hits.set(ip, list);
  }
  let writeIndex = 0;
  for (let i = 0; i < list.length; i++) {
    if (now - list[i] < RATE_WINDOW_MS) list[writeIndex++] = list[i];
  }
  list.length = writeIndex;

  if (list.length >= RATE_MAX_REQUESTS) return false;
  list.push(now);

  // Tablo büyümesini sınırla: penceredir sessiz IP'ler atılır.
  if (hits.size > RATE_MAX_IPS) {
    for (const [key, times] of hits) {
      if (times.length === 0 || now - times[times.length - 1] >= RATE_WINDOW_MS) {
        hits.delete(key);
      }
    }
  }
  return true;
}

/// İstek geçerliyse null, değilse döndürülmesi gereken hata yanıtı.
export function guard(req: Request, apiToken: string): Response | null {
  if (req.method === 'OPTIONS') return options204();

  if (!rateOk(req)) {
    return json(429, { error: 'Çok fazla istek; birazdan tekrar dene.' });
  }

  const header = req.headers.get('authorization');
  if (header == null || !header.startsWith('Bearer ')) {
    // Manuel akışlar sorgu token'ı da kabul edebilir.
    const query = new URL(req.url).searchParams.get('token');
    if (query == null || !secureEquals(query, apiToken)) {
      return json(401, { error: 'Geçersiz veya eksik token.' });
    }
    return null;
  }
  if (!secureEquals(header.substring('Bearer '.length), apiToken)) {
    return json(401, { error: 'Geçersiz veya eksik token.' });
  }
  return null;
}

export function json(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': '*',
      ...headers,
    },
  });
}

export function options204(): Response {
  return new Response(null, {
    status: 204,
    headers: {
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'GET, POST, OPTIONS',
      'access-control-allow-headers': 'authorization, content-type',
      'access-control-max-age': '86400',
    },
  });
}
