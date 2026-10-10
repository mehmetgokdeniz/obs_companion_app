import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:meta/meta.dart';

import 'course_model.dart';
import 'grade_parser.dart';
import 'login_result.dart';
import 'menu_parser.dart';

/// OBS oturumunu yöneten servis.
///
/// OBS menüdeki gerçek sayfa adlarını gizler, her bağlantıyı
/// `/oibs/start.aspx?gkm=<token>` ile verir. Bu yüzden veri sayfaları
/// önce [discoverPages] ile kullanıcının kendi oturumu içinde çözülür.
class ObsService {
  static const String baseUrl = 'https://obs.alparslan.edu.tr';

  static const String loginUrl = '$baseUrl/oibs/std/login.aspx';
  static const String captchaUrl = '$baseUrl/oibs/captcha/CaptchaImg.aspx';
  static const String homeUrl = '$baseUrl/oibs/std/index.aspx?curOp=0';
  static const String timeoutMarker = '/oibs/redirect.aspx';

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const Duration _timeout = Duration(seconds: 20);

  final Map<String, String> _cookies = {};

  /// Menüden çözülen sayfa adresleri. Anahtar: menüdeki görünen başlık.
  final Map<String, String> _pages = {};

  /// Öğrenci adı ve numarası, ana sayfadan okunur.
  String? studentName;

  Uint8List? captchaBytes;

  String get _cookieHeader =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Map<String, String> get _baseHeaders => {
        'User-Agent': _userAgent,
        'Accept-Language': 'tr-TR,tr;q=0.9',
        'Referer': homeUrl,
        if (_cookieHeader.isNotEmpty) 'Cookie': _cookieHeader,
      };

  /// Giriş formunun gizli alanlarını ve CAPTCHA görselini toplar.
  ///
  /// Bu GET'ler de [login] POST'uyla **aynı** başlıkları göndermek zorunda:
  /// OBS, User-Agent'a göre farklı login sayfası varyantı döndürüyor ve o
  /// sayfanın viewstate'i ile yapılan POST, "Oturum zaman aşımına uğradı"
  /// hatasıyla reddediliyor.
  Future<LoginResult> prepareLogin() async {
    final response = await _send(
      () => http.get(Uri.parse(loginUrl), headers: _baseHeaders),
    );

    if (response.statusCode != 200) {
      throw ObsException('Giriş sayfası yüklenemedi (HTTP ${response.statusCode}).');
    }

    final document = parser.parse(response.body);
    _absorbCookies(response);

    final captcha = await _downloadCaptcha();

    return LoginResult(
      viewState: _hiddenValue(document, '__VIEWSTATE'),
      viewStateGenerator: _hiddenValue(document, '__VIEWSTATEGENERATOR'),
      requestVerificationToken: _hiddenValue(document, '__RequestVerificationToken'),
      captcha: captcha,
    );
  }

  Future<Uint8List?> _downloadCaptcha() async {
    final response = await _send(
      () => http.get(Uri.parse(captchaUrl), headers: _baseHeaders),
    );
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
    _absorbCookies(response);
    captchaBytes = response.bodyBytes;
    return captchaBytes;
  }

  /// Giriş yapar. Başarılıysa oturum bilgisi taşıyan sonuç döner.
  Future<LoginResultStatus> login({
    required String studentId,
    required String password,
    required String securityCode,
    required String viewState,
    required String viewStateGenerator,
    required String requestVerificationToken,
  }) async {
    // Yönlendirme takibi kapatilir: OBS giriş POST'unu daima 302 ile
    // yanitliyor ve gercek hata mesaji (orn. "Guvenlik kodu hatali") POST'un
    // kendi govdesinde yaziliyor. Takip acik kalirsa o govde kayboluyor ve
    // yerine yonlendirme sayfasinin genel uyarisi geliyor.
    final request = http.Request('POST', Uri.parse(loginUrl))
      ..followRedirects = false
      ..headers.addAll({
        ..._baseHeaders,
        'Referer': loginUrl,
        'Content-Type': 'application/x-www-form-urlencoded',
      })
      ..bodyFields = {
        '__LASTFOCUS': '',
        '__EVENTTARGET': 'btnLogin',
        '__EVENTARGUMENT': '',
        '__VIEWSTATE': viewState,
        '__VIEWSTATEGENERATOR': viewStateGenerator,
        '__SCROLLPOSITIONX': '0',
        '__SCROLLPOSITIONY': '0',
        '__RequestVerificationToken': requestVerificationToken,
        'txtParamT01': studentId,
        'txtParamT02': password,
        'txtParamT1': password,
        'txtSecCode': securityCode,
        'txt_scrWidth': '0',
        'txt_scrHeight': '0',
      };

    final response = await _send(() async {
      return http.Response.fromStream(await request.send());
    });

    _absorbCookies(response);

    // Basarisiz giriste sunucu POST'un govdesine gercek hatayi yazar.
    final error = _extractError(response.body);
    if (error != null && !_isLoggedInPage(response.body)) {
      return LoginResultStatus.failure(_humanize(error));
    }

    // Basarili giriste 302 doner; yonlendirmeyi takip edip ana sayfaya
    // ulasiliyor mu diye bakmamiz gerekir.
    if (response.statusCode == 302 || response.statusCode == 301) {
      final location = response.headers['location'];
      if (location == null) {
        return const LoginResultStatus.failure('Giriş sonucu okunamadı.');
      }

      final redirect = await _send(
        () => http.get(
          Uri.parse(location.startsWith('http') ? location : '$baseUrl$location'),
          headers: _baseHeaders,
        ),
      );
      _absorbCookies(redirect);

      if (_isLoggedInPage(redirect.body)) {
        return LoginResultStatus.success(sessionCookie: _cookieHeader);
      }

      return LoginResultStatus.failure(
        _extractError(redirect.body) ?? 'Giriş başarısız.',
      );
    }

    if (_isLoggedInPage(response.body)) {
      return LoginResultStatus.success(sessionCookie: _cookieHeader);
    }

    return LoginResultStatus.failure(_extractError(response.body) ?? 'Giriş başarısız.');
  }

