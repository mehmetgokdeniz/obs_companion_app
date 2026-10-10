import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:obs_core/obs_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yeni not açıklandığında bildirim gönderir.
///
/// Notlar SharedPreferences'ta saklanır, böylece uygulama kapalıyken de
/// değişiklik algılanabilir.
class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'obs_grade_channel';
  static const _channelName = 'OBS Not ve Devamsızlık';

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);
  }

  Future<void> _show(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Yeni not ve devamsızlık değişiklikleri',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body, details);
  }

  /// [isFirstRun] true ise bildirim gönderilmez, sadece mevcut notlar
  /// kaydedilir; böylece ilk girişte geçmiş notlar için spam olmaz.
  Future<void> checkGrades(List<Course> courses, {required bool isFirstRun}) async {
    final prefs = await SharedPreferences.getInstance();

    for (final course in courses) {
      await _compare(prefs, course, 'midterm', course.midtermGrade, 'Vize notu');
      await _compare(prefs, course, 'final', course.finalGrade, 'Final notu');

      final letter = course.letterGrade;
      if (letter != null) {
        await _compare(prefs, course, 'letter', letter.hashCode, 'Harf notu',
            detail: letter);
      }
    }
  }

  /// Devamsızlık sınırına yaklaşan veya aşan dersler için uyarı gönderir.
  Future<void> checkAttendance(List<AttendanceRecord> records) async {
    final prefs = await SharedPreferences.getInstance();

    for (final record in records) {
      final absent = record.absentHours;
      if (absent == null) continue;

      final key = 'att_${record.courseCode}';
      final previous = prefs.getInt(key);

      if (previous != null && previous >= absent) continue;

      await prefs.setInt(key, absent);

      final ratio = record.ratio;
      final detail = ratio == null ? '$absent saat' : '$absent saat (%${ratio.toStringAsFixed(1)})';

      if (record.isExceeding) {
        await _show(
          'Devamsızlık sınırı aşıldı!',
          '${record.courseName}: $detail',
        );
      } else if (absent > 0) {
        await _show(
          'Devamsızlık güncellendi',
          '${record.courseName}: $detail',
        );
      }
    }
  }

  Future<void> _compare(
    SharedPreferences prefs,
    Course course,
    String suffix,
    Object? value,
    String label, {
    String? detail,
  }) async {
    if (value == null) return;

    final key = '${course.identity}_$suffix';
    final previous = prefs.get(key);

    // Not düzeltilmişse eski değeri güncelle, bildirim üretme.
    if (previous == value) return;

    await prefs.setString(key, value.toString());

    if (previous == null) return;

    final shown = detail ?? value.toString();
    final message = previous.toString() != shown
        ? '$label güncellendi: $previous → $shown'
        : '$label açıklandı: $shown';

    await _show('${course.name} — yeni not', message);
  }

  /// Çıkışta tüm not geçmişini siler, bir sonraki girişte "ilk çalıştırma"
  /// gibi davranmasın diye.
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (key.contains('_') || key.startsWith('att_')) {
        await prefs.remove(key);
      }
    }
  }
}
