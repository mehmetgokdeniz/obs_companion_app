// Uçtan uca manel akış doğrulaması.
//
//   dart run tool/admin_e2e.dart <base> <token> fetch   # görseli indir
//   dart run tool/admin_e2e.dart <base> <token> post 70 # aynı formu kullan
//
// `fetch` sunucu tarafında pendingForm'u hazırlar; `post` onu gönderir.
// Arada başka bir /admin/captcha çağrısı olmamalı (form tazelenir).
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('kullanım: dart run tool/admin_e2e.dart <base_url> <token> fetch|post <cevap>');
    exitCode = 2;
    return;
  }
  final base = args[0].replaceAll(RegExp(r'/+$'), '');
  final token = args[1];
  final mode = args[2];
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);

  try {
    if (mode == 'fetch') {
      final pageUrl = Uri.parse('$base/admin/captcha?token=${Uri.encodeQueryComponent(token)}');
      final pageReq = await client.getUrl(pageUrl);
      final pageResp = await pageReq.close();
      final html = await utf8.decodeStream(pageResp);
      print('PAGE_STATUS=${pageResp.statusCode}');

      final imgMatch = RegExp(r'base64,([^"]+)"').firstMatch(html);
      if (imgMatch == null) {
        stderr.writeln('görsel bulunamadı: ${html.substring(0, html.length.clamp(0, 300))}');
        exitCode = 1;
        return;
      }
      final imgBytes = base64Decode(imgMatch.group(1)!);
      final imgPath = '${Directory.systemTemp.path}${Platform.pathSeparator}admin_e2e.jpg';
      await File(imgPath).writeAsBytes(imgBytes);
      print('GORESEL=$imgPath Boyut=${imgBytes.length}');
      return;
    }

    if (mode == 'post') {
      if (args.length < 4) {
        stderr.writeln('post için cevap gerekli');
        exitCode = 2;
        return;
      }
      final answer = args[3];
      final postUrl = Uri.parse('$base/admin/login?token=${Uri.encodeQueryComponent(token)}');
      final postReq = await client.postUrl(postUrl);
      postReq.followRedirects = false;
      postReq.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      postReq.write('securityCode=${Uri.encodeQueryComponent(answer)}');
      final postResp = await postReq.close();
      await drain(postResp);
      print('POST_STATUS=${postResp.statusCode}');
      print('POST_LOCATION=${postResp.headers.value(HttpHeaders.locationHeader)}');

      final allReq = await client.getUrl(Uri.parse('$base/api/v1/all'));
      allReq.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final allResp = await allReq.close();
      final body = await utf8.decodeStream(allResp);
      print('ALL_STATUS=${allResp.statusCode}');
      if (allResp.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        print('OGRENCI=${json['studentName']}');
        print('DERS_SAYISI=${(json['courses'] as List).length}');
        print('PROGRAM=${(json['schedule'] as List).length}');
        print('DEVAMSIZLIK=${(json['attendance'] as List).length}');
        for (final c in (json['courses'] as List).take(3)) {
          print('  DERS: ${c['code']} ${c['name']} vize=${c['midtermGrade']} harf=${c['letterGrade']}');
        }
      } else {
        print('ALL_BODY=${body.substring(0, body.length.clamp(0, 400))}');
      }
      return;
    }

    stderr.writeln('bilinmeyen mod: $mode');
    exitCode = 2;
  } finally {
    client.close(force: true);
  }
}

Future<void> drain(HttpClientResponse r) async {
  await for (final _ in r) {}
}
