import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:obs_core/obs_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/notification_service.dart';

/// Uygulama durumu.
///
/// [unknown] başlangıç (yapılandırma okunuyor), [needsSetup] API adresi ve
/// token henüz girilmemiş, [ready] veri çekilebilir.
enum SessionState { unknown, needsSetup, ready }

class ObsProvider extends ChangeNotifier with WidgetsBindingObserver {
  ObsProvider({
    ApiService? service,
    NotificationService? notifications,
    SafeScheduler? scheduler,
  })  : _api = service,
        _notificationService = notifications ?? NotificationService(),
        _scheduler = scheduler ?? SafeScheduler();

  ApiService? _api;
  final NotificationService _notificationService;
  final SafeScheduler _scheduler;

  SessionState session = SessionState.unknown;
  bool isLoading = false;
  String? errorMessage;
  String? studentName;

  List<Course> courses = const [];
  List<ScheduleEntry> schedule = const [];
  List<AttendanceRecord> attendance = const [];

  Timer? _timer;
  bool _hasLoadedGrades = false;

  /// API'nin bağlı olup olmadığı.
  bool get isConnected => _api != null;

  static const _kBaseUrl = 'api_base_url';
  static const _kToken = 'api_token';
  static const _kCache = 'api_payload_cache';

  Future<void> initApp() async {
    WidgetsBinding.instance.addObserver(this);
    await _notificationService.init();
    await _loadConfig();
  }

  /// Yapılandırmayı okur; token varsa veriyi önbellekten gösterip
  /// arka planda tazeler, yoksa kurulum ekranına düşer.
  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_kBaseUrl);
    final token = prefs.getString(_kToken);

    if (baseUrl == null || token == null || baseUrl.isEmpty || token.isEmpty) {
      session = SessionState.needsSetup;
      notifyListeners();
      return;
    }

    _api = ApiService(baseUrl: baseUrl, token: token);
    session = SessionState.ready;
    _restoreCache(prefs);
    notifyListeners();

    unawaited(refreshAll());
    _startPolling();
  }

  /// Kurulum ekranından çağrılır: URL + token dener, tutarsa kaydeder.
  Future<bool> connect(String baseUrl, String token) async {
    final candidate = ApiService(baseUrl: baseUrl, token: token);

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      await candidate.status();
    } on ObsException catch (e) {
      errorMessage = e.message;
      isLoading = false;
      notifyListeners();
      return false;
    }

    _api = candidate;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, candidate.baseUrl);
    await prefs.setString(_kToken, candidate.token);

    session = SessionState.ready;
    isLoading = false;
    notifyListeners();

    await refreshAll();
    _startPolling();
    return true;
  }

  /// Yapılandırmayı siler ve kurulum ekranına döner.
  Future<void> disconnect() async {
    _stopPolling();
    await _notificationService.clearHistory();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBaseUrl);
    await prefs.remove(_kToken);
    await prefs.remove(_kCache);

    _api = null;
    session = SessionState.needsSetup;
    studentName = null;
    courses = const [];
    schedule = const [];
    attendance = const [];
    _hasLoadedGrades = false;
    notifyListeners();
  }

  /// Veriyi API'den çeker; [force] sunucu cache'ini yok sayar.
  ///
  /// İstekler paralel yapılmaz; tek `/all` ucu zaten her şeyi sırayla toplar.
  Future<void> refreshAll({bool force = false}) async {
    final api = _api;
    if (api == null) return;

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final payload = await api.fetchAll(refresh: force);

      studentName = payload.studentName;
      courses = payload.courses;
      schedule = payload.schedule;
      attendance = payload.attendance;

      await _saveCache(payload);

      await _notificationService.checkGrades(courses, isFirstRun: !_hasLoadedGrades);
      await _notificationService.checkAttendance(attendance);
      _hasLoadedGrades = true;

      _scheduler.onSuccess();
      errorMessage = null;
    } on ObsException catch (e) {
      errorMessage = e.message;
      _scheduler.onFailure();
    }

    isLoading = false;
    notifyListeners();
  }

  /// Son başarılı yanıtı önbelleğe yazar; çevrimdışı açılışta gösterilir.
  Future<void> _saveCache(ObsPayload payload) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCache, jsonEncode(payload.toJson()));
  }

  void _restoreCache(SharedPreferences prefs) {
    final raw = prefs.getString(_kCache);
    if (raw == null || raw.isEmpty) return;

    try {
      final payload = ObsPayload.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      studentName = payload.studentName;
      courses = payload.courses;
      schedule = payload.schedule;
      attendance = payload.attendance;
      _hasLoadedGrades = true;
    } on FormatException {
      // Bozuk önbellek yoksayılır; ilk tazeleme yenisiyle değiştirir.
    }
  }

  /// Otomatik güncellemeyi başlatır.
  ///
  /// Uygulama arka plana geçtiğinde zamanlayıcı durur, böylece kullanıcı
  /// uygulamayı açık bırakıp unutsa bile API'ye sürekli istek gitmez.
  void _startPolling() {
    _stopPolling();
    _scheduleNext();
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(_scheduler.nextDelay(), () async {
      // Arka plandayken istek atmıyoruz.
      if (AppLifecycleState.paused == _lifecycle) return _scheduleNext();

      await refreshAll();
      _scheduleNext();
    });
  }

  AppLifecycleState? _lifecycle = AppLifecycleState.resumed;

  /// Uygulama arka plana geçtiğinde otomatik güncellemeyi durdurur.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed && session == SessionState.ready) {
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _stopPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    super.dispose();
  }
}
