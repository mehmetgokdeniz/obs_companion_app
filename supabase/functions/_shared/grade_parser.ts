import { parseHTML } from 'npm:linkedom';

import type { AttendanceRecord, Course, ScheduleEntry } from './models.ts';

/// OBS sayfa parser'ları.
/// packages/obs_core/lib/src/grade_parser.dart portu.

const ELEMENT_NODE = 1;
const TEXT_NODE = 3;

/// Beyaz uzunluğunu tek boşluğa indirir.
function clean(value: string): string {
  return value.replace(/\s+/g, ' ').trim();
}

function text(el: Element | null | undefined): string {
  return el == null ? '' : clean(el.textContent ?? '');
}

/// "AFE201 (1)" / "YZM201(1)" -> "AFE201" (grup numarası atılır).
function stripGroup(value: string): string {
  return value.replace(/\s*\(\d+\)\s*$/, '').trim();
}

/// Yalnızca tam sayı not okur ("60" tamam, "-" ve "61.73" değil).
function grade(value: string): number | null {
  const t = clean(value);
  return /^\d+$/.test(t) ? Number(t) : null;
}

function matchInt(pattern: RegExp, value: string): number | null {
  const match = pattern.exec(value);
  if (match == null) return null;
  return /^\d+$/.test(match[1]) ? Number(match[1]) : null;
}

/// Ders kartındaki başlık metninden kodun sağındaki ders adını çeker.
///
/// Kart HTML'i `</span>(1) - Ders Adı` biçimindedir; ad, kod span'inden
/// sonraki düz metin düğümleridir.
function nameAfter(codeSpan: Element): string {
  const parent = codeSpan.parentNode;
  if (parent == null) return '';

  const nodes = Array.from(parent.childNodes);
  const index = nodes.indexOf(codeSpan);
  if (index < 0) return '';

  let buffer = '';
  for (let i = index + 1; i < nodes.length; i++) {
    const node = nodes[i];
    if (node.nodeType === ELEMENT_NODE) break; // Sıradaki span adı sonlandırır.
    if (node.nodeType === TEXT_NODE) buffer += node.textContent ?? '';
  }

  const match = /\(\d+\)\s*-\s*(.*)/.exec(buffer);
  return match == null ? '' : clean(match[1]);
}

/// Not listesi sayfasındaki ders kartlarını çevirir.
///
/// OBS bu sayfayı düz tablo yerine kart yapısında verir:
/// `div.ex-gc` içinde kod span'i, ders adı, sınıf ortalaması, harf notu ve
/// altında ayrı bir sınav tablosu (Vize/Final) bulunur.
export function parseGrades(html: string): Course[] {
  const { document } = parseHTML(html);
  const courses: Course[] = [];

  for (const card of document.querySelectorAll('div.ex-gc')) {
    const codeSpan = card.querySelector('span[id^="rptNotListesi_lblDersKod_"]');
    if (codeSpan == null) continue;

    const code = text(codeSpan);
    if (code.length === 0) continue;

    // Harf notu .grade-badge içinde; dönem başında yok ("-").
    const badge = card.querySelector('.grade-badge');
    const badgeText = badge == null ? '' : text(badge);
    const letter = badgeText.length === 0 ? null : badgeText;

    let midterm: number | null = null;
    let finalExam: number | null = null;
    for (const row of card.querySelectorAll('table.ex-gt tbody tr')) {
      const cells = row.querySelectorAll('td');
      if (cells.length < 2) continue;

      const exam = text(cells[0]).toLowerCase();
      const score = grade(text(cells[1]));
      if (score == null) continue;

      if (exam.includes('vize')) midterm = score;
      if (exam.includes('final')) finalExam = score;
    }

    courses.push({
      code,
      name: nameAfter(codeSpan),
      day: '',
      time: '',
      classroom: '',
      midtermGrade: midterm,
      finalGrade: finalExam,
      letterGrade: letter,
    });
  }

  return courses;
}

/// Haftalık ders programını çevirir.
///
/// OBS programı pivot tablo olarak verir: satırlar saat aralığı, sütunlar
/// günlerdir; dolu hücrelerde `.course-info` bloğu bulunur.
export function parseSchedule(html: string): ScheduleEntry[] {
  const { document } = parseHTML(html);
  const table = document.querySelector('table.myGridClass');
  if (table == null) return [];

  const entries: ScheduleEntry[] = [];
  for (const row of table.querySelectorAll('tbody tr')) {
    const timeText = text(row.querySelector('.tt-saat-txt'));
    if (timeText.length === 0) continue;

    // "08:00-08:45" -> başlangıç / bitiş.
    const parts = timeText.split('-');
    const start = parts[0].trim();
    const end = parts.length > 1 ? parts[1].trim() : '';

    for (const cell of row.querySelectorAll('td.pivot-cell')) {
      const info = cell.querySelector('.course-info');
      if (info == null) continue;

      const code = text(info.querySelector('.course-code'));
      if (code.length === 0) continue;

      entries.push({
        courseCode: stripGroup(code),
        courseName: text(info.querySelector('.course-name')),
        day: cell.getAttribute('data-label') ?? '',
        startTime: start,
        endTime: end,
        classroom: text(info.querySelector('.course-room')),
      });
    }
  }

  return entries;
}

/// Devamsızlık sayfasını çevirir.
///
/// Satırlar `div.rpt-row` içindeki kolonlardan oluşur. Son kolonda
/// `(Teorik:6) (Uygulama:0)` biçiminde devamsızlık, yanındaki bilgi
/// bağlantısının `title` özniteliğinde ise toplam saat
/// (`Toplam 14 Hafta (28 Saat)`) yer alır.
export function parseAttendance(html: string): AttendanceRecord[] {
  const { document } = parseHTML(html);
  const records: AttendanceRecord[] = [];

  for (const row of document.querySelectorAll('div.rpt-row')) {
    const cols = Array.from(row.children);
    if (cols.length < 7) continue;

    const code = text(cols[0] as Element);
    if (code.length === 0) continue;

    let absenceText = '';
    let infoTitle: string | null = null;
    for (const col of cols) {
      const t = text(col as Element);
      if (t.includes('Teorik:')) absenceText = t;
      const info = (col as Element).querySelector('a[title]');
      if (info != null) infoTitle = info.getAttribute('title');
    }

    const theory = matchInt(/Teorik:\s*(\d+)/, absenceText);
    const practice = matchInt(/Uygulama:\s*(\d+)/, absenceText);

    const totalHours = infoTitle == null
      ? null
      : matchInt(/Hafta\s*\((\d+)\s*Saat\)/, infoTitle);

    records.push({
      courseCode: stripGroup(code),
      courseName: text(cols[1] as Element),
      absentHours: (theory ?? 0) + (practice ?? 0),
      totalHours,
      status: null,
    });
  }

  return records;
}
