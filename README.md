# OBS Companion + Kendine Özel OBS API

[![CI](https://github.com/mehmetgokdeniz/obs_companion_app/actions/workflows/ci.yml/badge.svg)](https://github.com/mehmetgokdeniz/obs_companion_app/actions/workflows/ci.yml)

Muş Alparslan Üniversitesi OBS verilerini (not, ders programı, devamsızlık)
**giriş ekranı görmeden** çekmek için çok parçalı bir çözüm:

1. **`supabase/`** — Canlı API. Edge Functions (TypeScript) OBS'e senin adına
   giriş yapar (CAPTCHA'yı saf JS OCR ile çözer, olmazsa uygulamada manel
   akışa düşer), oturumu canlı tutar ve veriyi JSON olarak sunar.
   pg_cron her 15 dakikada worker'ı çağırır (keep-alive + heartbeat).
2. **`packages/obs_core/`** — OBS scraper + parser çekirdeği (saf Dart).
   Yerel araçlar ve eski sunucu bunu kullanır; TS portu
   `supabase/functions/_shared/` içindeki aynı parser'larla eşleşir.
3. **Flutter uygulaması** — OBS'e hiç bağlanmaz; API'ye token ile bağlanır.
   Kurulum ekranına bir kez URL + token girersin, sonra hiçbir giriş görmezsin.
4. **`server/`** — Eski Dart sunucusu (referans/legacy). VM'de çalıştırılmak
   üzere tasarlanmıştı; Supabase göçünden sonra deploy yolu olarak kullanılmaz.

Diğer uygulamaların da aynı API'yi kullanması yeterlidir: tek bir Bearer
token, tek bir JSON uçları seti.

## Mimari

```
Flutter uygulaması ──┐
Diğer uygulamalar  ──┼── GET /status, /all, /captcha (Bearer token)
                     │         │
                     │         ▼
                     │   Supabase Edge Functions (status, all, captcha)
                     │         │  ├─ Postgres: session_state, snapshot,
                     │         │  │            captcha_challenge, heartbeat
                     │         │  └─ _shared: obs_client + parser + OCR
                     │         │
                     │   pg_cron (*/15) ──► worker: keep-alive + tarama ──► OBS
                     │
                     └─ yerel önbellek (çevrimdışı açılış)
```

## API Uçları

| Uç | Auth | Açıklama |
|---|---|---|
| `GET /status` | Bearer | oturum/önbellek durumu (+ `lastWorkerAt`) |
| `GET /all` | Bearer | not + program + devamsızlık tek istekte |
| `GET /captcha` | Bearer | taze CAPTCHA görseli (yalnızca manel akışta) |
| `POST /captcha` | Bearer | manel kodu dener (`{"code": "70"}`) |
| `worker` | Supabase JWT | pg_cron hedefi (uygulamadan çağrılmaz) |

`/all` önbellek TTL'i 5 dakikadır; `?refresh=1` önbelleği yok sayar. Taze
snapshot varsa yanıt anlıktır (DB'den okunur), tazeyse OBS'ten çekilir.

Örnek:

```bash
curl -H "Authorization: Bearer $API_TOKEN" \
  "https://<REF>.supabase.co/functions/v1/all"
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

- **Normal durum**: hiç görmezsin. Worker 15 dakikada bir oturumu canlı tutar;
  düşerse saf JS OCR ile sessizce yeniden giriş dener.
- **OCR başarısız** (`OCR_ENABLED=false` ya da eşik altı okuma): sunucu
  `needsManualCaptcha: true` döner. Uygulamada sarı **"Oturum yenilemek için
  güvenlik kodu gerekiyor"** bandındaki **Çöz** düğmesi dialogu açar: görsel
  gelir, rakamların toplamını yazarsın, oturum açılır ve veri tazelenir.

> OCR asla tahmin etmez: güvenilmeyen okuma null döner ve manel akış açılır
> (yanlış cevap, sıfırdan daha kötüdür). Şablonlar gerçek örneklerden üretilir
> (`supabase/tools/build_templates.ts`); LOO değerlendirmesinde **0 yanlış**
> ölçümü vardır.

## Testler

```bash
deno test --config supabase/deno.json --allow-read supabase/tests   # parser port + expression + OCR (20 test)
cd packages/obs_core && dart test   # parser + model + scheduler
cd server && dart test              # eski sunucu: auth, uçlar, cache, rate-limit
flutter test                        # API istemcisi + captcha akışı
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

### Seçenek S — Supabase (önerilen: tam göç, VM yok)

Sistem tamamen serverless çalışır: scrape + keep-alive + API'nin tamamı
Supabase'de. Free plan **kredi kartı istemez** (2 proje, 500 MB DB).

> **Pause riski**: Free proje ~7 gün düşük veritabanı aktivitesinde
> uyutulur. `*/15` cron'unun her çalıştırdığı heartbeat yazımı bunu önler;
> yine de uyarı e-postası gelirse Dashboard → **Resume project** (veri
> silinmez,1 yıl geri gelir).

**1) Hesap + proje**

1. [supabase.com/dashboard](https://supabase.com/dashboard) → GitHub/e-posta ile
   giriş → **New project** → bölge seç (ör. `eu-central-1`) → DB şifresi not et.
2. **Project Settings → API** sayfasındaki `Project ref`, `anon key` ve
   `service_role key` değerlerini al.

**2) CLI + bağlantı**

```bash
npm i -g supabase
supabase login                      # tarayıcıyla yetkilendir
supabase link --project-ref <REF>
```

**2b) OBS erişim relay'i (Cloudflare Worker — zorunlu)**

> **Önemli**: OBS (`obs.alparslan.edu.tr`), veri merkezi IP'lerini TCP seviyesinde
> resetler → Supabase'den doğrudan erişim YOK. Kanıtlanmış çözüm: şeffaf bir
> Cloudflare Worker relay (ücretsiz, uyumaz,100k istek/gün; .tr origin'lere en
> yakın POP'tan çıkış yaptığı için engeli aşar).

```bash
npx wrangler login      # GitHub ile, kart istemez
npx wrangler deploy tools/obs-relay/worker.js --name obs-relay
# çıktı: https://obs-relay.<kullanıcıadın>.workers.dev
```

(Panel yolu: Workers & Pages → Create → Hello World → **Edit code** ile
`tools/obs-relay/worker.js` içeriğini yapıştır → Deploy.)

**3) Şema + secret'lar + fonksiyonlar**

```bash
supabase db push                    # supabase/migrations/0001_init.sql

supabase secrets set \
  API_TOKEN=<32+ karakter rastgele> \
  OBS_USERNAME=<okul no> \
  OBS_PASSWORD=<şifre> \
  OBS_BASE_URL=https://obs-relay.<kullanıcıadın>.workers.dev \
  OCR_ENABLED=true

supabase functions deploy status  --no-verify-jwt
supabase functions deploy all     --no-verify-jwt
supabase functions deploy captcha --no-verify-jwt
supabase functions deploy worker            # JWT doğrulama açık kalır
```

- `API_TOKEN` uygulamanın kurulum ekranına gireceği token'dır.
- `OCR_ENABLED=false` yaparsan otomatik OCR hiç denenmez, her yenilemede
  manel akış açılır (test için yararlı).
- `supabase/functions/_shared/` içindeki ortak modüller deploy'da otomatik
  paketlenir.

**4) Cron (keep-alive + heartbeat)**

