import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:obs_core/obs_core.dart';

import 'captcha_solver.dart';

/// API'nin tek istekte döndürüdüğü taze veri.
class Snapshot {
  final String? studentName;
  final DateTime fetchedAt;
  final List<Course> courses;
  final List<ScheduleEntry> schedule;
  final List<AttendanceRecord> attendance;

  const Snapshot({
    this.studentName,
    required this.fetchedAt,
    required this.courses,
    required this.schedule,
    required this.attendance,
  });

  Map<String, dynamic> toJson() => {
        'studentName': studentName,
        'fetchedAt': fetchedAt.toIso8601String(),
        'courses': courses.map((e) => e.toJson()).toList(),
        'schedule': schedule.map((e) => e.toJson()).toList(),
        'attendance': attendance.map((e) => e.toJson()).toList(),
      };
}

/// OBS oturumunun tek sahibi.
///
/// Görevleri: diskten oturum geri yükleme, düşerse OCR ile sessiz yeniden
/// giriş, kayan oturum süresini canlı tutan keep-alive ping'i ve veriyi
/// cache'leyerek API'ye sunmak. Manuel CAPTCHA fallback'i [pendingForm]
/// üzerinden yürür.
class SessionManager {
  SessionManager({
    required this.username,
    required this.password,
    required this.dataDir,
    ObsService? service,
    CaptchaSolver? solver,
    this.cacheTtl = const Duration(minutes: 5),
    SafeScheduler? scheduler,
  })  : _service = service ?? ObsService(),
        _solver = solver ?? CaptchaSolver(),
        _scheduler = scheduler ?? SafeScheduler();

  final String username;
  final String password;
  final String dataDir;
  final Duration cacheTtl;

  final ObsService _service;
  final CaptchaSolver _solver;
  final SafeScheduler _scheduler;

  /// OCR çözemediğinde manel sayfanın kullandığı hazır giriş formu.
  LoginResult? pendingForm;

  bool sessionAlive = false;

  /// Otomatik giriş OCR'ın tesseract'sız ya da başarısız olmasıyla bekler.
  bool needsManualCaptcha = false;

  String? studentName;
  DateTime? lastRefresh;

  Snapshot? _cache;
  Future<void> _chain = Future.value();
  Timer? _keepAliveTimer;
  bool _stopped = false;

  File get _cookieFile => File('$dataDir${Platform.pathSeparator}session.json');

  /// Diskten oturum deneme → başarısızsa giriş → keep-alive döngüsü.
  Future<void> start() async {
    await _synchronized(() async {
      final restored = await _restoreCookie();
      if (restored) return;
      await _loginAuto();
    });
    _scheduleKeepAlive();
  }

  void _scheduleKeepAlive() {
    if (_stopped) return;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer(_scheduler.nextDelay(), () async {
      await _ping();
      _scheduleKeepAlive();
    });
  }

  /// Ana sayfa ping'i: kayan oturum süresini uzatır, düşen oturumu
  /// yeniden girişle onarır.
  Future<void> _ping() async {
    try {
      final alive = await _service.isSessionAlive();
      sessionAlive = alive;
      if (!alive) {
        await _synchronized(_loginAuto);
      }
    } on ObsException {
      // Ağ hatasında oturuma dokunmuyoruz; sonraki ping tekrar dener.
    }
  }

  Future<bool> _restoreCookie() async {
    try {
      if (!await _cookieFile.exists()) return false;
      final json = jsonDecode(await _cookieFile.readAsString());
      final cookie = json['cookie'] as String?;
      if (cookie == null || cookie.isEmpty) return false;

      _service.restoreSession(cookie);
      sessionAlive = await _service.isSessionAlive();
      if (!sessionAlive) {
        await _cookieFile.delete();
      }
      return sessionAlive;
    } on Exception {
      return false;
    }
  }

  /// OCR ile sessiz giriş. En fazla 2 deneme; CAPTCHA hep tazelenir.
  ///
  /// [ObsException] fırlatmaz: başarısızlık durumunu bayraklarda tutar ki
  /// API "manuel captcha bekleniyor" diyebilsin.
  Future<void> _loginAuto() async {
    needsManualCaptcha = false;

    if (username.isEmpty || password.isEmpty) {
      needsManualCaptcha = true;
      return;
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      final form = await _service.prepareLogin();
      final captcha = form.captcha;

      int? sum;
      if (captcha != null) {
        sum = await _solver.solve(captcha);
      }

      if (sum == null) {
        pendingForm = form;
        needsManualCaptcha = true;
        return;
      }

      final result = await _service.login(
        studentId: username,
        password: password,
        securityCode: sum.toString(),
        viewState: form.viewState,
        viewStateGenerator: form.viewStateGenerator,
        requestVerificationToken: form.requestVerificationToken,
      );

      if (result.success) {
        sessionAlive = true;
        pendingForm = null;
        await _saveCookie();
        return;
      }

      // Yanlış CAPTCHA olabilir; döngü yeni form + yeni görselle dener.
      // Şifre hatası burada iki denemede de aynı çıkar, manel fallback'e
      // düşülür (orada sunucunun gerçek mesajı görünür).
    }

    needsManualCaptcha = true;
    pendingForm = await _service.prepareLogin();
  }

