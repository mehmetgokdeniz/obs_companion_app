import 'dart:convert';
import 'dart:io';

import 'package:obs_api_server/api.dart';
import 'package:obs_api_server/session_manager.dart';
import 'package:obs_core/obs_core.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Ağ trafiği üretmeyen sahte servis: her metot sayaçlarak çağrılıyor ki
/// cache ve sıralı çekim davranışı doğrulansın.
class FakeObsService extends ObsService {
  int aliveChecks = 0;
  int gradeFetches = 0;
  int scheduleFetches = 0;
  int attendanceFetches = 0;
  int logins = 0;

  @override
  Future<bool> isSessionAlive() async {
    aliveChecks++;
    return true;
  }

  @override
  Future<void> discoverPages() async {
    studentName = 'Ayşe Yılmaz';
  }

  @override
  Future<List<Course>> fetchGrades() async {
    gradeFetches++;
    return const [
      Course(code: 'BIL101', name: 'Programlama', midtermGrade: 85, finalGrade: 90, letterGrade: 'AA'),
    ];
  }

  @override
  Future<List<ScheduleEntry>> fetchSchedule() async {
    scheduleFetches++;
    return const [
      ScheduleEntry(
        courseCode: 'BIL101',
        courseName: 'Programlama',
        day: 'Pazartesi',
        startTime: '09:00',
        endTime: '10:50',
        classroom: 'A101',
      ),
    ];
  }

  @override
  Future<List<AttendanceRecord>> fetchAttendance() async {
    attendanceFetches++;
    return const [
      AttendanceRecord(courseCode: 'BIL101', courseName: 'Programlama', absentHours: 6, totalHours: 30),
    ];
  }
}

/// Kimlik bilgisi girilmemiş, oturum açık görünen sahte: [SessionManager]
///'ın "açık oturum" yolunu izlemesini sağlar.
class AliveSessionManager extends SessionManager {
  AliveSessionManager({required super.dataDir, super.service})
      : super(username: '', password: '');

  @override
  Future<void> start() async {
    sessionAlive = true;
  }
}

