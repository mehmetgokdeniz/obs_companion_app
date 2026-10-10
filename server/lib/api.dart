import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:obs_core/obs_core.dart';
import 'package:shelf/shelf.dart';

import 'session_manager.dart';

/// Bearer token korumalı JSON API.
///
/// Rotalar:
///  * `GET /health`          — auth'sız canlılık kontrolü
///  * `GET /api/v1/status`   — oturum/önbellek durumu
///  * `GET /api/v1/grades`   — notlar
///  * `GET /api/v1/schedule` — ders programı
///  * `GET /api/v1/attendance` — devamsızlık
///  * `GET /api/v1/all`      — üçü bir arada (uygulamanın tek isteği)
///  * `?refresh=1`           — önbelleği yok sayar
///
/// `GET /admin/captcha` + `POST /admin/login`, OCR başarısız olduğunda
/// devreye giren token korumalı manel CAPTCHA sayfasıdır.
class ApiHandler {
  ApiHandler({
    required this.sessions,
    required this.token,
    this.maxRequests = 60,
    this.window = const Duration(minutes: 1),
  });

  final SessionManager sessions;

  /// İstemcinin taşıdığı erişim anahtarı.
  final String token;

  /// Kayan pencere içinde IP başına izin verilen istek sayısı.
  ///
  /// Tarayıcı bir uç için önce OPTIONS preflight, sonra gerçek isteği
  /// atar; uygulama da connect sırasında iki ucu üst üste çağırır. Bu
  /// yüzden aralık-tabanlı (1/sn) değil pencere-tabanlı limit kullanılır.
  final int maxRequests;
  final Duration window;

  /// IP -> son istek zamanları (kayan pencere).
  final Map<String, List<DateTime>> _hits = {};

  Future<Response> call(Request request) async {
    return _cors(await _handle(request));
  }

  Future<Response> _handle(Request request) async {
    // Tarayıcılar Authorization başlıklı isteklerden önce OPTIONS atar;
    // auth'suz ve limit dışı yanıtlanmalıdır, yoksa site engellenir.
    if (request.method == 'OPTIONS') {
      return Response(204);
    }

    final path = request.url.path;

    if (!_rateOk(request)) {
      return _json(429, {'error': 'Çok fazla istek; birazdan tekrar dene.'});
    }

    if (path == 'health') {
      return _json(200, {'status': 'ok', 'time': DateTime.now().toIso8601String()});
    }

    if (!_authorized(request)) {
      return _json(401, {'error': 'Geçersiz veya eksik token.'});
    }

    try {
      switch (path) {
        case 'api/v1/status':
          return _json(200, sessions.status());
        case 'api/v1/grades':
          return await _section(request, 'courses');
        case 'api/v1/schedule':
          return await _section(request, 'schedule');
        case 'api/v1/attendance':
          return await _section(request, 'attendance');
        case 'api/v1/all':
          final snapshot = await sessions.snapshot(force: _force(request));
          return _json(200, snapshot.toJson());
        case 'admin/captcha':
          return await _captchaPage();
        case 'admin/login':
          return await _submitCaptcha(request);
        default:
          return _json(404, {'error': 'Uç bulunamadı.'});
      }
    } on ObsException catch (e) {
      return _json(502, {
        'error': e.message,
        if (sessions.needsManualCaptcha) 'needsManualCaptcha': true,
      });
    }
  }

  /// Tarayıcının farklı origin'den okuyabilmesi için CORS başlıkları.
  ///
  /// Token sorguyla da taşınabildiğinden origin'i kısıtlamak anlamlı değil;
  /// koruma tamamen token'da.
  Response _cors(Response response) {
    final headers = Map<String, String>.from(response.headers)
      ..['access-control-allow-origin'] = '*';

    if (response.statusCode == 204) {
      headers['access-control-allow-methods'] = 'GET, POST, OPTIONS';
      headers['access-control-allow-headers'] = 'authorization, content-type';
      headers['access-control-max-age'] = '86400';
    }
    return response.change(headers: headers);
  }

