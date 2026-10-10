// Not Listesi sayfasında dönem değiştirip (ASP.NET postback) geçmiş dönem
// notlarını ham HTML olarak indirir.
//
// dart run tool/dump_period.dart [yilKod]   ör: 20251
import 'dart:convert';
import 'dart:io';

import 'package:obs_core/obs_core.dart';

Future<void> main(List<String> args) async {
  final wanted = args.isNotEmpty ? args[0] : '20251';

  final cookieFile = File('data${Platform.pathSeparator}session.json');
  if (!await cookieFile.exists()) {
    stderr.writeln('session.json yok.');
    exitCode = 78;
    return;
  }
  final state = jsonDecode(await cookieFile.readAsString()) as Map<String, dynamic>;

  final service = ObsService();
  service.restoreSession(state['cookie'] as String? ?? '');
  if (!await service.isSessionAlive()) {
    stderr.writeln('oturum ölü.');
    exitCode = 1;
    return;
  }

  await service.discoverPages();
  final menuUrl = service.menuUrlFor('Not Listesi');
  if (menuUrl == null) {
    stderr.writeln('Not Listesi menüde bulunamadı.');
    exitCode = 1;
    return;
  }

  // Not Listesi sayfasını ilk kez çek (viewstate al).
  final first = await service.fetchPageHtml('Not Listesi');
  // Form action'ı yanıltıcı olabiliyor (gkm yönlendirmesi); gerçek adres
  // menü gkm → caller → gkm zincirinden sonra /oibs/std/not_listesi_op.aspx.
  final pageUrl = 'https://obs.alparslan.edu.tr/oibs/std/not_listesi_op.aspx';
  print('POST_ADRESI=$pageUrl');

  final form = _hiddenFields(first);
  print('VIEWSTATE_LEN=${(form['__VIEWSTATE'] ?? '').length}');
  print('DONEMLER=${form.entries.where((e) => e.key.contains('cmbDonem')).map((e) => '${e.key}=${e.value}').toList()}');

  // Mevcut seçili dönemi bul.
  final selected = RegExp(r'<option selected="selected" value="(\d+)"').firstMatch(first)?.group(1);
  print('SECILI_DONEM=$selected');

  if (selected == wanted) {
    final out = File('${Directory.systemTemp.path}${Platform.pathSeparator}donem_$wanted.html');
    await out.writeAsString(first, flush: true);
    print('AYNI_DONEM=${out.path}');
    return;
  }

  // Postback: __EVENTTARGET = cmbDonemler.
  final body = <String, String>{
    for (final e in form.entries) e.key: e.value,
    '__EVENTTARGET': 'cmbDonemler',
    '__EVENTARGUMENT': '',
    'cmbDonemler': wanted,
  };

  final cookie = state['cookie'] as String? ?? '';
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final req = await client.postUrl(Uri.parse(pageUrl));
    req.followRedirects = true;
    req.headers.set(HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36');
    req.headers.set(HttpHeaders.acceptLanguageHeader, 'tr-TR,tr;q=0.9');
    req.headers.set(HttpHeaders.refererHeader, 'https://obs.alparslan.edu.tr/oibs/std/index.aspx?curOp=0');
    req.headers.set(HttpHeaders.cookieHeader, cookie);
    req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
    req.write(body.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&'));

    final resp = await req.close();
    final html = await utf8.decodeStream(resp);
    print('STATUS=${resp.statusCode}');
    final loc = resp.headers.value(HttpHeaders.locationHeader);
    print('URL=${loc ?? '(aynı)'}');

    var finalHtml = html;
    // 302 olursa caller.aspx'i takip et (çerçeve sayfası gerçek içeriği yükler).
    if (loc != null) {
      final followUrl = loc.startsWith('http') ? loc : 'https://obs.alparslan.edu.tr$loc';
      final fReq = await client.getUrl(Uri.parse(followUrl));
      fReq.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36');
      fReq.headers.set(HttpHeaders.cookieHeader, cookie);
      fReq.headers.set(HttpHeaders.refererHeader, pageUrl);
      final fResp = await fReq.close();
      finalHtml = await utf8.decodeStream(fResp);
      print('FOLLOW_STATUS=${fResp.statusCode}');
      print('FOLLOW_URL=$followUrl');
    }

    final out = File('${Directory.systemTemp.path}${Platform.pathSeparator}donem_$wanted.html');
    await out.writeAsString(finalHtml, flush: true);
    print('KAYDEDILDI=${out.path} (${finalHtml.length} bayt)');
    print('DONEM_SECIMI=${finalHtml.contains('value="$wanted"')}');
    print('KART_SAYISI=${RegExp('rptNotListesi_lblDersKod_').allMatches(finalHtml).length}');
  } finally {
    client.close(force: true);
  }
}

Map<String, String> _hiddenFields(String html) {
  final result = <String, String>{};
  for (final m in RegExp(r'<input[^>]*type="hidden"[^>]*>').allMatches(html)) {
    final tag = m.group(0)!;
    final name = RegExp(r'name="([^"]*)"').firstMatch(tag)?.group(1);
    final value = RegExp(r'value="([^"]*)"').firstMatch(tag)?.group(1) ?? '';
    if (name != null && name.isNotEmpty) result[name] = value;
  }
  return result;
}