Request _get(
  String path, {
  String? token,
  Map<String, String>? headers,
  Map<String, String>? query,
}) {
  final uri = Uri.parse('http://localhost/$path');
  return Request(
    'GET',
    uri.replace(queryParameters: {...uri.queryParameters, ...?query}),
    headers: {
      if (token != null) 'authorization': 'Bearer $token',
      ...?headers,
    },
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('obs_api_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ApiHandler build(SessionManager sessions) => ApiHandler(
        sessions: sessions,
        token: 'test-token',
      );

  group('auth', () {
    test('health authsuz calisir', () async {
      final handler = build(AliveSessionManager(dataDir: tempDir.path));
      final response = await handler(_get('health'));

      expect(response.statusCode, 200);
      expect(jsonDecode(await response.readAsString())['status'], 'ok');
    });

    test('token yoksa 401', () async {
      final handler = build(AliveSessionManager(dataDir: tempDir.path));
      final response = await handler(_get('api/v1/status'));

      expect(response.statusCode, 401);
    });

    test('yanlis token 401, dogrusu 200', () async {
      final handler = build(AliveSessionManager(dataDir: tempDir.path));

      expect((await handler(_get('api/v1/status', token: 'yanlis'))).statusCode, 401);

      final ok = await handler(_get('api/v1/status', token: 'test-token'));
      expect(ok.statusCode, 200);
    });

    test('bilinmeyen uc 404', () async {
      final handler = build(AliveSessionManager(dataDir: tempDir.path));
      final response = await handler(_get('api/v1/yok', token: 'test-token'));

      expect(response.statusCode, 404);
    });
  });

  group('veri uclari', () {
    test('all ucu uc veriyi birlikte dondurur', () async {
      final sessions = AliveSessionManager(
        dataDir: tempDir.path,
        service: FakeObsService(),
      );
      await sessions.start();
      final handler = build(sessions);

      final response = await handler(_get('api/v1/all', token: 'test-token'));
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(response.statusCode, 200);
      expect(body['studentName'], 'Ayşe Yılmaz');
      expect((body['courses'] as List).single['code'], 'BIL101');
      expect((body['schedule'] as List).single['startTime'], '09:00');
      expect((body['attendance'] as List).single['absentHours'], 6);
      expect(body['fetchedAt'], isNotNull);
    });

    test('tekil uclar kendi listesini dondurur', () async {
      final sessions = AliveSessionManager(
        dataDir: tempDir.path,
        service: FakeObsService(),
      );
      await sessions.start();
      final handler = build(sessions);

      final response = await handler(_get('api/v1/grades', token: 'test-token'));
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(body.keys, containsAll(['studentName', 'fetchedAt', 'courses']));
      expect(body.containsKey('schedule'), isFalse);
    });

    test('cache tazeyse OBS tekrar yoklanmaz, refresh zorlar', () async {
      final fake = FakeObsService();
      final sessions = SessionManager(
        username: '',
        password: '',
        dataDir: tempDir.path,
        service: fake,
      );
      // Boş kimlik bilgisi _loginAuto'yu manel yola iter; oturumu açık
      // sayıp fetch yolunu sınamak için doğrudan işaretliyoruz.
      sessions.sessionAlive = true;
      final handler = build(sessions);

      await handler(_get('api/v1/all', token: 'test-token'));
      await handler(_get('api/v1/all', token: 'test-token'));
      expect(fake.gradeFetches, 1);

      await handler(_get('api/v1/all', token: 'test-token', query: {'refresh': '1'}));
      expect(fake.gradeFetches, 2);
    });

    test('oturum kapaliyken 502 ve manel captcha bayragi', () async {
      final sessions = SessionManager(
        username: '',
        password: '',
        dataDir: tempDir.path,
      );
      final handler = build(sessions);

      final response = await handler(_get('api/v1/all', token: 'test-token'));
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(response.statusCode, 502);
      expect(body['needsManualCaptcha'], isTrue);
      expect(body['error'], isNotEmpty);
    });
  });

  group('rate limit ve CORS', () {
    test('pencere asilinca 429', () async {
      final handler = ApiHandler(
        sessions: AliveSessionManager(dataDir: tempDir.path),
        token: 'test-token',
        maxRequests: 2,
        window: const Duration(minutes: 1),
      );
      const ip = {'x-forwarded-for': '1.2.3.4'};

      final first = await handler(_get('health', headers: ip));
      final second = await handler(_get('health', headers: ip));
      final third = await handler(_get('health', headers: ip));

      expect(first.statusCode, 200);
      expect(second.statusCode, 200);
      expect(third.statusCode, 429);
    });

    test('farkli IP adresleri ayri sayilir', () async {
      final handler = ApiHandler(
        sessions: AliveSessionManager(dataDir: tempDir.path),
        token: 'test-token',
        maxRequests: 1,
      );

      final a = await handler(_get('health', headers: {'x-forwarded-for': '1.1.1.1'}));
      final b = await handler(_get('health', headers: {'x-forwarded-for': '2.2.2.2'}));

      expect(a.statusCode, 200);
      expect(b.statusCode, 200);
    });

    test('OPTIONS preflight authsuz ve limitsiz 204 doner', () async {
      final handler = ApiHandler(
        sessions: AliveSessionManager(dataDir: tempDir.path),
        token: 'test-token',
      );

      final response = await handler(
        Request('OPTIONS', Uri.parse('http://localhost/api/v1/all')),
      );

      expect(response.statusCode, 204);
      expect(response.headers['access-control-allow-origin'], '*');
      expect(response.headers['access-control-allow-headers'], contains('authorization'));
      expect(response.headers['access-control-allow-methods'], contains('GET'));
    });

    test('her yanitta CORS basligi bulunur', () async {
      final handler = build(AliveSessionManager(dataDir: tempDir.path));

      final ok = await handler(_get('health'));
      final unauthorized = await handler(_get('api/v1/status'));
      final missing = await handler(_get('yok'));

      expect(ok.headers['access-control-allow-origin'], '*');
      expect(unauthorized.headers['access-control-allow-origin'], '*');
      expect(missing.headers['access-control-allow-origin'], '*');
    });
  });
}