  /// Tek bölüm uçları: cache'li snapshot'tan ilgili listeyi ayırır.
  Future<Response> _section(Request request, String key) async {
    final snapshot = await sessions.snapshot(force: _force(request));
    final body = <String, dynamic>{
      'studentName': snapshot.studentName,
      'fetchedAt': snapshot.fetchedAt.toIso8601String(),
      key: snapshot.toJson()[key],
    };
    return _json(200, body);
  }

  /// OCR'ın tesseract'sız kaldığı durumda açılan basit CAPTCHA formu.
  Future<Response> _captchaPage() async {
    final form = await sessions.refreshManualForm();
    final captcha = form.captcha;

    if (captcha == null) {
      return _json(502, {'error': 'CAPTCHA görseli alınamadı.'});
    }

    const page = '''
<!doctype html>
<html lang="tr">
<head><meta charset="utf-8"><title>OBS Captcha</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
 body{font-family:sans-serif;display:flex;justify-content:center;padding:2rem;background:#f5f5f5}
 form{background:#fff;padding:2rem;border-radius:12px;box-shadow:0 2px 8px rgba(0,0,0,.1);text-align:center}
 input{font-size:1.2rem;padding:.5rem;width:8rem;text-align:center;margin:.5rem 0}
 button{font-size:1.1rem;padding:.5rem 1.5rem;border-radius:8px;border:0;background:#1565c0;color:#fff;cursor:pointer}
 img{image-rendering:pixelated}
</style></head>
<body>
<form method="POST" action="/admin/login?token=__TOKEN__">
  <h2>Güvenlik kodu</h2>
  <p>Görseldeki rakamların toplamını gir</p>
  <img src="data:image/jpeg;base64,__IMG__" alt="captcha">
  <p><input name="securityCode" inputmode="numeric" autocomplete="off" autofocus required></p>
  <p><button type="submit">Giriş yap</button></p>
</form>
</body>
</html>''';

    final html = page
        .replaceAll('__IMG__', base64Encode(captcha))
        .replaceAll('__TOKEN__', Uri.encodeQueryComponent(token));

    return Response(
      200,
      body: html,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }

  Future<Response> _submitCaptcha(Request request) async {
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    final code = (params['securityCode'] ?? '').trim();

    if (code.isEmpty) {
      return _json(400, {'error': 'Güvenlik kodu boş olamaz.'});
    }

    final result = await sessions.submitManual(code);

    if (result.success) {
      return Response(
        303,
        headers: {'location': '/api/v1/status?token=$token'},
      );
    }

    return _json(401, {
      'error': result.error ?? 'Giriş başarısız.',
      'retryUrl': '/admin/captcha?token=$token',
    });
  }

  bool _force(Request request) =>
      request.url.queryParameters['refresh'] == '1';

  bool _authorized(Request request) {
    final header = request.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) {
      // Manuel sayfalar tarayıcıdan geldiği için query token'ı da kabul edilir.
      final query = request.url.queryParameters['token'];
      return query != null && _secureEquals(query, token);
    }
    return _secureEquals(header.substring('Bearer '.length), token);
  }

  /// Timing attack'e dayanıklı karşılaştırma (kısa anahtar için fazlasıyla yeterli).
  bool _secureEquals(String a, String b) {
    final ab = utf8.encode(a);
    final bb = utf8.encode(b);
    if (ab.length != bb.length) return false;
    var diff = 0;
    for (var i = 0; i < ab.length; i++) {
      diff |= ab[i] ^ bb[i];
    }
    return diff == 0;
  }

  bool _rateOk(Request request) {
    final now = DateTime.now();
    final ip = _clientIp(request);

    final hits = (_hits[ip] ??= <DateTime>[])
      ..removeWhere((t) => now.difference(t) >= window);

    if (hits.length >= maxRequests) return false;
    hits.add(now);

    // Tablo büyümesini sınırla: penceredir sessiz IP'ler atılır.
    if (_hits.length > 1000) {
      _hits.removeWhere((_, list) =>
          list.isEmpty || now.difference(list.last) >= window);
    }
    return true;
  }

  /// İstemci IP'si: arkadaki proxy'nin eklediği başlık önce gelir.
  String _clientIp(Request request) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    final info = request.context['shelf.io.connectionInfo'];
    if (info is HttpConnectionInfo) return info.remoteAddress.address;
    return 'unknown';
  }

  Response _json(int status, Object body) => Response(
        status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}
