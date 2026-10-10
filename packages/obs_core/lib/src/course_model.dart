/// Bir dersin not bilgileri.
class Course {
  final String code;
  final String name;
  final String day;
  final String time;
  final String classroom;
  final int? midtermGrade;
  final int? finalGrade;
  final String? letterGrade;

  const Course({
    required this.code,
    required this.name,
    this.day = '',
    this.time = '',
    this.classroom = '',
    this.midtermGrade,
    this.finalGrade,
    this.letterGrade,
  });

  /// Bildirim kısmında notları ayırt etmek için kullanılır.
  String get identity => '$code|$name';

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'day': day,
        'time': time,
        'classroom': classroom,
        'midtermGrade': midtermGrade,
        'finalGrade': finalGrade,
        'letterGrade': letterGrade,
      };

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        day: json['day'] as String? ?? '',
        time: json['time'] as String? ?? '',
        classroom: json['classroom'] as String? ?? '',
        midtermGrade: (json['midtermGrade'] as num?)?.toInt(),
        finalGrade: (json['finalGrade'] as num?)?.toInt(),
        letterGrade: json['letterGrade'] as String?,
      );
}

/// Haftalık ders programındaki tek bir ders saatinin bilgileri.
class ScheduleEntry {
  final String courseCode;
  final String courseName;
  final String day;
  final String startTime;
  final String endTime;
  final String classroom;

  const ScheduleEntry({
    required this.courseCode,
    required this.courseName,
    required this.day,
    required this.startTime,
    required this.endTime,
    this.classroom = '',
  });

  Map<String, dynamic> toJson() => {
        'courseCode': courseCode,
        'courseName': courseName,
        'day': day,
        'startTime': startTime,
        'endTime': endTime,
        'classroom': classroom,
      };

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) => ScheduleEntry(
        courseCode: json['courseCode'] as String? ?? '',
        courseName: json['courseName'] as String? ?? '',
        day: json['day'] as String? ?? '',
        startTime: json['startTime'] as String? ?? '',
        endTime: json['endTime'] as String? ?? '',
        classroom: json['classroom'] as String? ?? '',
      );
}

/// Bir dersin devamsızlık bilgisi.
class AttendanceRecord {
  final String courseCode;
  final String courseName;
  final int? absentHours;
  final int? totalHours;
  final String? status;

  const AttendanceRecord({
    required this.courseCode,
    required this.courseName,
    this.absentHours,
    this.totalHours,
    this.status,
  });

  /// Devamsızlık yüzdesi, sınırlı değerler geldiğinde hesaplanır.
  double? get ratio {
    final total = totalHours;
    if (total == null || total <= 0) return null;
    return (absentHours ?? 0) / total * 100;
  }

  /// Devamsızlık sınırını aşmış mı?
  bool get isExceeding {
    final r = ratio;
    return r != null && r >= 30;
  }

  Map<String, dynamic> toJson() => {
        'courseCode': courseCode,
        'courseName': courseName,
        'absentHours': absentHours,
        'totalHours': totalHours,
        'status': status,
        'ratio': ratio,
        'isExceeding': isExceeding,
      };

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) =>
      AttendanceRecord(
        courseCode: json['courseCode'] as String? ?? '',
        courseName: json['courseName'] as String? ?? '',
        absentHours: (json['absentHours'] as num?)?.toInt(),
        totalHours: (json['totalHours'] as num?)?.toInt(),
        status: json['status'] as String?,
      );
}
