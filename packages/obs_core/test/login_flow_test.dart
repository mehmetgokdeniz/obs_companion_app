/// Canlı ağa atarlar; CI bunları `dart test --exclude-tags live` ile atlar.
@Tags(['live'])
library;

import 'package:obs_core/obs_core.dart';
import 'package:test/test.dart';

/// OBS, giriş POST'unun **her** yanıtı için 302 döndürüyor. Bu yüzden
/// yalnızca durum koduna bakmak, yanlış bilgilerle bile başarılı giriş
/// sanılmasına yol açıyordu. Bu testler gerçek sunucuya istek atarak
/// davranışın doğru yorumlandığını doğrular.
void main() {
  test('yanlis bilgilerle giris reddedilir', () async {
    final service = ObsService();
    final form = await service.prepareLogin();

    final result = await service.login(
      studentId: '99999999999',
      password: 'yanlisparola',
      securityCode: '99',
      viewState: form.viewState,
      viewStateGenerator: form.viewStateGenerator,
      requestVerificationToken: form.requestVerificationToken,
    );

    expect(result.success, isFalse);
    expect(result.sessionCookie, isNull);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('basarisiz giristen sonra oturum canli gorunmez', () async {
    final service = ObsService();
    final form = await service.prepareLogin();

    await service.login(
      studentId: '99999999999',
      password: 'yanlisparola',
      securityCode: '99',
      viewState: form.viewState,
      viewStateGenerator: form.viewStateGenerator,
      requestVerificationToken: form.requestVerificationToken,
    );

    expect(await service.isSessionAlive(), isFalse);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('giris formu gercek captcha gorseli dondurur', () async {
    final service = ObsService();
    final form = await service.prepareLogin();

    expect(form.viewState, isNotEmpty);
    expect(form.viewStateGenerator, isNotEmpty);
    expect(form.requestVerificationToken, isNotEmpty);
    expect(form.captcha, isNotNull);
    // Gorsel gercekten JPEG verisi olmali.
    expect(form.captcha!.length, greaterThan(1000));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('sunucunun gercek hata mesaji okunur', () async {
    final service = ObsService();
    final form = await service.prepareLogin();

    final result = await service.login(
      studentId: '250912032',
      password: 'YanlisSifre',
      securityCode: '1',
      viewState: form.viewState,
      viewStateGenerator: form.viewStateGenerator,
      requestVerificationToken: form.requestVerificationToken,
    );

    print('--- GIRIS SONUCU ---');
    print('success: ${result.success}');
    print('error  : ${result.error}');

    expect(result.success, isFalse);
    // Sabit metni degil, sunucunun gercek mesajini gormeliyiz.
    expect(result.error, isNot('Giriş başarısız.'));
    expect(result.error, isNotNull);
    expect(result.error!.trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('cerez nitelikleri oturum degeri sanilmaz', () async {
    final service = ObsService();
    await service.prepareLogin();

    final cookie = service.sessionCookieForTest;
    print('COOKIE: $cookie');

    // Gercek oturum degerleri bulunmali.
    expect(cookie, contains('ASP.NET_SessionId='));
    expect(cookie, contains('__RequestVerificationToken_L29pYnM1='));

    // Nitelikler oturum degeri degildir; sunucuya gonderilmemeli.
    expect(cookie, isNot(contains('path=')));
    expect(cookie, isNot(contains('SameSite')));
    expect(cookie, isNot(contains('HttpOnly')));
    expect(cookie, isNot(contains('Expires')));
  }, timeout: const Timeout(Duration(seconds: 90)));
}
