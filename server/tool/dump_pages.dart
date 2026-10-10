// Diskteki oturum çereziyle gerçek OBS sayfalarını ham HTML olarak indirir.
// Parser'ları gerçek yapıya göre düzeltmek için kullanılır.
//
// dart run tool/dump_pages.dart
import 'dart:convert';
import 'dart:io';

import 'package:obs_core/obs_core.dart';

Future<void> main() async {
  final dataDir = 'data';
  final cookieFile = File('$dataDir${Platform.pathSeparator}session.json');
  if (!await cookieFile.exists()) {
    stderr.writeln('session.json yok; önce sunucuyu giriş yapmış halde çalıştırın.');
    exitCode = 78;
    return;
  }

  final state = jsonDecode(await cookieFile.readAsString()) as Map<String, dynamic>;
  final cookie = state['cookie'] as String? ?? '';
  if (cookie.isEmpty) {
    stderr.writeln('cookie boş.');
    exitCode = 78;
    return;
  }

  final outDir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}obs_pages');
  await outDir.create(recursive: true);

  final service = ObsService();
  service.restoreSession(cookie);

  if (!await service.isSessionAlive()) {
    stderr.writeln('oturum ölü.');
    exitCode = 1;
    return;
  }
  print('OTURUM_CANLI=true');

  await service.discoverPages();
  print('OGRENCI_ADI=${service.studentName}');

  // Ana sayfa (index.aspx) — öğrenci adı buradan okunuyor mu?
  final homeHtml = await service.fetchPageHtmlAnaSayfa();
  final homeFile = File('${outDir.path}${Platform.pathSeparator}_home.html');
  await homeFile.writeAsString(homeHtml, flush: true);
  print('ANA_SAYFA=${homeFile.path} (${homeHtml.length} bayt)');
  print('ANA_SAYFA_ADSOYAD_VAR=${homeHtml.contains('lblOgrenciAdSoyad')}');

  // Menü başlıklarını ve sayfaları indir.
  for (final title in const [
    'Not Listesi',
    'Ders Programı',
    'Bölüm Ders Programı',
    'Devamsızlık Durumu',
    'Transkript',
  ]) {
    try {
      final html = await service.fetchPageHtml(title);
      final safe = title.replaceAll(RegExp(r'[^\w]+'), '_');
      final file = File('${outDir.path}${Platform.pathSeparator}$safe.html');
      await file.writeAsString(html, flush: true);
      print('KAYDEDILDI=$title -> ${file.path} (${html.length} bayt)');
    } on ObsException catch (e) {
      print('HATA=$title -> ${e.message}');
    }
  }

  print('CIKTI_DIZINI=${outDir.path}');
}
