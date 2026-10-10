import 'dart:typed_data';

/// Giriş formunun sunucudan çekilen gizli alanları.
class LoginResult {
  final String viewState;
  final String viewStateGenerator;
  final String requestVerificationToken;
  final Uint8List? captcha;

  const LoginResult({
    required this.viewState,
    required this.viewStateGenerator,
    required this.requestVerificationToken,
    this.captcha,
  });
}

/// Giriş denemesinin sonucunu taşır: başarılı mı, hata mesajı ne?
class LoginResultStatus {
  final bool success;
  final String? sessionCookie;
  final String? error;

  const LoginResultStatus.success({required this.sessionCookie})
      : success = true,
        error = null;

  const LoginResultStatus.failure(this.error)
      : success = false,
        sessionCookie = null;
}

/// Servis katmanından fırlatılan, kullanıcıya gösterilebilir hatalar.
class ObsException implements Exception {
  final String message;

  const ObsException(this.message);

  @override
  String toString() => message;
}
