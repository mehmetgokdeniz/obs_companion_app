import 'dart:math';

/// OBS'e yapılan istekleri seyrelterek sunucuya yük bindirmemeyi sağlar.
///
///  * Her tur arasına rastgele bekleme eklenir; istekler sabit bir ritme
///    takılmaz ve otomasyon gibi görünmez.
///  * Başarısız denemelerde bekleme kademeli uzar, böylece hatalı istekler
///    arka arkaya tekrarlanmaz.
class SafeScheduler {
  SafeScheduler({Random? random}) : _random = random ?? Random();

  /// İki tur arasındaki en kısa bekleme.
  static const Duration baseInterval = Duration(minutes: 10);

  /// Eklenebilecek en fazla rastgele bekleme.
  static const Duration maxJitter = Duration(minutes: 5);

  /// Hatalı deneme başına eklenecek bekleme.
  static const Duration backoffStep = Duration(minutes: 5);

  final Random _random;

  int _failedAttempts = 0;

  /// Başarılı bir turdan sonra çağrılır.
  void onSuccess() => _failedAttempts = 0;

  /// Başarısız bir turdan sonra çağrılır.
  void onFailure() => _failedAttempts++;

  /// Sıradaki tur için beklenecek süre.
  Duration nextDelay() {
    final jitterMs = _random.nextInt(maxJitter.inMilliseconds + 1);
    final backoffMs = _failedAttempts * backoffStep.inMilliseconds;
    return baseInterval + Duration(milliseconds: jitterMs + backoffMs);
  }
}