  /// Yanıt, oturum açılmış ana sayfanın kendisi mi?
  ///
  /// Başarılı girişten sonra ana sayfada çıkış düğmesi bulunur; giriş
  /// formunda ise bu düğme yoktur ve giriş alanları yer alır.
  bool _isLoggedInPage(String body) {
    if (body.contains(timeoutMarker)) return false;
    return body.contains('id="btnLogout"') ||
        body.contains('IFRAME1') ||
        body.contains('id="proMenu"');
  }

  /// Ana sayfayı açar, menü bağlantılarını çözer ve öğrenci bilgisini okur.
  Future<void> discoverPages() async {
    final response = await _send(
      () => http.get(Uri.parse(homeUrl), headers: {..._baseHeaders, 'Referer': loginUrl}),
    );

    if (!_isLoggedInPage(response.body)) {
      throw const ObsException('Oturum açık değil, tekrar giriş yapmalısın.');
    }

    final document = parser.parse(response.body);
    // Öğrenci adı #lblOgrenciAdSoyad2 span'inde duruyor; içerik
    // "250912032 - AD SOYAD" biçiminde, okul noyu ayıklıyoruz.
    final raw = document.querySelector('#lblOgrenciAdSoyad2')?.text.trim() ??
        document.querySelector('#lblOgrenciAdSoyad')?.text.trim();
    studentName = _studentNameFrom(raw);

    _pages
      ..clear()
      ..addEntries(parseMenu(response.body).map((e) => MapEntry(e.title, e.url)));
  }

  /// Menüde adı geçen sayfayı getirir.
  Future<String?> _fetchPageByTitle(List<String> titles) async {
    for (final title in titles) {
      final url = _pages[title];
      if (url == null) continue;

      final response = await _send(
        () => http.get(Uri.parse(url), headers: _baseHeaders),
      );

      // Oturum düşmüşse sunucu yönlendirme sayfasını döner.
      if (response.body.contains(timeoutMarker) ||
          response.body.contains('Yönlendirme Yapılıyor')) {
        throw const ObsException('Oturum süresi doldu, tekrar giriş yapmalısın.');
      }
      if (response.statusCode == 404) {
        throw const ObsException('Sayfa bulunamadı, OBS menüsü değişmiş olabilir.');
      }

      return response.body;
    }
    return null;
  }

  /// "250912032 - MEHMET GÖKDENİZ" -> "MEHMET GÖKDENİZ".
  static String? _studentNameFrom(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final dash = raw.indexOf(' - ');
    final name = dash >= 0 ? raw.substring(dash + 3) : raw;
    final trimmed = name.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Ana sayfanın ham HTML'ini getirir (öğrenci adı gibi alanların
  /// gerçek yapısını incelemek için).
  Future<String> fetchPageHtmlAnaSayfa() async {
    final response = await _send(
      () => http.get(Uri.parse(homeUrl), headers: {..._baseHeaders, 'Referer': loginUrl}),
    );
    if (!_isLoggedInPage(response.body)) {
      throw const ObsException('Oturum açık değil, tekrar giriş yapmalısın.');
    }
    return response.body;
  }

  /// Menüde başlığı verilen sayfanın çözülmüş adresi.
  ///
  /// [discoverPages] çağrıldıktan sonra anlamlıdır; yalnızca araç ve test
  /// amaçlıdır (örn. dönem değiştirme postback'i).
  String? menuUrlFor(String title) => _pages[title];

  /// Menüde adı geçen sayfanın ham HTML'ini getirir.
  ///
  /// Parser'ları gerçek OBS çıktısıyla karşılaştırıp ayarlamak için
  /// kullanılır; uygulama akışı bundan yararlanmaz.
  Future<String> fetchPageHtml(String title) async {
    final html = await _fetchPageByTitle([title]);
    if (html == null) {
      throw ObsException('$title sayfası bulunamadı.');
    }
    return html;
  }

  Future<List<Course>> fetchGrades() async {
    final html = await _fetchPageByTitle(const ['Not Listesi']);
    if (html == null) {
      throw const ObsException('Not Listesi sayfası bulunamadı.');
    }
    return parseGrades(html);
  }

  Future<List<ScheduleEntry>> fetchSchedule() async {
    final html = await _fetchPageByTitle(const ['Ders Programı', 'Bölüm Ders Programı']);
    if (html == null) {
      throw const ObsException('Ders Programı sayfası bulunamadı.');
    }
    return parseSchedule(html);
  }

  Future<List<AttendanceRecord>> fetchAttendance() async {
    final html = await _fetchPageByTitle(const ['Devamsızlık Durumu']);
    if (html == null) {
      throw const ObsException('Devamsızlık sayfası bulunamadı.');
    }
    return parseAttendance(html);
  }

  /// Oturum hâlâ geçerli mi?
  Future<bool> isSessionAlive() async {
    final response = await _send(
      () => http.get(Uri.parse(homeUrl), headers: {..._baseHeaders, 'Referer': loginUrl}),
    );
    // Ana sayfa, oturum yokken de 200 döner ama yönlendirme sayfasının
    // gövdesini verir; bu yüzden yalnızca durum koduna bakmak yanıltıcıdır.
    return _isLoggedInPage(response.body);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } on Exception catch (e) {
      throw ObsException('Bağlantı hatası: $e');
    }
  }

