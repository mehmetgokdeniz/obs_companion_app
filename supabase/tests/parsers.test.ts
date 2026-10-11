import { assert, assertEquals } from 'jsr:@std/assert';

import { parseAttendance, parseGrades, parseSchedule } from '../functions/_shared/grade_parser.ts';
import { parseMenu } from '../functions/_shared/menu_parser.ts';
import {
  attendanceIsExceeding,
  attendanceRatio,
  attendanceToJson,
  courseToJson,
} from '../functions/_shared/models.ts';

// packages/obs_core/test/obs_core_test.dart parser grupları portu.

Deno.test('parseMenu: gkm adreslerini menu_close icinden cikarir', () => {
  const html = `
        <a class="nav-link"
           onclick="menu_close(this,'/oibs/start.aspx?gkm=abc123');" href="#">
          <p>Not Listesi</p>
        </a>`;

  const links = parseMenu(html);

  assertEquals(links.length, 1);
  assertEquals(links[0].title, 'Not Listesi');
  assertEquals(links[0].url, 'https://obs.alparslan.edu.tr/oibs/start.aspx?gkm=abc123');
});

Deno.test('parseMenu: href ile gelen baglantilari da okur', () => {
  const html = `
        <a class="nav-link" href="/oibs/start.aspx?gkm=xyz" target="_blank">
          <p>Transkript</p>
        </a>`;

  const links = parseMenu(html);

  assertEquals(links.length, 1);
  assertEquals(links[0].title, 'Transkript');
  assertEquals(links[0].url, 'https://obs.alparslan.edu.tr/oibs/start.aspx?gkm=xyz');
});

// Gerçek OBS kart yapısı: div.ex-gc + kod span'i + sınav tablosu.
const gradeCard = `
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
      </div>`;

Deno.test('parseGrades: kart yapisini okur: kod, ad, vize, final, harf', () => {
  const courses = parseGrades(gradeCard);

  assertEquals(courses.length, 1);
  assertEquals(courses[0].code, 'TRD129');
  assertEquals(courses[0].name, 'Türk Dili I');
  assertEquals(courses[0].midtermGrade, 60);
  assertEquals(courses[0].finalGrade, 75);
  assertEquals(courses[0].letterGrade, 'CB');
});

Deno.test('parseGrades: not girilmemis kartta notlar null kalir', () => {
  const empty = `
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
        </div>`;

  const courses = parseGrades(empty);

  assertEquals(courses.length, 1);
  assertEquals(courses[0].code, 'YZM201');
  assertEquals(courses[0].name, 'Nesne Tabanlı Programlama');
  assertEquals(courses[0].midtermGrade, null);
  assertEquals(courses[0].finalGrade, null);
  assertEquals(courses[0].letterGrade, null);
});

Deno.test('parseSchedule: pivot tabloyu okur: gun, saat, kod, ad, salon', () => {
  // Gerçek OBS pivot yapısı: saat satırı + gün hücreleri.
  const html = `
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
        </table>`;

  const entries = parseSchedule(html);

  assertEquals(entries.length, 1);
  assertEquals(entries[0].courseCode, 'YZM201');
  assertEquals(entries[0].courseName, 'Nesne Tabanlı Programlama');
  assertEquals(entries[0].day, 'Pazartesi');
  assertEquals(entries[0].startTime, '08:00');
  assertEquals(entries[0].endTime, '08:45');
  assertEquals(entries[0].classroom, 'BLD-Z-16');
});

Deno.test('parseSchedule: bos programda liste doner', () => {
  assertEquals(parseSchedule('<html><body>Yok</body></html>').length, 0);
});

Deno.test('parseAttendance: rpt-row kolonlarini okur ve orani hesaplar', () => {
  // Gerçek OBS devamsızlık yapısı: rpt-panel satırları.
  const html = `
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
        </div>`;

  const records = parseAttendance(html);

  assertEquals(records.length, 1);
  assertEquals(records[0].courseCode, 'AFE201');
  assertEquals(records[0].courseName, 'SEÇ: Afet Yönetimi');
  assertEquals(records[0].absentHours, 6);
  assertEquals(records[0].totalHours, 28);
  const ratio = attendanceRatio(records[0]);
  assert(ratio != null && Math.abs(ratio - 21.4) < 0.1);
  assertEquals(attendanceIsExceeding(records[0]), false);
});

Deno.test('parseAttendance: sinir asildiginda isExceeding dogru olur', () => {
  const html = `
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
        </div>`;

  const records = parseAttendance(html);

  assertEquals(records.length, 1);
  assertEquals(records[0].absentHours, 9);
  assertEquals(records[0].totalHours, 30);
  const ratio = attendanceRatio(records[0]);
  assert(ratio != null && Math.abs(ratio - 30) < 0.01);
  assertEquals(attendanceIsExceeding(records[0]), true);
});

Deno.test('model json: course toJson alanlari dogru', () => {
  const json = courseToJson({
    code: 'BIL101',
    name: 'Bilgisayar Programlama',
    day: '',
    time: '',
    classroom: '',
    midtermGrade: 85,
    finalGrade: 90,
    letterGrade: 'AA',
  });

  assertEquals(json['code'], 'BIL101');
  assertEquals(json['midtermGrade'], 85);
  assertEquals(json['finalGrade'], 90);
  assertEquals(json['letterGrade'], 'AA');
});

Deno.test('model json: attendance ratio alanli json uretir', () => {
  const json = attendanceToJson({
    courseCode: 'BIL101',
    courseName: 'Programlama',
    absentHours: 9,
    totalHours: 30,
    status: null,
  });

  const ratio = json['ratio'] as number;
  assert(Math.abs(ratio - 30) < 0.01);
  assertEquals(json['isExceeding'], true);
  assertEquals(json['absentHours'], 9);
});
