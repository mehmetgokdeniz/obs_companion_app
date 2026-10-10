import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Giriş bilgilerini ve oturum çerezini cihazın şifreli deposunda tutar.
///
/// Öğrenci şifresi cihazda şifreli saklanır, hiçbir zaman kendi sunucumuza
/// veya başka bir yere gönderilmez. OBS'e giden tek veri, kullanıcının
/// giriş ekranında girdiği bilgilerdir.
class CredentialStorage {
  CredentialStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _studentIdKey = 'obs_student_id';
  static const _passwordKey = 'obs_password';

  /// Kayıtlı öğrenci numarası.
  Future<String?> readStudentId() => _storage.read(key: _studentIdKey);

  /// Kayıtlı şifre.
  Future<String?> readPassword() => _storage.read(key: _passwordKey);

  /// Giriş başarılı olduğunda bilgileri saklar.
  Future<void> saveCredentials({
    required String studentId,
    required String password,
  }) async {
    await _storage.write(key: _studentIdKey, value: studentId);
    await _storage.write(key: _passwordKey, value: password);
  }

  /// Giriş denemesi başarısız olduğunda kayıtlı bilgileri siler.
  Future<void> clear() => _storage.deleteAll();
}
