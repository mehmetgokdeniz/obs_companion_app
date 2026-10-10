import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// OBS'in CAPTCHA'sını OCR ile çözer.
///
/// Görsel bir işlem sorusudur ("64+6=?"); [solveExpression] bunu hesaplar.
class CaptchaSolver {
  CaptchaSolver({this.tesseractCmd = 'tesseract'});

  final String tesseractCmd;

  bool? _isAvailable;

  /// tesseract çalıştırılabilir mi?
  Future<bool> available() async {
    if (_isAvailable != null) return _isAvailable!;
    try {
      final result = await Process.run(tesseractCmd, ['--version']);
      _isAvailable = result.exitCode == 0;
    } on ProcessException {
      _isAvailable = false;
    }
    return _isAvailable!;
  }

  /// CAPTCHA görselindeki rakamların toplamını döndürür.
  ///
  /// Rakam okunamazsa null: çağırıcı yeniden denemeli ya da manel yola
  /// geçmelidir.
  Future<int?> solve(Uint8List image) async {
    if (!await available()) return null;

    final dir = await Directory.systemTemp.createTemp('obs_captcha_');
    final file = File('${dir.path}/captcha.jpg');
    await file.writeAsBytes(image, flush: true);

    try {
      final result = await Process.run(tesseractCmd, [
        file.path,
        'stdout',
        '--psm',
        '7',
        '-c',
        // Operatörler de okunmalı: soru "64+6=?" gibi bir işlem.
        'tessedit_char_whitelist=0123456789+-=*/',
      ]);

      if (result.exitCode != 0) return null;

      return solveExpression(result.stdout as String);
    } finally {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Geçici dosya silinemese çalışmayı etkilemez.
      }
    }
  }

  /// OCR çıktısındaki aritmetik ifadeyi çözer.
  ///
  /// OBS'in CAPTCHA'sı "64+6=?" biçiminde bir işlem sorusudur; rakamları
  /// toplamak değil, ifadeyi hesaplamak gerekir (aksi halde 6+4+6=16 gibi
  /// yanlış sonuç çıkar ve bir girişim boşa harcanır).
  ///
  /// Operatör okunamadıysa ya da ifade eksikse null döner: çağırıcı taze
  /// görselle yeniden dener, en sonunda manel fallback'e geçer. Yanlış
  /// tahmini sıfırdan daha güvenlidir.
  @visibleForTesting
  static int? solveExpression(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return null;

    final tokens = RegExp(r'\d+|[+\-*/]')
        .allMatches(cleaned)
        .map((m) => m.group(0)!)
        .toList();

    // "64+6" -> [64, +, 6]: ilk eleman sayı, sonrası operatör-sayı çifti.
    if (tokens.length < 3) return null;

    var acc = int.tryParse(tokens.first);
    if (acc == null) return null;
    var total = acc;

    var i = 1;
    while (i < tokens.length) {
      final op = tokens[i];
      if (i + 1 >= tokens.length) return null; // Sağ operand eksik.
      final right = int.tryParse(tokens[i + 1]);
      if (right == null) return null;

      switch (op) {
        case '+':
          total += right;
        case '-':
          total -= right;
        case '*':
          total *= right;
        case '/':
          if (right == 0) return null;
          total = total ~/ right;
        default:
          return null;
      }
      i += 2;
    }
    return total;
  }
}