`supabase/migrations/0002_cron.sql` dosyasındaki `<REF>` ve `<ANON_KEY>`
değerlerini doldurup `supabase db push` ile uygula. Alternatif olarak aynı
SQL'i Dashboard → **SQL Editor**'de çalıştırabilirsin:

```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule('obs-worker', '*/15 * * * *', $$
  select net.http_post(
    url := 'https://<REF>.supabase.co/functions/v1/worker',
    headers := '{"Content-Type": "application/json",
                "Authorization": "Bearer <ANON_KEY>"}'::jsonb,
    body := '{}',
    timeout_milliseconds := 30000
  );
$$);
```

**5) Doğrulama**

```bash
BASE="https://mqfnecoswcobbwlecmlf.supabase.co/functions/v1"   # <REF> kendi projen
curl -s $BASE/status                                   # 401 (token'sız)
curl -s -H "Authorization: Bearer $API_TOKEN" $BASE/status
# {"sessionAlive":true,"needsManualCaptcha":false,...}

supabase functions invoke worker                       # keep-alive + tarama
# all veri dönmeli; oturum düşerse needsManualCaptcha: true gelir
```

İlk kullanımda (ya da OCR'ın çözemediği her durumda) `/captcha` görseli
gelir; cevap görseldeki işlemin SONUCUDUR (ör. `29+5=?` → `34`).
`POST /captcha {"code":"34"}` → `{"success":true}` → `/all` veriyi döner.

Dashboard → **Database → Cron Jobs** listesinde `obs-worker` görünmeli;
15 dakika sonra **Table Editor → heartbeat** satırı tazelenmelidir.

**6) Uygulamaya bağlama**

