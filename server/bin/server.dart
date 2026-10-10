import 'dart:io';

import 'package:obs_api_server/api.dart';
import 'package:obs_api_server/session_manager.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Yapılandırma ortam değişkenlerinden, yoksa `.env` dosyasından okunur.
///
/// Gerekli: `API_TOKEN` (istemcilerin taşıdığı erişim anahtarı).
/// OBS kimlik bilgileri `OBS_USERNAME` / `OBS_PASSWORD`.
/// İsteğe bağlı: `PORT` (varsayılan 8080), `DATA_DIR` (varsayılan `data`).
Map<String, String> loadConfig() {
  final config = Map<String, String>.from(Platform.environment);

  final envFile = File('.env');
  if (envFile.existsSync()) {
    for (final line in envFile.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final key = trimmed.substring(0, eq).trim();
      var value = trimmed.substring(eq + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      config.putIfAbsent(key, () => value);
    }
  }

  return config;
}

Future<void> main() async {
  final config = loadConfig();

  final token = config['API_TOKEN'];
  if (token == null || token.isEmpty) {
    stderr.writeln(
      'API_TOKEN tanımlı değil. Sunucu başlatılamıyor; '
      '.env dosyasına API_TOKEN=... ekleyin.',
    );
    exitCode = 78; // EX_CONFIG
    return;
  }

  final port = int.tryParse(config['PORT'] ?? '') ?? 8080;
  final dataDir = config['DATA_DIR'] ?? 'data';

  final sessions = SessionManager(
    username: config['OBS_USERNAME'] ?? '',
    password: config['OBS_PASSWORD'] ?? '',
    dataDir: dataDir,
  );

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(ApiHandler(sessions: sessions, token: token).call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);

  // Keep-alive döngüsü ve ilk oturum denemesi sunucu ayaktayken başlar;
  // /health ilk saniyeden itibaren yanıt verir.
  sessions.start();

  stdout.writeln(
    'OBS API http://${server.address.host}:${server.port} üzerinde dinliyor '
    '(dataDir: $dataDir)',
  );
  if ((config['OBS_USERNAME'] ?? '').isEmpty) {
    stdout.writeln(
      'UYARI: OBS_USERNAME/OBS_PASSWORD boş; oturum manel CAPTCHA '
      'bekleyecek ( /admin/captcha ).',
    );
  }

  // SIGTERM/SIGINT ile düzgün kapanış.
  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\nKapanıyor...');
    await sessions.stop();
    await server.close(force: true);
    exit(0);
  });
}