  void _absorbCookies(http.Response response) {
    // Dart, birden fazla set-cookie başlığını tek string olarak toplar.
    // Biçim: "isim=deger; path=/; HttpOnly; SameSite=Lax,isim2=deger2; ...".
    // Bu yüzden önce virgülle ayrılmış cerezleri belirleyip sonra her birini
    // niteliklerinden ayırmak gerekir.
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;

    for (final cookie in raw.split(',')) {
      // Her parçanın ilk "isim=deger" çifti çerezin kendisidir; geri kalanı
      // niteliklerdir (path, HttpOnly, SameSite, Max-Age vb.).
      final pair = cookie.split(';').first.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;

      final name = pair.substring(0, eq).trim();
      if (!_isCookieName(name)) continue;

      final value = pair.substring(eq + 1).trim().replaceAll('"', '');
      if (value.isEmpty) continue;

      _cookies[name] = value;
    }
  }

  /// Cerez adları harf, rakam, tire ve alt çizgiden oluşur; nitelik adları
  /// ("path", "SameSite") da bu kalıba uyar, bu yüzden ayrıca eleniyorlar.
  bool _isCookieName(String name) {
    if (!RegExp(r'^[A-Za-z0-9_\-.]+$').hasMatch(name)) return false;
    return !_cookieAttributes.contains(name.toLowerCase());
  }

  static const _cookieAttributes = {
    'path',
    'domain',
    'expires',
    'max-age',
    'secure',
    'httponly',
    'samesite',
    'version',
    'comment',
  };

  /// Toplanan oturum çerezinin başlığı. Başarılı girişten sonra diske
  /// yazılır ki sunucu yeniden başlasa da oturum kaybolmasın.
  String get sessionCookie => _cookieHeader;

  /// Toplanan oturum cerzinin basligi. Testlerin ayristirmayi dogrulamasi
  /// icin gorunur kiliyoruz.
  @visibleForTesting
  String get sessionCookieForTest => _cookieHeader;

  String _hiddenValue(dynamic document, String name) =>
      document.querySelector('input[name="$name"]')?.attributes['value']
          as String? ?? '';

String? _extractError(String body) {
    // OBS hata mesajini lblSonuclar icine yazar; ancak "class" niteligi
    // "id"den once gelir, bu yuzden sadece id'ye bakmak yetmez.
    final match = RegExp(
      r'''<span[^>]*\bid\s*=\s*['"]lblSonuclar['"][^>]*>(.*?)</span>''',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(body);
    if (match == null) return null;

    final text = (parser.parseFragment(match.group(1) ?? '').text ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.isEmpty ? null : text;
  }

  /// Sunucunun ham mesajini kullaniciya daha anlasilir hale getirir.
  String _humanize(String serverMessage) {
    final lower = serverMessage.toLowerCase();

    if (lower.contains('güvenlik kodu') || lower.contains('guvenlik kodu')) {
      return 'Güvenlik kodunu yanlış girdin. Görseldeki rakamların toplamını yaz.';
    }
    if (lower.contains('kullanıcı') || lower.contains('kullanici')) {
      return 'Öğrenci numaranı kontrol et.';
    }
    if (lower.contains('şifre') || lower.contains('sifre')) {
      return 'Şifren yanlış, tekrar dene.';
    }
    if (lower.contains('oturum')) {
      return 'Oturum zaman aşımına uğradı. Lütfen tekrar dene.';
    }

    return serverMessage;
  }

  void restoreSession(String cookie) {
    for (final part in cookie.split(';')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      _cookies[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
    }
  }
}
