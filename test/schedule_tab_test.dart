import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obs_companion_app/providers/obs_provider.dart';
import 'package:obs_companion_app/views/home_view.dart';
import 'package:obs_core/obs_core.dart';
import 'package:provider/provider.dart';

ScheduleEntry _entry({
  required String code,
  required String name,
  required String start,
  required String room,
}) {
  return ScheduleEntry(
    courseCode: code,
    courseName: name,
    day: 'Pazartesi',
    startTime: start,
    endTime: '08:45',
    classroom: room,
  );
}

void main() {
  const longRoom = 'BLD-Z-16(EL-Z-16 BLD104 Bilgisayar Laboratuvarı)[45]';

  testWidgets('program hucresinde ders adi ve sinif ust üste binmez', (tester) async {
    final provider = ObsProvider()
      ..session = SessionState.ready
      ..studentName = 'Test Ogrenci'
      ..schedule = [
        _entry(
          code: 'BIL201',
          name: 'Yazılım Mühendisliği ve Analizi',
          start: '08:00',
          room: longRoom,
        ),
        _entry(
          code: 'MAT101',
          name: 'Lineer Cebir',
          start: '09:00',
          room: 'BLD-Z-17 BLD103',
        ),
      ];

    await tester.pumpWidget(
      ChangeNotifierProvider<ObsProvider>.value(
        value: provider,
        child: const MaterialApp(home: HomeView()),
      ),
    );

    await tester.tap(find.text('Program'));
    await tester.pumpAndSettle();

    final name = find.text('Yazılım Mühendisliği ve Analizi');
    final room = find.text('Sınıf: $longRoom');
    final code = find.text('BIL201');

    expect(name, findsOneWidget, reason: 'Ders adı görünmeli.');
    expect(room, findsOneWidget, reason: 'Sınıf bilgisi görünmeli.');
    expect(code, findsOneWidget, reason: 'Ders kodu görünmeli.');

    final nameRect = tester.getRect(name);
    final roomRect = tester.getRect(room);
    final codeRect = tester.getRect(code);

    // Satır yüksekliği 48px'e sabitlenirse üçüncü satıra hiç yer kalmaz ve
    // metin alt satırdaki dersin üstüne boyanır.
    expect(
      codeRect.height,
      greaterThan(0),
      reason: 'Ders kodu satır yüksekliğine sığmadı; metin alt satıra taşıyor.',
    );
    expect(
      codeRect.bottom - nameRect.top,
      greaterThan(48),
      reason: 'Satır, ders adı + sınıf + kod içeriğini taşıyacak kadar yüksek değil.',
    );

    // Üç metin alt alta dizili; hiçbiri diğerinin kutusuna girmiyor.
    expect(nameRect.bottom, lessThanOrEqualTo(roomRect.top + 0.5));
    expect(roomRect.bottom, lessThanOrEqualTo(codeRect.top + 0.5));

    // Ardışık iki satır da birbirinin üstüne binmiyor.
    final secondRowName = find.text('Lineer Cebir');
    expect(secondRowName, findsOneWidget);
    expect(
      codeRect.bottom,
      lessThanOrEqualTo(tester.getRect(secondRowName).top + 0.5),
      reason: 'İlk satırın içeriği ikinci satırdaki dersin üstüne taşıyor.',
    );
  });
}
