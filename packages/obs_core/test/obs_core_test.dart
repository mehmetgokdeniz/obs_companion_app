import 'package:obs_core/obs_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseMenu', () {
    test('gkm adreslerini menu_close icinden cikarir', () {
      const html = '''
        <a class="nav-link"
           onclick="menu_close(this,'/oibs/start.aspx?gkm=abc123');" href="#">
          <p>Not Listesi</p>
        </a>
      ''';

      final links = parseMenu(html);

      expect(links, hasLength(1));
      expect(links.first.title, 'Not Listesi');
      expect(
        links.first.url,
        'https://obs.alparslan.edu.tr/oibs/start.aspx?gkm=abc123',
      );
    });

    test('href ile gelen baglantilari da okur', () {
      const html = '''
        <a class="nav-link" href="/oibs/start.aspx?gkm=xyz" target="_blank">
          <p>Transkript</p>
        </a>
      ''';

      final links = parseMenu(html);

      expect(links.single.title, 'Transkript');
      expect(links.single.url, 'https://obs.alparslan.edu.tr/oibs/start.aspx?gkm=xyz');
    });
  });

  group('parseGrades', () {
    // Gerçek OBS kart yapısı: div.ex-gc + kod span'i + sınav tablosu.
    const card = '''
      <div class="ex-gc">
        <table class="ex-gt"><tbody><tr class="ex-r ex-gh"><td>
          <div><div class="mb-1">
            <span id="rptNotListesi_lblDersKod_0"><font>TRD129</font></span>(1) - T&uuml;rk Dili I
            <span class="mx-1">|</span>
            <span id="rptNotListesi_lblCardOrt_0"><font>Ort</font></span>:
            <span class="avg-badge">69</span>
            <span id="rptNotListesi_lblCardNot_0"><font>Not</font></span>:
            <span class="grade-badge">CB</span>
            <span id="rptNotListesi_lblCardDurum_0"><font>Durumu</font></span>:
            <span class=''>Ge&ccedil;ti</span>
          </div></div>
        </td></tr></tbody></table>
        <table class="ex-gt">
          <thead><tr class="ex-hr">
            <th class="ex-h">S&#305;nav Ad&#305;</th><th class="ex-h">Not</th>
            <th class="ex-h">&#304;lan Tarihi</th><th class="ex-h">S&#305;n&#305;f Ort.</th><th class="ex-h">Detay</th>
          </tr></thead>
          <tbody>
            <tr class="ex-r ex-i">
              <td class="ex-c">Vize</td><td class="ex-c">60</td>
              <td class="ex-c">23.11.2025</td><td class="ex-c">61.73</td><td class="ex-c"></td>
            </tr>
            <tr class="ex-r ex-i">
              <td class="ex-c">Final</td><td class="ex-c">75</td>
              <td class="ex-c">19.01.2026</td><td class="ex-c">76.36</td><td class="ex-c"></td>
            </tr>
          </tbody>
        </table>
      </div>''';

    test('kart yapisini okur: kod, ad, vize, final, harf', () {
      final courses = parseGrades(card);

      expect(courses, hasLength(1));
      expect(courses.first.code, 'TRD129');
      expect(courses.first.name, 'Türk Dili I');
      expect(courses.first.midtermGrade, 60);
      expect(courses.first.finalGrade, 75);
      expect(courses.first.letterGrade, 'CB');
    });

    test('not girilmemis kartta notlar null kalir', () {
      const empty = '''
        <div class="ex-gc">
          <table class="ex-gt"><tbody><tr class="ex-r ex-gh"><td>
            <div><div class="mb-1">
              <span id="rptNotListesi_lblDersKod_1">YZM201</span>(1) - Nesne Tabanl&#305; Programlama
              <span class="mx-1">|</span>
              <span id="rptNotListesi_lblCardNot_1">Not</span>:
              <span class="text-muted">-</span>
            </div></div>
          </td></tr></tbody></table>
          <table class="ex-gt"><thead><tr><th>S&#305;nav Ad&#305;</th><th>Not</th></tr></thead>
          <tbody><tr><td colspan="5">Kay&#305;t Yok</td></tr></tbody></table>
        </div>''';

      final courses = parseGrades(empty);

      expect(courses, hasLength(1));
      expect(courses.first.code, 'YZM201');
      expect(courses.first.name, 'Nesne Tabanlı Programlama');
      expect(courses.first.midtermGrade, isNull);
      expect(courses.first.finalGrade, isNull);
      expect(courses.first.letterGrade, isNull);
    });
  });

  group('parseSchedule', () {
    test('pivot tabloyu okur: gun, saat, kod, ad, salon', () {
      // Gerçek OBS pivot yapısı: saat satırı + gün hücreleri.
      const html = '''
        <table class="myGridClass mb-0">
          <thead id="theadSch"><tr>
            <th id="thTitle" class="pivot-header pivot-time"><div class="tt-th-inner"><span class="tt-th-txt">Saat</span></div></th>
            <th id="thMonday" class="pivot-header"><div class="tt-th-inner"><span class="tt-th-txt">Pazartesi</span></div></th>
            <th id="thTuesday" class="pivot-header"><div class="tt-th-inner"><span class="tt-th-txt">Sal&#305;</span></div></th>
          </tr></thead>
          <tbody>
            <tr id="rptTimeSlots_trSlot_0">
              <td class="pivot-time" data-label="Saat"><span class="tt-saat-inner"><span class="tt-saat-txt">08:00-08:45</span></span></td>
              <td class="pivot-cell" data-label="Pazartesi">
                <div class="course-info">
                  <div><span class="course-code tt-course-code">YZM201(1)</span></div>
                  <div class="course-name">Nesne Tabanl&#305; Programlama</div>
                  <div class="course-room">BLD-Z-16</div>
                  <div class="course-instructor">Prof. Dr. X</div>
                </div>
              </td>
              <td class="pivot-cell" data-label="Sal&#305;"></td>
            </tr>
          </tbody>
        </table>
      ''';

      final entries = parseSchedule(html);

      expect(entries, hasLength(1));
      expect(entries.first.courseCode, 'YZM201');
      expect(entries.first.courseName, 'Nesne Tabanlı Programlama');
      expect(entries.first.day, 'Pazartesi');
      expect(entries.first.startTime, '08:00');
      expect(entries.first.endTime, '08:45');
      expect(entries.first.classroom, 'BLD-Z-16');
    });

    test('bos programda liste doner', () {
      expect(parseSchedule('<html><body>Yok</body></html>'), isEmpty);
    });
  });

  group('parseAttendance', () {
    test('rpt-row kolonlarini okur ve orani hesaplar', () {
      // Gerçek OBS devamsızlık yapısı: rpt-panel satırları.
      const html = '''
        <div class="rpt-panel-body">
          <div class="row rpt-row">
            <div class="col-1">AFE201 (1)</div>
            <div class="col-3">SE&#199;: Afet Y&#246;netimi</div>
            <div class="col-1 text-center mhide">2+0</div>
            <div class="col-1 text-center mhide">2</div>
            <div class="col-1 text-center mhide">2</div>
            <div class="col-2 mhide">Yaz&#305;l&#305;m M&#252;hendisli&#287;i</div>
            <div class="col-2 d-flex">
              <span class="text-right">(Teorik:6)  (Uygulama:0)</span>
              <a title="Toplam 14 Hafta (28 Saat).&#10;Teorik Toplam&#305; 28 Saat, Devams&#305;zlik Oran&#305; (%30)/8 Saat."></a>
            </div>
          </div>
        </div>
      ''';

      final records = parseAttendance(html);

      expect(records, hasLength(1));
      expect(records.first.courseCode, 'AFE201');
      expect(records.first.courseName, 'SEÇ: Afet Yönetimi');
      expect(records.first.absentHours, 6);
      expect(records.first.totalHours, 28);
      expect(records.first.ratio, closeTo(21.4, 0.1));
      expect(records.first.isExceeding, isFalse);
    });

    test('sinir asildiginda isExceeding dogru olur', () {
      const html = '''
        <div class="rpt-panel-body">
          <div class="row rpt-row">
            <div class="col-1">BIL101 (1)</div>
            <div class="col-3">Programlama</div>
            <div class="col-1">2+0</div>
            <div class="col-1">3</div>
            <div class="col-1">2</div>
            <div class="col-2">Bilgisayar</div>
            <div class="col-2 d-flex">
              <span class="text-right">(Teorik:9)  (Uygulama:0)</span>
              <a title="Toplam 14 Hafta (30 Saat).&#10;Teorik Toplam&#305; 30 Saat, Devams&#305;zlik Oran&#305; (%30)/9 Saat."></a>
            </div>
          </div>
        </div>
      ''';

      final records = parseAttendance(html);

      expect(records.single.absentHours, 9);
      expect(records.single.totalHours, 30);
      expect(records.single.ratio, closeTo(30, 0.01));
      expect(records.single.isExceeding, isTrue);
    });
  });

  group('model json', () {
    test('Course toJson ve fromJson ayni veriyi uretir', () {
      const course = Course(
        code: 'BIL101',
        name: 'Bilgisayar Programlama',
        midtermGrade: 85,
        finalGrade: 90,
        letterGrade: 'AA',
      );

      final restored = Course.fromJson(course.toJson());

      expect(restored.code, course.code);
      expect(restored.name, course.name);
      expect(restored.midtermGrade, 85);
      expect(restored.finalGrade, 90);
      expect(restored.letterGrade, 'AA');
    });

    test('ScheduleEntry tur donusumleri dogru', () {
      final entry = ScheduleEntry.fromJson({
        'courseCode': 'BIL101',
        'courseName': 'Programlama',
        'day': 'Pazartesi',
        'startTime': '09:00',
        'endTime': '10:50',
        'classroom': 'A101',
      });

      expect(entry.toJson()['startTime'], '09:00');
      expect(entry.classroom, 'A101');
    });

    test('AttendanceRecord ratio alanli json uretir', () {
      const record = AttendanceRecord(
        courseCode: 'BIL101',
        courseName: 'Programlama',
        absentHours: 9,
        totalHours: 30,
      );

      final json = record.toJson();

      expect(json['ratio'], closeTo(30, 0.01));
      expect(json['isExceeding'], isTrue);
      expect(AttendanceRecord.fromJson(json).absentHours, 9);
    });
  });

  group('SafeScheduler', () {
    test('her tur arasinda en az on dakika bekler', () {
      final scheduler = SafeScheduler();
      for (var i = 0; i < 20; i++) {
        expect(scheduler.nextDelay(), greaterThanOrEqualTo(const Duration(minutes: 10)));
      }
    });

    test('hata sonrasi bekleme uzar', () {
      final scheduler = SafeScheduler();

      final first = scheduler.nextDelay();
      scheduler.onFailure();
      final afterFailure = scheduler.nextDelay();

      expect(afterFailure, greaterThan(first));
    });

    test('basarili tur sayaci sifirlar', () {
      final scheduler = SafeScheduler();

      scheduler.onFailure();
      scheduler.onFailure();
      scheduler.onSuccess();

      final before = scheduler.nextDelay();
      scheduler.onFailure();
      final after = scheduler.nextDelay();

      // Tek hata, iki hatadan kısa süre üretir.
      expect(before, lessThanOrEqualTo(const Duration(minutes: 15)));
      expect(after, lessThanOrEqualTo(const Duration(minutes: 20)));
    });
  });
}
