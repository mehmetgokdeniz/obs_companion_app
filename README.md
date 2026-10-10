# OBS Companion + Kendine Özel OBS API

Muş Alparslan Üniversitesi OBS verilerini (not, ders programı, devamsızlık)
**giriş ekranı görmeden** çekmek için iki parçalı bir çözüm:

1. **`server/`** — Kendi API sunucun. OBS'e senin adına giriş yapar (CAPTCHA'yı
   OCR ile çözer), oturumu canlı tutar ve veriyi JSON olarak sunar.
2. **`packages/obs_core/`** — OBS scraper + parser çekirdeği (saf Dart).
   Hem sunucu hem uygulama aynı paketi kullanır; HTML değişikliğinin bakımı
   tek yerdedir.
3. **Flutter uygulaması** — OBS'e hiç bağlanmaz; API'ye token ile bağlanır.
   Kurulum ekranına bir kez URL + token girersin, sonra hiçbir giriş görmezsin.

Diğer uygulamaların da aynı API'yi kullanması yeterlidir: tek bir Bearer
token, tek bir JSON uçları seti.

## Mimari

```
Flutter uygulaması ──┐
Diğer uygulamalar  ──┼── GET /api/v1/all (Bearer token) ──► server/ (Shelf)
                     │                                       │
                     │                                       ├─ obs_core (scrape)
                     │                                       ├─ oturum cache + keep-alive
                     │                                       └─ tesseract (CAPTCHA OCR)
                     │
                     └─ yerel önbellek (çevrimdışı açılış)
```

## API Uçları

| Uç | Auth | Açıklama |
|---|---|---|
| `GET /health` | yok | canlılık kontrolü (load balancer için) |
| `GET /api/v1/status` | Bearer | oturum/önbellek durumu |
| `GET /api/v1/grades` | Bearer | notlar |
| `GET /api/v1/schedule` | Bearer | ders programı |
| `GET /api/v1/attendance` | Bearer | devamsızlık |
| `GET /api/v1/all` | Bearer | üçü bir arada (uygulamanın tek isteği) |
| `GET /admin/captcha` | Bearer | manel CAPTCHA sayfası (yalnızca OCR başarısızsa) |

Tüm uçlar `?refresh=1` ile önbelleği yok sayar. Önbellek TTL'i 5 dakikadır;
aynı pencere içinde OBS'e tekrar istek gitmez.

Örnek:

```bash
curl -H "Authorization: Bearer $API_TOKEN" https://senin-alanadi.com/api/v1/all
```

```json
{
  "studentName": "Ayşe Yılmaz",
  "fetchedAt": "2026-10-09T10:00:00.000",
  "courses": [{"code": "BIL101", "name": "...", "midtermGrade": 85, "...": "..."}],
  "schedule": [{"courseCode": "BIL101", "day": "Pazartesi", "...": "..."}],
  "attendance": [{"courseCode": "BIL101", "absentHours": 6, "totalHours": 30, "...": "..."}]
}
```

## Yerel çalıştırma

```bash
cd server
copy .env.example .env      # API_TOKEN, OBS_USERNAME, OBS_PASSWORD doldur
dart pub get
dart run bin/server.dart
```

> Sunucu `API_TOKEN` yoksa **78 (EX_CONFIG)** ile çıkar.

Oturum ilk girişte `server/data/session.json` dosyasına yazılır; sunucu yeniden
başlasa da oturum geri gelir. Ana sayfa ping'i (10–15 dk, rastgele) kayan oturum
süresini uzattığı sürece yeniden giriş nadiren gerekir.

### CAPTCHA ne zaman görülür?

- **Normal durum**: hiç görmezsin. Keep-alive oturumu düşürmez; düşerse sunucu
  tesseract ile rakam toplamasını çözüp sessizce yeniden giriş yapar.
- **tesseract yok ya da OCR başarısız**: sunucu `needsManualCaptcha: true`
  döner. `https://senin-alanadi.com/admin/captcha?token=...` adresini açıp
  görseldeki rakamların toplamını bir kez girersin.

## Testler

```bash
cd packages/obs_core && dart test   # parser + model + scheduler (15 test)
cd server && dart test              # auth, uçlar, cache, rate-limit (9 test)
flutter test                        # API istemcisi (4 test)
flutter analyze && (cd server && dart analyze) && (cd packages/obs_core && dart analyze)
```

`packages/obs_core/test/login_flow_test.dart` gerçek OBS sunucusuna istek atan
canlı testlerdir; `dart test test/login_flow_test.dart` ile ayrıca koşulur.

### Teşhis araçları (`server/tool/`)

OBS HTML'i değişirse parser'ları gerçek çıktıya göre ayarlamak için:

