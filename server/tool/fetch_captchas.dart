// OBS CAPTCHA görsellerini örneklemek için indirir.
//
// Kullanım: cd server && dart run tool/fetch_captchas.dart <adet> <çıktı_dizini>
//
// Her örnekte yeni bir ASP.NET oturumu açılır (giriş gerekmez); indirilen
// görseller şablon üretimine (supabase/tools/build_templates.ts) girdi olur.
import 'dart:io';

import 'package:obs_core/obs_core.dart';

Future<void> main(List<String> args) async {
  final count = args.isNotEmpty ? int.parse(args[0]) : 12;
  final outDir = Directory(args.length > 1 ? args[1] : 'tool/samples');

  await outDir.create(recursive: true);

  final service = ObsService();
  var saved = 0;

  for (var i = 0; i < count; i++) {
    try {
      final form = await service.prepareLogin();
      final captcha = form.captcha;
      if (captcha == null) {
        stderr.writeln('[$i] captcha görseli alınamadı');
        continue;
      }
      final file = File('${outDir.path}/captcha_$saved.jpg');
      await file.writeAsBytes(captcha, flush: true);
      stdout.writeln('${file.path}\t${captcha.length}');
      saved++;
    } on ObsException catch (e) {
      stderr.writeln('[$i] hata: ${e.message}');
    }
  }

  stdout.writeln('toplam: $saved görsel -> ${outDir.path}');
}