  /// Manuel CAPTCHA sayfası için her açılışta taze form + görsel.
  Future<LoginResult> refreshManualForm() async {
    return _synchronized(() async {
      final form = await _service.prepareLogin();
      pendingForm = form;
      return form;
    });
  }

  /// Manuel girilen toplamı dener. Başarılıysa cookie diske yazılır.
  Future<LoginResultStatus> submitManual(String securityCode) async {
    return _synchronized(() async {
      final form = pendingForm;
      if (form == null) {
        throw const ObsException('Önce güvenlik kodu görseli istenmeli.');
      }

      final result = await _service.login(
        studentId: username,
        password: password,
        securityCode: securityCode,
        viewState: form.viewState,
        viewStateGenerator: form.viewStateGenerator,
        requestVerificationToken: form.requestVerificationToken,
      );

      if (result.success) {
        sessionAlive = true;
        needsManualCaptcha = false;
        pendingForm = null;
        await _saveCookie();
      } else {
        // Yeni görsel üret ki kullanıcı hemen tekrar deneyebilsin.
        pendingForm = await _service.prepareLogin();
      }
      return result;
    });
  }

  /// Cache tazeyse onu, değilse OBS'ten taze veri çeker.
  ///
  /// [force] cache'i yok sayar. Oturum düşmüşse önce sessiz giriş dener;
  /// manel captcha gerekiyorsa [ObsException] ile bildirir.
  Future<Snapshot> snapshot({bool force = false}) {
    return _synchronized(() async {
      final cache = _cache;
      if (!force &&
          cache != null &&
          DateTime.now().difference(cache.fetchedAt) < cacheTtl) {
        return cache;
      }

      await _ensureAlive();
      try {
        return await _fetch();
      } on ObsException catch (e) {
        if (!e.message.contains('Oturum')) rethrow;
        // Sayfa ortasında oturum düştü: bir kez yeniden giriş dene.
        sessionAlive = false;
        await _loginAuto();
        await _ensureAlive();
        return await _fetch();
      }
    });
  }

  Future<void> _ensureAlive() async {
    if (sessionAlive) return;
    await _loginAuto();
    if (sessionAlive) return;

    if (needsManualCaptcha) {
      throw const ObsException(
        'Sunucu oturumu yenilenemiyor; manel güvenlik kodu bekleniyor.',
      );
    }
    throw const ObsException('OBS girişi başarısız.');
  }

  Future<Snapshot> _fetch() async {
    await _service.discoverPages();
    studentName = _service.studentName;

    // İstekler sıralı: OBS'e paralel istek oturum düşürme riski taşıyor.
    final courses = await _service.fetchGrades();
    final schedule = await _service.fetchSchedule();
    final attendance = await _service.fetchAttendance();

    final snapshot = Snapshot(
      studentName: studentName,
      fetchedAt: DateTime.now(),
      courses: courses,
      schedule: schedule,
      attendance: attendance,
    );
    _cache = snapshot;
    lastRefresh = snapshot.fetchedAt;
    return snapshot;
  }

  /// Cookie'yi diske yazar; sunucu restart olsa da oturum geri gelir.
  Future<void> _saveCookie() async {
    try {
      await Directory(dataDir).create(recursive: true);
      await _cookieFile.writeAsString(
        jsonEncode({
          'cookie': _service.sessionCookie,
          'savedAt': DateTime.now().toIso8601String(),
        }),
        flush: true,
      );
    } on FileSystemException {
      // Kalıcılık yoksa bile oturum bellekte yaşamaya devam eder.
    }
  }

  /// Oturum/cache işlemlerini sıraya sokar: paralel API istekleri aynı
  /// anda ikinci bir OBS oturumu açmasın.
  Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = _chain.then((_) => action());
    _chain = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> stop() async {
    _stopped = true;
    _keepAliveTimer?.cancel();
    await _chain;
  }

  /// /health ve /status için durum özeti.
  Map<String, dynamic> status() => {
        'sessionAlive': sessionAlive,
        'needsManualCaptcha': needsManualCaptcha,
        'studentName': studentName,
        'lastRefresh': lastRefresh?.toIso8601String(),
        'cacheAgeSeconds': _cache == null
            ? null
            : DateTime.now().difference(_cache!.fetchedAt).inSeconds,
      };
}