- API Adresi: `https://<REF>.supabase.co/functions/v1`
- Token: `API_TOKEN`

> Edge Function limitleri (Free): 150 sn wall-clock, 256 MB, istek başına
> 2 sn CPU (I/O sayılmaz). Tarama işi bu bütçe altında; süre aşımında eski
> snapshot korunur ve sonraki istek yeniden dener.

### Legacy — Dart sunucusu (VM yolları, artık kullanılmıyor)

Aşağıdaki seçenekler `server/` Docker imajını içerir; Supabase göçündan sonra
deploy yolu olarak gerekmez. Yerel geliştirme ve referans olarak kalır.

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

> Kalıcı disk Render'da **yalnızca ücretli planda** var; ücretsiz planda
> `session.json` her yeniden başlayışta gider ve disk **15 dakikada bir uyur**
> (~50 sn soğuk başlangıç). Bu yüzden kalıcı oturum istiyorsan Seçenek A/C
> tercih edilir.

Ücretsiz katmanda sunucu uyandığında oturum cookie'si yoksa OCR ile sessizce
yeniden giriş dener; OCR başarısız olursa `/admin/captcha` gerekir.

### Seçenek C — Google Cloud always-free VM (uyumaz, 30 GB disk)

Always-free kapsamı (Google'ın resmi free tier sayfası, 2026-10-07):

- `us-west1`, `us-central1`, `us-east1` bölgelerinde 1 adet non-preemptible
  **`e2-micro`** (1 GB RAM). Saat sınırı "ayda X saat" değil, **ayın toplam
  saati** kadar → 7/24 çalıştırılabilir.
- **30 GB** standard persistent disk.
- Aylık **1 GB** çıkış trafiği (uygulama 10–15 dk'da bir ~15 KB çeker →
  **~65 MB/ay**, limitin çok altında).

> Bölgeler yalnızca ABD. OBS'i ABD IP'sinden istemek CAPTCHA oranını
> artırabilir; gerekirse başka bir free bölgesi/Oracle'a dönülebilir.

**1) Console'da VM aç** — billing hesabı gerekir (~$0–1 geçici blokaj):

```bash
gcloud compute instances create obs-api \
  --machine-type=e2-micro --zone=us-central1-a \
  --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud \
  --boot-disk-size=10GB --tags=obs-api

gcloud compute firewall-rules create allow-obs-8080 \
  --allow=tcp:8080 --source-ranges=0.0.0.0/0 --target-tags=obs-api
```

**2) Bütçe uyarısı** (önerilir): Console → **Billing → Budgets & alerts →
Create budget**, eşik **$1**. Free tier dışına çıkmadan haberin olur.

**3) İmajı derle (Cloud Shell, tarayıcıda açılır — yerel Docker gerekmez)**

