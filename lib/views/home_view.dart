import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:obs_core/obs_core.dart';
import 'package:provider/provider.dart';

import '../providers/obs_provider.dart';
import 'captcha_dialog.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ObsProvider>();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF110A1D),
            Color(0xFF1A1130),
            Color(0xFF251A40),
          ],
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: Text(provider.studentName ?? 'Dersler ve Notlar'),
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              surfaceTintColor: Colors.transparent,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: provider.isLoading ? null : provider.refreshAll,
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: provider.isLoading
                      ? null
                      : () async {
                          await provider.disconnect();
                        },
                ),
              ],
            ),
            body: provider.isLoading && provider.courses.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      if (provider.needsManualCaptcha)
                        _CaptchaBanner(
                          onSolve: () => showCaptchaDialog(context),
                        ),
                      if (provider.errorMessage != null)
                        _ErrorBanner(message: provider.errorMessage!),
                      Expanded(
                        child: IndexedStack(
                          index: _tab,
                          children: [
                            _GradesTab(courses: provider.courses),
                            _ScheduleTab(entries: provider.schedule),
                            _AttendanceTab(records: provider.attendance),
                          ],
                        ),
                      ),
                    ],
                  ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) => setState(() => _tab = index),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.school), label: 'Notlar'),
                NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Program'),
                NavigationDestination(icon: Icon(Icons.event_busy), label: 'Devamsızlık'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptchaBanner extends StatelessWidget {
  final VoidCallback onSolve;

  const _CaptchaBanner({required this.onSolve});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.security, color: Colors.amber.shade900),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Oturum yenilemek için güvenlik kodu gerekiyor.',
              style: TextStyle(color: Color(0xFF5D4300)),
            ),
          ),
          TextButton(
            onPressed: onSolve,
            child: const Text('Çöz'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.red.shade50,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: Colors.red.shade900))),
        ],
      ),
    );
  }
}

class _GradesTab extends StatelessWidget {
  final List<Course> courses;

  const _GradesTab({required this.courses});

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return const _EmptyState('Kayıtlı ders bulunamadı.');
    }

    return ListView.builder(
      itemCount: courses.length,
      itemBuilder: (context, index) {
        final course = courses[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Text(course.code.isNotEmpty ? course.code[0] : 'D'),
            ),
            title: Text(course.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Kod: ${course.code}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GradeBox(label: 'Vize', value: course.midtermGrade),
                const SizedBox(width: 10),
                _GradeBox(label: 'Final', value: course.finalGrade),
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    course.letterGrade ?? '-',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GradeBox extends StatelessWidget {
  final String label;
  final int? value;

  const _GradeBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(
          '${value ?? '-'}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _ScheduleTab extends StatelessWidget {
  final List<ScheduleEntry> entries;

  const _ScheduleTab({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _EmptyState('Ders programı bulunamadı.');
    }

    final weekdayOrder = <String>[
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
    ];

    final timeSlots = <String>{};
    final byDayAndTime = <String, Map<String, List<ScheduleEntry>>>{};

    for (final entry in entries) {
      final normalizedDay = _normalizeDay(entry.day);
      final slot = entry.startTime.isNotEmpty
          ? '${entry.startTime} - ${entry.endTime}'.trim()
          : (entry.endTime.isNotEmpty ? entry.endTime : 'Saat yok');

      timeSlots.add(slot);
      final dayMap = byDayAndTime.putIfAbsent(normalizedDay, () => <String, List<ScheduleEntry>>{});
      dayMap.putIfAbsent(slot, () => <ScheduleEntry>[]).add(entry);
    }

    final sortedSlots = timeSlots.toList()
      ..sort((a, b) {
        final aMinutes = _toMinutes(a.split(' - ').first);
        final bMinutes = _toMinutes(b.split(' - ').first);
        return aMinutes.compareTo(bMinutes);
      });

    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 720),
            child: DataTable(
              columnSpacing: 12,
              horizontalMargin: 8,
              // Varsayılan satır yüksekliği 48px; ders adı + sınıf kutusu
              // bunu aşıp alt satıra taşıyordu. Satır içeriğe göre büyür.
              dataRowMinHeight: 48,
              dataRowMaxHeight: double.infinity,
              columns: [
                const DataColumn(label: Text('Saat')),
                ...weekdayOrder.map(
                  (day) => DataColumn(label: Text(day, style: const TextStyle(fontWeight: FontWeight.bold))),
                ),
              ],
              rows: sortedSlots.map((slot) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        slot,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    ...weekdayOrder.map((day) {
                      final dayKey = _normalizeDay(day);
                      final items = byDayAndTime[dayKey]?[slot] ?? const <ScheduleEntry>[];

                      return DataCell(
                        Align(
                          alignment: Alignment.centerLeft,
                          child: items.isEmpty
                              ? const Text('—', style: TextStyle(color: Colors.grey))
                              : Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: items.map((item) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      constraints: const BoxConstraints(maxWidth: 170),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.08),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (item.courseName.isNotEmpty)
                                            Text(
                                              item.courseName,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          if (item.classroom.isNotEmpty)
                                            Text(
                                              'Sınıf: ${item.classroom}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          if (item.courseCode.isNotEmpty)
                                            Text(
                                              item.courseCode,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.white60,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ),
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  static String _normalizeDay(String day) {
    final value = day.trim().toLowerCase();
    final normalized = value
        .replaceAll('ı', 'i')
        .replaceAll('ş', 's')
        .replaceAll('ç', 'c')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u')
        .replaceAll('ğ', 'g');

    if (normalized.contains('pazartesi')) return 'pazartesi';
    if (normalized.contains('sali') || normalized.contains('salı')) return 'salı';
    if (normalized.contains('carsamba') || normalized.contains('çarşamba')) return 'çarşamba';
    if (normalized.contains('persembe') || normalized.contains('perşembe')) return 'perşembe';
    if (normalized.contains('cuma')) return 'cuma';
    return normalized;
  }

  static int _toMinutes(String timeText) {
    final text = timeText.trim();
    if (text.isEmpty || !text.contains(':')) return 0;

    final parts = text.split(':');
    if (parts.length < 2) return 0;

    try {
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      return hour * 60 + minute;
    } on FormatException {
      return 0;
    }
  }
}

class _AttendanceTab extends StatelessWidget {
  final List<AttendanceRecord> records;

  const _AttendanceTab({required this.records});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const _EmptyState('Devamsızlık bilgisi bulunamadı.');
    }

    return ListView.builder(
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        final ratio = record.ratio;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ListTile(
            leading: Icon(
              record.isExceeding ? Icons.error : Icons.check_circle,
              color: record.isExceeding ? Colors.red : Colors.green,
            ),
            title: Text(record.courseName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              ratio == null
                  ? 'Devamsızlık: ${record.absentHours ?? '-'}'
                  : 'Devamsızlık: ${record.absentHours ?? 0} / ${record.totalHours} (%${ratio.toStringAsFixed(1)})',
            ),
            trailing: record.status == null
                ? null
                : Text(record.status!, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState(this.message);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
        ),
      ),
    );
  }
}
