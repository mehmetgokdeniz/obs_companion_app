import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:obs_core/obs_core.dart';

class ObsPayload {
  final String? studentName;
  final DateTime? fetchedAt;
  final List<Course> courses;
  final List<ScheduleEntry> schedule;
  final List<AttendanceRecord> attendance;

  const ObsPayload({
    this.studentName,
    this.fetchedAt,
    this.courses = const [],
    this.schedule = const [],
    this.attendance = const [],
  });

  factory ObsPayload.fromJson(Map<String, dynamic> json) => ObsPayload(
        studentName: json['studentName'] as String?,
        fetchedAt: json['fetchedAt'] == null
            ? null
            : DateTime.tryParse(json['fetchedAt'] as String),
        courses: (json['courses'] as List<dynamic>? ?? const [])
            .map((e) => Course.fromJson(e as Map<String, dynamic>))
            .toList(),
        schedule: (json['schedule'] as List<dynamic>? ?? const [])
            .map((e) => ScheduleEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        attendance: (json['attendance'] as List<dynamic>? ?? const [])
            .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'studentName': studentName,
        'fetchedAt': fetchedAt?.toIso8601String(),
        'courses': courses.map((e) => e.toJson()).toList(),
        'schedule': schedule.map((e) => e.toJson()).toList(),
        'attendance': attendance.map((e) => e.toJson()).toList(),
      };
}

class ApiService {
  ApiService({
    required String baseUrl,
    required String token,
    http.Client? client,
  })  : baseUrl = _normalize(baseUrl),
        token = token.trim(),
        _client = client ?? http.Client();

  final String baseUrl;
  final String token;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 35);

  static final _ipv4Literal = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  static String _normalize(String raw) {
    var url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      // IP literal'ı bir alan adı değildir; sertifikası olmaz, https denenirse
      // el sıkışma patlar. Alan adlarında ise https varsayılır.
      final host = url.split('/').first.split(':').first;
      final isLocalAddress = host == 'localhost' || _ipv4Literal.hasMatch(host);
      url = '${isLocalAddress ? 'http' : 'https'}://$url';
    }
    return url;
  }

  Future<Map<String, dynamic>> status() => _get('/status');

  Future<ObsPayload> fetchAll({bool refresh = false}) async {
    final json = await _get('/all', refresh: refresh);
    return ObsPayload.fromJson(json);
  }

  /// Manuel captcha akışı: taze güvenlik kodu görselini indirir.
  Future<Uint8List> captchaImage() async {
    final json = await _get('/captcha');
    final image = json['imageBase64'];
    if (image is! String || image.isEmpty) {
      throw const ObsException('CAPTCHA görseli alınamadı.');
    }
    return base64Decode(image);
  }

  /// Manuel girilen kodu dener; başarısızsa sunucu taze görselle döner.
  Future<CaptchaSubmitResult> submitCaptcha(String code) async {
    final uri = Uri.parse('$baseUrl/captcha');

    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'code': code}),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ObsException(
        'API sunucusu zamanında yanıt vermedi. API adresini ve sunucunun '
        'çalıştığını kontrol et.',
      );
    } on SocketException catch (e) {
      throw ObsException('API sunucusuna bağlanılamadı: ${e.message}');
    } on http.ClientException catch (e) {
      throw ObsException('API bağlantısı kurulamadı: ${e.message}');
    }

    Map<String, dynamic> decoded;
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      decoded = body is Map<String, dynamic> ? body : <String, dynamic>{};
    } on FormatException {
      decoded = <String, dynamic>{};
    }

    final imageBase64 = decoded['imageBase64'];
    return CaptchaSubmitResult(
      success: response.statusCode == 200,
      error: decoded['error'] as String?,
      image: imageBase64 is String && imageBase64.isNotEmpty
          ? base64Decode(imageBase64)
          : null,
    );
  }

  Map<String, String> get _authHeaders => {
        'Authorization': <String>['Bearer', token].join(' '),
      };

  Future<Map<String, dynamic>> _get(
    String path, {
    bool refresh = false,
  }) async {
    final endpoint = Uri.parse('$baseUrl$path');
    final uri = refresh
        ? endpoint.replace(queryParameters: {'refresh': '1'})
        : endpoint;

    final http.Response response;
    try {
      response = await _getWithRetry(uri);
    } on TimeoutException {
      throw const ObsException(
        'API sunucusu zamanında yanıt vermedi. API adresini ve sunucunun '
        'çalıştığını kontrol et.',
      );
    } on SocketException catch (e) {
      throw ObsException('API sunucusuna bağlanılamadı: ${e.message}');
    } on http.ClientException catch (e) {
      throw ObsException('API bağlantısı kurulamadı: ${e.message}');
    }

    Map<String, dynamic> decoded;
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      decoded = body is Map<String, dynamic> ? body : <String, dynamic>{};
    } on FormatException {
      decoded = <String, dynamic>{};
    }

    if (response.statusCode == 200) return decoded;

    final message = decoded['error'] as String? ??
        'Sunucu hatası (HTTP ${response.statusCode}).';
    throw ObsException(message);
  }

  Future<http.Response> _getWithRetry(Uri uri) async {
    try {
      return await _client.get(uri, headers: _authHeaders).timeout(_timeout);
    } on TimeoutException {
      return await _client.get(uri, headers: _authHeaders).timeout(_timeout);
    }
  }
}

/// Manuel captcha gönderiminin sonucu.
class CaptchaSubmitResult {
  final bool success;
  final String? error;

  /// Başarısız girişten sonra sunucunun döndüğü taze görsel (varsa).
  final Uint8List? image;

  const CaptchaSubmitResult({
    required this.success,
    this.error,
    this.image,
  });
}