`e2-micro` 1 GB RAM ile derleme yapamaz; `cloudbuild.yaml` imajı Google'ın
altyapısında derler (ücretsiz: ayda 2500 dakika) ve Artifact Registry'ye iter:

```bash
git clone https://github.com/mehmetgokdeniz/obs_companion_app.git && cd obs_companion_app
gcloud services enable cloudbuild.googleapis.com artifactregistry.googleapis.com
gcloud artifacts repositories create obs-api --repository-format=docker --location=us-central1
gcloud builds submit

# VM'nin varsayılan servis hesabına imajı çekme yetkisi ver
# (atlanırsa VM'de `docker pull` 403 döner)
gcloud artifacts repositories add-iam-policy-binding obs-api \
  --location=us-central1 \
  --member="serviceAccount:$(gcloud config get-value project)-compute@developer.gserviceaccount.com" \
  --role=roles/artifactregistry.reader
```

**4) VM'de** (`gcloud compute ssh obs-api --zone=us-central1-a`):

```bash
# 1 GB RAM yetersiz kalırsa dart/tesseract OOM kill yiyebilir → 2 GB swap
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

curl -fsSL https://get.docker.com | sh

# Sunucu .env'i çalışma dizininden (/app) okur
mkdir -p ~/obs-data
cat > ~/obs-data/.env <<'EOF'
API_TOKEN=<32+ karakter rastgele>
OBS_USERNAME=<okul no>
OBS_PASSWORD=<şifre>
EOF
chmod 600 ~/obs-data/.env

gcloud auth configure-docker us-central1-docker.pkg.dev

docker pull us-central1-docker.pkg.dev/<PROJE>/obs-api/obs-api:latest
docker run -d --name obs-api --restart unless-stopped \
  -p 8080:8080 \
  -v "$HOME/obs-data:/app/data" \
  -v "$HOME/obs-data/.env:/app/.env:ro" \
  us-central1-docker.pkg.dev/<PROJE>/obs-api/obs-api:latest

curl -s http://127.0.0.1:8080/health     # {"status":"ok",...} görmelisin
```

IP adresini al:

```bash
gcloud compute instances describe obs-api --zone=us-central1-a \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
```

Uygulamaya **`http://<VM-IP>:8080`** yaz (IP literal'ı `http://` ile açılır).

> `.env` ayrı bir dosya olarak mount edilir; `data/` kalıcıdır, VM yeniden
> başlasa da `session.json` silinmez → OBS'e sıfırdan giriş gerekmez.
>
> **Uyarı**: adres `http://` olduğu için token internet üzerinde düz metin
> gider. Alan adın varsa Nginx + Let's Encrypt ile Seçenek A'daki gibi
> HTTPS'e çevir.

### Güvenlik notları

- `API_TOKEN` sızarsa notların okunur → HTTPS zorunlu, token'ı paylaşma.
  Supabase fonksiyonları `verify_jwt=false` ile kendi Bearer kontrolünü yapar.
- `service_role key` yalnızca edge function secret'larında yaşar; istemciye
  asla gömülmez. `anon key` herkese açıktır (yalnızca cron çağrısında kullanılır).
- `.env` ve `server/data/` git'e girmez (`.gitignore`'da).
- API, IP başına dakikada 60 istekle sınırlıdır (429 döner; isolate belleği
  paylaşılmadığı için en iyi ihtimalle tahminidir — asıl koruma token'dadır).

## Uygulamayı bağlama

1. Uygulamayı aç → **Kurulum** ekranı gelir.
2. API adresi (`https://<REF>.supabase.co/functions/v1`) ve `API_TOKEN`'ı gir
   → **Bağlan**.
3. Artık not/program/devamsızlık doğrudan gelir; OBS giriş ekranı görmezsin.
4. Sarı güvenlik kodu bandı çıkarsa **Çöz** ile görseli gir; oturum açılır.
5. Çıkış ikonu yalnızca bu yapılandırmayı siler (sunucudaki oturumu değil).
