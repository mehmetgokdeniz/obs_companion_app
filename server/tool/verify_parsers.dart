// Parser'ları gerçek OBS HTML çıktılarına karşı doğrular.
//
// dart run tool/verify_parsers.dart
import 'dart:io';

import 'package:obs_core/obs_core.dart';

void main() {
  final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}obs_pages');
  final home = File('${dir.path}${Platform.pathSeparator}_home.html');
  if (home.existsSync()) {
    // Öğrenci adı ayıklama (discoverPages yerine doğrudan HTML'den).
    final raw = _extract(home.readAsStringSync(), 'lblOgrenciAdSoyad2');
    print('OGRENCI_ADI_HAM=$raw');
  }

  final gradesFile = File('${dir.path}${Platform.pathSeparator}Not_Listesi.html');
  if (gradesFile.existsSync()) {
    final courses = parseGrades(gradesFile.readAsStringSync());
    print('--- NOT LISTESI (aktif donem, notlar bos olmali) ---');
    print('DERS_SAYISI=${courses.length}');
    for (final c in courses) {
      print('  ${c.code} | ${c.name} | vize=${c.midtermGrade} final=${c.finalGrade} harf=${c.letterGrade}');
    }
  }

  final periodFile = File('${Directory.systemTemp.path}${Platform.pathSeparator}donem_20251.html');
  if (periodFile.existsSync()) {
    final courses = parseGrades(periodFile.readAsStringSync());
    print('--- NOT LISTESI (20251, notlar dolu olmali) ---');
    print('DERS_SAYISI=${courses.length}');
    for (final c in courses) {
      print('  ${c.code} | ${c.name} | vize=${c.midtermGrade} final=${c.finalGrade} harf=${c.letterGrade}');
    }
  }

  final scheduleFile = File('${dir.path}${Platform.pathSeparator}Ders_Program_.html');
  if (scheduleFile.existsSync()) {
    final entries = parseSchedule(scheduleFile.readAsStringSync());
    print('--- DERS PROGRAMI ---');
    print('GIRIS_SAYISI=${entries.length}');
    for (final e in entries.take(8)) {
      print('  ${e.day} ${e.startTime}-${e.endTime} ${e.courseCode} ${e.courseName} | ${e.classroom}');
    }
  }

  final attFile = File('${dir.path}${Platform.pathSeparator}Devams_zl_k_Durumu.html');
  if (attFile.existsSync()) {
    final records = parseAttendance(attFile.readAsStringSync());
    print('--- DEVAMSIZLIK ---');
    print('KAYIT_SAYISI=${records.length}');
    for (final r in records) {
      print('  ${r.courseCode} | ${r.courseName} | yok=${r.absentHours} toplam=${r.totalHours} oran=${r.ratio?.toStringAsFixed(1)} asim=${r.isExceeding}');
    }
  }
}

String? _extract(String html, String id) {
  final match = RegExp('id="$id"[^>]*>([^<]*)').firstMatch(html);
  return match?.group(1)?.trim();
}
