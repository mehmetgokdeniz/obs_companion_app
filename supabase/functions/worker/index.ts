/// worker — pg_cron'dan 15 dakikada bir çağrılır.
///
/// 1) Her çalıştırmada heartbeat yazar (free plan pause önleme).
/// 2) Lease alır: keep-alive ping'i; oturum düştüyse OCR ile yeniden giriş.
/// 3) Snapshot tazeyse dokunmaz, tazeyse OBS'ten yeniler.
///
/// Platform JWT doğrulaması açıktır (config.toml: verify_jwt = true);
/// cron anon anahtarıyla çağırır.
import { json } from '../_shared/auth.ts';
import { ConfigError, loadConfig } from '../_shared/env.ts';
import { isObsException } from '../_shared/obs.ts';
import {
  ensureAlive,
  newDeadline,
  newService,
  scrapeAndSave,
  snapshotAgeMs,
  WORKER_REFRESH_MS,
} from '../_shared/session.ts';
import { Store } from '../_shared/store.ts';

const LEASE_SECONDS = 300;

Deno.serve(async (_req) => {
  let store: Store;
  let cfg;
  try {
    cfg = loadConfig();
    store = new Store(cfg);
  } catch (e) {
    const message = e instanceof ConfigError ? e.message : 'Yapılandırma hatası.';
    return json(500, { ok: false, error: message });
  }

  // Pause önleme: ilk iş, her koşulda.
  try {
    await store.heartbeat();
  } catch (e) {
    console.error('heartbeat failed:', e);
    return json(500, { ok: false, error: 'Heartbeat yazılamadı.' });
  }

  const owner = crypto.randomUUID();
  if (!await store.acquireLease(owner, LEASE_SECONDS)) {
    return json(200, { ok: true, skipped: 'lease_busy' });
  }

  try {
    const service = await newService(cfg, store);
    const deadline = newDeadline();

    try {
      await ensureAlive(service, cfg, store, deadline);

      const snapshot = await store.getSnapshot();
      const stale = snapshot == null ||
        snapshotAgeMs(snapshot.fetched_at) > WORKER_REFRESH_MS;
      if (stale) {
        await scrapeAndSave(service, cfg, store, deadline);
      }

      return json(200, { ok: true, alive: true, scraped: stale });
    } catch (e) {
      if (!isObsException(e)) throw e;
      // OBS kaynaklı beklenen durum; flag'ler yardımcı fonksiyonlarda yazıldı.
      await store.patchSession({ last_error: e.message }).catch(() => {});
      const session = await store.getSession();
      return json(200, {
        ok: false,
        error: e.message,
        needsManualCaptcha: session?.needs_manual_captcha ?? false,
      });
    }
  } catch (e) {
    console.error('worker error:', e);
    return json(500, { ok: false, error: 'Beklenmeyen hata.' });
  } finally {
    await store.releaseLease(owner).catch(() => {});
  }
});