```bash
cd server
dart run tool/dump_pages.dart       # oturumla tüm sayfaları ham HTML indirir
dart run tool/verify_parsers.dart   # parser'ları o HTML'e karşı doğrular
dart run tool/dump_period.dart 20251  # geçmiş dönem notlarını çeker
dart run tool/admin_e2e.dart <base> <token> fetch   # manel captcha görselini indir
dart run tool/admin_e2e.dart <base> <token> post 70 # aynı formu gönderir
```

Çıktılar `%TEMP%\\obs_pages` altına yazılır. `verify_parsers` her dersi kod/ad/
vize/final/harf ve devamsızlık oranlarıyla listeler; gerçek OBS çıktısıyla
karşılaştırıp parser'ı düzeltmek için yeterlidir.

## Deploy

### Seçenek A — Oracle Cloud Always Free VM (önerilir: uyumaz)

Sunucu hiç uyumaz → oturum keep-alive hiç kesilmez → CAPTCHA'ya neredeyse hiç
gerek kalmaz.

**1) OCI konsolunda VM aç** (Always Free: `VM.Standard.E2.1.Micro`, Ubuntu
22.04/24.04, ~4 GB disk). Security List → **Ingress Rules** ekle:

| Port | Kaynak |
|---|---|
| 22 | 0.0.0.0/0 |
| 80 | 0.0.0.0/0 |
| 443 | 0.0.0.0/0 |
| 8080 | 0.0.0.0/0 (yalnızca alan adı yoksa) |

**2) VM'de (Ubuntu):**

```bash
sudo apt-get update
sudo apt-get install -y git docker.io nginx
git clone <repo> && cd obs_companion_app

cp server/.env.example server/.env   # API_TOKEN / OBS_USERNAME / OBS_PASSWORD
chmod 600 server/.env

# DİKKAT: build context repo KÖKÜ olmalı; Dockerfile packages/obs_core'u kopyalar.
docker build -f server/Dockerfile -t obs-api .
docker run -d --name obs-api --restart unless-stopped \
  -p 127.0.0.1:8080:8080 \
  -v "$PWD/server/data:/app/data" -v "$PWD/server/.env:/app/.env:ro" \
  obs-api

curl -s http://127.0.0.1:8080/health   # {"status":"ok",...} görmelisin
```

> Kalıcı disk (`/app/data`) şart: `session.json` orada durmazsa her restart'ta
> OBS'e sıfırdan giriş yapılır. VM'de disk zaten kalıcıdır.

**3) Bağlantı adresi**

- **Alan adın varsa (önerilir)**: Nginx + Let's Encrypt ile HTTPS'e çevir,
  uygulamaya `https://api.ornek-alanadi.com` yaz.
- **Alan adın yoksa**: `docker run` satırındaki `-p 127.0.0.1:8080:8080`
  yerine `-p 8080:8080` koy, uygulamaya `http://<VM-IP-adresi>:8080` yaz.
  Uygulama IP literal'ını `http://` ile açar. **Bu yol şifresizdir**: token ve
  notların internet üzerinde düz metin gider — yalnızca denemede kullan.

Ardından Nginx'i Let's Encrypt ile HTTPS'e çevirin (Caddy de kullanabilirsiniz):

```nginx
server {
  server_name api.ornek-alanadi.com;
  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
}
```

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d api.ornek-alanadi.com
```

> `X-Forwarded-For` başlığı, rate-limit'in IP'yi doğru tanıması için şart.

### Seçenek B — Render (ücretsiz katman, uyur)

`server/Dockerfile` hazır. Render'da **New → Web Service** → repo →:

- **Runtime**: Docker
- **Dockerfile Path**: `server/Dockerfile`
- **Environment**: `API_TOKEN`, `OBS_USERNAME`, `OBS_PASSWORD`
- **Volume**: 1 GB disk → `/app/data` (oturum ve `.env` kalıcı olsun)

Ücretsiz katman uyur; uyandığında oturum cookie'si diskten geri gelir, gelmezse
sunucu OCR ile sessizce yeniden giriş dener.

### Güvenlik notları

- `API_TOKEN` sızarsa notların okunur → HTTPS zorunlu, token'ı paylaşma.
- `.env` ve `server/data/` git'e girmez (`.gitignore`'da).
- Sunucu IP başına saniyede 1 istekle sınırlıdır (429 döner).

## Uygulamayı bağlama

1. Uygulamayı aç → **Kurulum** ekranı gelir.
2. API adresi (`https://api.ornek-alanadi.com`) ve token'ı gir → **Bağlan**.
3. Artık not/program/devamsızlık doğrudan gelir; OBS giriş ekranı görmezsin.
4. Çıkış ikonu yalnızca bu yapılandırmayı siler (sunucudaki oturumu değil).
