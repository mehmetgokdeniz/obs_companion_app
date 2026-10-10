import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:obs_companion_app/services/api_service.dart';
import 'package:obs_core/obs_core.dart';

void main() {
  group('ApiService', () {
    test('basarili yaniti modele cevirir', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/all');
        expect(request.headers['Authorization'], 'Bearer tok123');
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'studentName': 'Ayşe Yılmaz',
            'fetchedAt': '2026-10-09T10:00:00.000',
            'courses': [
              {
                'code': 'BIL101',
                'name': 'Programlama',
                'midtermGrade': 85,
                'finalGrade': 90,
                'letterGrade': 'AA',
              },
            ],
            'schedule': [
              {
                'courseCode': 'BIL101',
                'courseName': 'Programlama',
                'day': 'Pazartesi',
                'startTime': '09:00',
                'endTime': '10:50',
                'classroom': 'A101',
              },
            ],
            'attendance': [
              {
                'courseCode': 'BIL101',
                'courseName': 'Programlama',
                'absentHours': 6,
                'totalHours': 30,
                'status': 'Devamsız',
              },
            ],
          })),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiService(baseUrl: 'https://api.ornek.com', token: ' tok123 ', client: client);
      final payload = await api.fetchAll();

      expect(payload.studentName, 'Ayşe Yılmaz');
      expect(payload.courses.single.midtermGrade, 85);
      expect(payload.schedule.single.startTime, '09:00');
      expect(payload.attendance.single.isExceeding, isFalse);
      expect(payload.fetchedAt, isNotNull);
    });

    test('refresh=true ekler', () async {
      var seenQuery = false;
      final client = MockClient((request) async {
        seenQuery = request.url.queryParameters['refresh'] == '1';
        return http.Response.bytes(utf8.encode('{}'), 200);
      });

      final api = ApiService(baseUrl: 'https://api.ornek.com/', token: 't', client: client);
      await api.fetchAll(refresh: true);

      expect(seenQuery, isTrue);
    });

    test('sunucu hatasinda ObsException firlatir', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(jsonEncode({'error': 'Oturum düşdü'})),
          503,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiService(baseUrl: 'https://api.ornek.com', token: 't', client: client);

      expect(
        api.fetchAll(),
        throwsA(isA<ObsException>().having((e) => e.message, 'message', 'Oturum düşdü')),
      );
    });

    test('protokol yoksa https eklenir, sondaki slash temizlenir', () {
      final api = ApiService(baseUrl: 'api.ornek.com///', token: 't');
      expect(api.baseUrl, 'https://api.ornek.com');
    });

    test('IP literalina https eklenmez', () {
      expect(ApiService(baseUrl: '129.146.12.34:8080', token: 't').baseUrl,
          'http://129.146.12.34:8080');
      expect(ApiService(baseUrl: '192.168.1.10:8080', token: 't').baseUrl,
          'http://192.168.1.10:8080');
      expect(ApiService(baseUrl: 'localhost:8080', token: 't').baseUrl,
          'http://localhost:8080');
      expect(ApiService(baseUrl: '127.0.0.1', token: 't').baseUrl,
          'http://127.0.0.1');
    });

    test('alan adi yine https olur, IP gibi gorunen alt alan adi dahil degil', () {
      expect(ApiService(baseUrl: 'api.ornek.com:8443', token: 't').baseUrl,
          'https://api.ornek.com:8443');
      expect(ApiService(baseUrl: '1.2.3.4.ornek.com', token: 't').baseUrl,
          'https://1.2.3.4.ornek.com');
    });
  });
}
