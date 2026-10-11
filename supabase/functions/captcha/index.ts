/// GET  /captcha — taze güvenlik kodu görseli (eski /admin/captcha)
/// POST /captcha — manel kodu dener (eski POST /admin/login)
///
/// OCR başarısız olduğunda uygulama görseli gösterir, kullanıcı çözer.
/// Formun gizli alanları + o formun çeresi challenge satırında saklanır;
/// form ile cookie eşleşmediyse OBS girişi reddeder.
import { json } from '../_shared/auth.ts';
import { apiEntry } from '../_shared/api.ts';
import { isObsException, ObsService } from '../_shared/obs.ts';
import type { Config } from '../_shared/env.ts';
import { Store } from '../_shared/store.ts';

const LEASE_SECONDS = 180;

function toBase64(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

Deno.serve((req) =>
  apiEntry(req, async (req, cfg, store) => {
    if (req.method === 'POST') return await submit(req, cfg, store);
    if (req.method === 'GET') return await present(cfg, store);
    return json(405, { error: 'Metot desteklenmiyor.' });
  }),
);

/// Her açılışta taze form + görsel (eski refreshManualForm davranışı).
async function present(cfg: Config, store: Store): Promise<Response> {
  try {
    const service = new ObsService(cfg.obsBaseUrl);
    const form = await service.prepareLogin();

    if (form.captcha == null) {
      return json(502, { error: 'CAPTCHA görseli alınamadı.' });
    }

    const challenge = await store.createChallenge({
      cookie: service.sessionCookie,
      viewState: form.viewState,
      viewStateGenerator: form.viewStateGenerator,
      requestVerificationToken: form.requestVerificationToken,
      imageBase64: toBase64(form.captcha),
    });

    return json(200, {
      imageBase64: challenge.image_base64,
      mime: 'image/jpeg',
      expiresAt: challenge.expires_at,
    });
  } catch (e) {
    if (!isObsException(e)) throw e;
    return json(502, { error: e.message });
  }
}

async function submit(req: Request, cfg: Config, store: Store): Promise<Response> {
  let code = '';
  try {
    const body = await req.json();
    code = typeof body?.code === 'string' ? body.code.trim() : '';
  } catch {
    // Geçersiz gövde aşağıdaki doğrulamaya düşer.
  }
  if (code.length === 0) {
    return json(400, { error: 'Güvenlik kodu boş olamaz.' });
  }
  if (cfg.obsUsername.length === 0 || cfg.obsPassword.length === 0) {
    return json(500, { error: 'OBS giriş bilgileri yapılandırılmamış.' });
  }

  const owner = crypto.randomUUID();
  if (!await store.acquireLease(owner, LEASE_SECONDS)) {
    return json(502, { error: 'Sunucu şu an meşgul; birazdan tekrar dene.' });
  }

  try {
    const challenge = await store.activeChallenge();
    if (challenge == null) {
      return json(400, { error: 'Önce güvenlik kodu görseli istenmeli.' });
    }

    const service = new ObsService(cfg.obsBaseUrl);
    service.restoreSession(challenge.cookie);

    const result = await service.login({
      studentId: cfg.obsUsername,
      password: cfg.obsPassword,
      securityCode: code,
      viewState: challenge.view_state,
      viewStateGenerator: challenge.view_state_generator,
      requestVerificationToken: challenge.request_verification_token,
    });
    await store.markChallengeUsed(challenge.id);

    if (result.success) {
      await store.patchSession({
        cookie: service.sessionCookie,
        saved_at: new Date().toISOString(),
        session_alive: true,
        needs_manual_captcha: false,
        last_error: null,
      });
      return json(200, { success: true });
    }

    // Başarısız: kullanıcı hemen tekrar deneyebilsin diye taze görsel üret.
    const fresh = await service.prepareLogin();
    let imageBase64: string | null = null;
    if (fresh.captcha != null) {
      const next = await store.createChallenge({
        cookie: service.sessionCookie,
        viewState: fresh.viewState,
        viewStateGenerator: fresh.viewStateGenerator,
        requestVerificationToken: fresh.requestVerificationToken,
        imageBase64: toBase64(fresh.captcha),
      });
      imageBase64 = next.image_base64;
    }
    await store.patchSession({ last_error: result.error });

    return json(401, {
      success: false,
      error: result.error ?? 'Giriş başarısız.',
      ...(imageBase64 != null ? { imageBase64, mime: 'image/jpeg' } : {}),
    });
  } catch (e) {
    if (!isObsException(e)) throw e;
    return json(502, { error: e.message });
  } finally {
    await store.releaseLease(owner).catch(() => {});
  }
}
