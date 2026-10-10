import 'package:html/dom.dart' show Element, Text;
import 'package:html/parser.dart' as parser;

import 'course_model.dart';

/// Beyaz uzunluğunu tek boşluğa indirir.
String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

String _text(Element? element) =>
    element == null ? '' : _clean(element.text);

/// "AFE201 (1)" / "YZM201(1)" -> "AFE201" (grup numarası atılır).
String _stripGroup(String value) =>
    value.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '').trim();

/// Yalnızca tam sayı not okur ("60" tamam, "-" ve "61.73" değil).
int? _grade(String value) {
  final t = _clean(value);
  return RegExp(r'^\d+$').hasMatch(t) ? int.parse(t) : null;
}

/// Ders kartındaki başlık metninden kodun sağındaki ders adını çeker.
///
/// Kart HTML'i `</span>(1) - Ders Adı` biçimindedir; ad, kod span'inden
/// sonraki düz metin düğümleridir.
String _nameAfter(Element codeSpan) {
  final parent = codeSpan.parent;
  if (parent == null) return '';

  final nodes = parent.nodes;
  final index = nodes.indexOf(codeSpan);
  if (index < 0) return '';

  final buffer = StringBuffer();
  for (var i = index + 1; i < nodes.length; i++) {
    final node = nodes[i];
    if (node is Element) break; // Sıradaki span adı sonlandırır.
    if (node is Text) buffer.write(node.data);
  }

  final match = RegExp(r'\(\d+\)\s*-\s*(.*)').firstMatch(buffer.toString());
  return match == null ? '' : _clean(match.group(1)!);
}

/// Not listesi sayfasındaki ders kartlarını çevirir.
///
/// OBS bu sayfayı düz tablo yerine kart yapısında verir:
/// `div.ex-gc` içinde kod span'i, ders adı, sınıf ortalaması, harf notu ve
/// altında ayrı bir sınav tablosu (Vize/Final) bulunur.
List<Course> parseGrades(String html) {
  final document = parser.parse(html);
  final courses = <Course>[];

  for (final card in document.querySelectorAll('div.ex-gc')) {
    final codeSpan = card.querySelector('span[id^="rptNotListesi_lblDersKod_"]');
    if (codeSpan == null) continue;

    final code = _text(codeSpan);
    if (code.isEmpty) continue;

    // Harf notu .grade-badge içinde; dönem başında yok ("-").
    final badge = card.querySelector('.grade-badge');
    final letter = badge == null ? null : _text(badge).isEmpty ? null : _text(badge);

    int? midterm;
    int? finalExam;
    for (final row in card.querySelectorAll('table.ex-gt tbody tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 2) continue;

      final exam = _text(cells[0]).toLowerCase();
      final score = _grade(_text(cells[1]));
      if (score == null) continue;

      if (exam.contains('vize')) midterm = score;
      if (exam.contains('final')) finalExam = score;
    }

    courses.add(Course(
      code: code,
      name: _nameAfter(codeSpan),
      midtermGrade: midterm,
      finalGrade: finalExam,
      letterGrade: letter,
    ));
  }

  return courses;
}

/// Haftalık ders programını çevirir.
///
/// OBS programı pivot tablo olarak verir: satırlar saat aralığı, sütunlar
/// günlerdir; dolu hücrelerde `.course-info` bloğu bulunur.
List<ScheduleEntry> parseSchedule(String html) {
  final document = parser.parse(html);
  final table = document.querySelector('table.myGridClass');
  if (table == null) return const [];

  final entries = <ScheduleEntry>[];
  for (final row in table.querySelectorAll('tbody tr')) {
    final timeText = _text(row.querySelector('.tt-saat-txt'));
    if (timeText.isEmpty) continue;

    // "08:00-08:45" -> başlangıç / bitiş.
    final parts = timeText.split('-');
    final start = parts.isNotEmpty ? parts[0].trim() : '';
    final end = parts.length > 1 ? parts[1].trim() : '';

    for (final cell in row.querySelectorAll('td.pivot-cell')) {
      final info = cell.querySelector('.course-info');
      if (info == null) continue;

      final code = _text(info.querySelector('.course-code'));
      if (code.isEmpty) continue;

      entries.add(ScheduleEntry(
        courseCode: _stripGroup(code),
        courseName: _text(info.querySelector('.course-name')),
        day: cell.attributes['data-label'] ?? '',
        startTime: start,
        endTime: end,
        classroom: _text(info.querySelector('.course-room')),
      ));
    }
  }

  return entries;
}

/// Devamsızlık sayfasını çevirir.
///
/// Satırlar `div.rpt-row` içindeki kolonlardan oluşur. Son kolonda
/// `(Teorik:6) (Uygulama:0)` biçiminde devamsızlık, yanındaki bilgi
/// bağlantısının `title` özniteliğinde ise toplam saat (`Toplam ... (28 Saat)`)
/// yer alır.
List<AttendanceRecord> parseAttendance(String html) {
  final document = parser.parse(html);
  final records = <AttendanceRecord>[];

  for (final row in document.querySelectorAll('div.rpt-row')) {
    final cols = row.children;
    if (cols.length < 7) continue;

    final code = _text(cols[0]);
    if (code.isEmpty) continue;

    String absenceText = '';
    String? infoTitle;
    for (final col in cols) {
      final t = _text(col);
      if (t.contains('Teorik:')) absenceText = t;
      final info = col.querySelector('a[title]');
      if (info != null) infoTitle = info.attributes['title'];
    }

    final theory =
        int.tryParse(RegExp(r'Teorik:\s*(\d+)').firstMatch(absenceText)?.group(1) ?? '');
    final practice =
        int.tryParse(RegExp(r'Uygulama:\s*(\d+)').firstMatch(absenceText)?.group(1) ?? '');

    final totalMatch = infoTitle == null
        ? null
        : RegExp(r'Hafta\s*\((\d+)\s*Saat\)').firstMatch(infoTitle);

    records.add(AttendanceRecord(
      courseCode: _stripGroup(code),
      courseName: _text(cols[1]),
      absentHours: (theory ?? 0) + (practice ?? 0),
      totalHours: totalMatch == null ? null : int.tryParse(totalMatch.group(1)!),
    ));
  }

  return records;
}
