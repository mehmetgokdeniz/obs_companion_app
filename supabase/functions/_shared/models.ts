/// Veri modelleri — packages/obs_core/lib/src/course_model.dart portu.

export interface Course {
  code: string;
  name: string;
  day: string;
  time: string;
  classroom: string;
  midtermGrade: number | null;
  finalGrade: number | null;
  letterGrade: string | null;
}

export function courseToJson(c: Course): Record<string, unknown> {
  return {
    code: c.code,
    name: c.name,
    day: c.day,
    time: c.time,
    classroom: c.classroom,
    midtermGrade: c.midtermGrade,
    finalGrade: c.finalGrade,
    letterGrade: c.letterGrade,
  };
}

export interface ScheduleEntry {
  courseCode: string;
  courseName: string;
  day: string;
  startTime: string;
  endTime: string;
  classroom: string;
}

export function scheduleEntryToJson(e: ScheduleEntry): Record<string, unknown> {
  return {
    courseCode: e.courseCode,
    courseName: e.courseName,
    day: e.day,
    startTime: e.startTime,
    endTime: e.endTime,
    classroom: e.classroom,
  };
}

export interface AttendanceRecord {
  courseCode: string;
  courseName: string;
  absentHours: number | null;
  totalHours: number | null;
  status: string | null;
}

/// Devamsızlık yüzdesi; toplam saat yoksa veya sıfırsa null.
export function attendanceRatio(r: AttendanceRecord): number | null {
  const total = r.totalHours;
  if (total == null || total <= 0) return null;
  return (r.absentHours ?? 0) / total * 100;
}

/// Sınır (%30) aşılmış mı?
export function attendanceIsExceeding(r: AttendanceRecord): boolean {
  const ratio = attendanceRatio(r);
  return ratio != null && ratio >= 30;
}

export function attendanceToJson(r: AttendanceRecord): Record<string, unknown> {
  return {
    courseCode: r.courseCode,
    courseName: r.courseName,
    absentHours: r.absentHours,
    totalHours: r.totalHours,
    status: r.status,
    ratio: attendanceRatio(r),
    isExceeding: attendanceIsExceeding(r),
  };
}

/// API'nin tek istekte döndürüdüğü taze veri (server Snapshot.toJson).
export interface Snapshot {
  studentName: string | null;
  fetchedAt: string;
  courses: Course[];
  schedule: ScheduleEntry[];
  attendance: AttendanceRecord[];
}

export function snapshotToJson(s: Snapshot): Record<string, unknown> {
  return {
    studentName: s.studentName,
    fetchedAt: s.fetchedAt,
    courses: s.courses.map(courseToJson),
    schedule: s.schedule.map(scheduleEntryToJson),
    attendance: s.attendance.map(attendanceToJson),
  };
}
