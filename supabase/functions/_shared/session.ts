/// Oturum yaşam döngüsü: keep-alive, OCR ile yeniden giriş, tarama ve
/// kalıcılık. server/lib/session_manager.dart'ın stateless karşılığı.
import type { Config } from './env.ts';
import type { Snapshot } from './models.ts';
import { snapshotToJson } from './models.ts';
import { isObsException, ObsException, ObsService } from './obs.ts';
import { solveCaptcha } from './ocr.ts';
import type { Store } from './store.ts';

/// Uygulama cache'i: 5 dakika taze ise OBS'e dokunulmaz (eski sunucuyla aynı).
export const CACHE_TTL_MS = 5 * 60_000;

/// Worker taramayı bu yaşın üstünde yeniler.
export const WORKER_REFRESH_MS = 15 * 60_000;

/// Edge function'ın 150 sn wall-clock limiti altında kalması için bütçe.
export const BUDGET_MS = 110_000;

const LOGIN_MAX_ATTEMPTS = 2;

const BUDGET_MESSAGE =
  'Zaman aşımı: işlem tamamlanamadı; sonraki istekte yeniden denenecek.';

export function newDeadline(): number {
  return Date.now() + BUDGET_MS;
}

function withinBudget(deadline: number): boolean {
  return Date.now() < deadline;
}

function checkBudget(deadline: number): void {
  if (!withinBudget(deadline)) throw new ObsException(BUDGET_MESSAGE);
}

/// Kayıtlı çerezi çözerek service oluşturur.
export async function newService(cfg: Config, store: Store): Promise<ObsService> {
  const service = new ObsService(cfg.obsBaseUrl);
  const state = await store.getSession();
  if (state?.cookie != null && state.cookie.length > 0) {
    service.restoreSession(state.cookie);
  }
  return service;
}

interface LoginAutoOutcome {
  alive: boolean;
  needsManualCaptcha: boolean;
  error: string | null;
}

/// OCR ile sessiz giriş. En fazla 2 deneme; CAPTCHA hep tazelenir.
///
/// ObsException fırlatmaz (ağ hariç): başarısızlık durumunu sonuçta tutar ki
/// çağıran "manuel captcha bekleniyor" diyebilsin.
async function loginAuto(
  service: ObsService,
  cfg: Config,
  deadline: number,
): Promise<LoginAutoOutcome> {
  if (cfg.obsUsername.length === 0 || cfg.obsPassword.length === 0) {
    return { alive: false, needsManualCaptcha: true, error: null };
  }

  const solve = (image: Uint8Array): number | null =>
    cfg.ocrEnabled ? solveCaptcha(image) : null;

  for (let attempt = 0; attempt < LOGIN_MAX_ATTEMPTS; attempt++) {
    checkBudget(deadline);

    const form = await service.prepareLogin();
    const sum = form.captcha == null ? null : solve(form.captcha);

    if (sum == null) {
      return { alive: false, needsManualCaptcha: true, error: null };
    }

    const result = await service.login({
      studentId: cfg.obsUsername,
      password: cfg.obsPassword,
      securityCode: String(sum),
      viewState: form.viewState,
      viewStateGenerator: form.viewStateGenerator,
      requestVerificationToken: form.requestVerificationToken,
    });

    if (result.success) {
      return { alive: true, needsManualCaptcha: false, error: null };
    }

    // Yanlış CAPTCHA olabilir; döngü yeni form + yeni görselle dener.
    // Şifre hatası iki denemede de aynı çıkar, manel fallback'e düşülür.
  }

  return { alive: false, needsManualCaptcha: true, error: null };
}

/// Oturum açık değilse cookie doğrular, düşmüşse yeniden giriş yapar.
/// Başarısızsa (manuel captcha gerekiyorsa) ObsException fırlatır —
/// server/session_manager.dart#_ensureAlive ile aynı mesajlarla.
export async function ensureAlive(
  service: ObsService,
  cfg: Config,
  store: Store,
  deadline: number,
): Promise<void> {
  const state = await store.getSession();
  if (state?.session_alive === true) return;

  if (state?.cookie != null && state.cookie.length > 0) {
    try {
      if (await service.isSessionAlive()) {
        await store.patchSession({
          session_alive: true,
          needs_manual_captcha: false,
          last_error: null,
        });
        return;
      }
    } catch (e) {
      // Ağ hatasında oturuma dokunmuyoruz; yeniden giriş yine de denenir
      // (eski sunucudaki _restoreCookie davranışıyla aynı).
      if (!isObsException(e)) throw e;
    }
  }

  const outcome = await loginAuto(service, cfg, deadline);

  if (outcome.alive) {
    await store.patchSession({
      cookie: service.sessionCookie,
      saved_at: new Date().toISOString(),
      session_alive: true,
      needs_manual_captcha: false,
      last_error: null,
    });
    return;
  }

  await store.patchSession({
    session_alive: false,
    needs_manual_captcha: outcome.needsManualCaptcha,
    last_error: outcome.error,
  });

  if (outcome.needsManualCaptcha) {
    throw new ObsException('Sunucu oturumu yenilenemiyor; manel güvenlik kodu bekleniyor.');
  }
  if (outcome.error != null) throw new ObsException(outcome.error);
  throw new ObsException('OBS girişi başarısız.');
}

/// Veriyi OBS'ten çekip snapshot'a yazar; sayfa ortasında oturum düşerse
/// bir kez yeniden girişle tekrar dener (eski snapshot() davranışı).
export async function scrapeAndSave(
  service: ObsService,
  cfg: Config,
  store: Store,
  deadline: number,
): Promise<Snapshot> {
  try {
    return await fetchAndPersist(service, store, deadline);
  } catch (e) {
    if (isObsException(e) && e.message.includes('Oturum')) {
      await store.patchSession({ session_alive: false });
      await ensureAlive(service, cfg, store, deadline);
      return await fetchAndPersist(service, store, deadline);
    }
    throw e;
  }
}

async function fetchAndPersist(
  service: ObsService,
  store: Store,
  deadline: number,
): Promise<Snapshot> {
  await service.discoverPages();

  const courses = await service.fetchGrades();
  checkBudget(deadline);
  const schedule = await service.fetchSchedule();
  checkBudget(deadline);
  const attendance = await service.fetchAttendance();

  const snapshot: Snapshot = {
    studentName: service.studentName,
    fetchedAt: new Date().toISOString(),
    courses,
    schedule,
    attendance,
  };

  await store.saveSnapshot(snapshotToJson(snapshot), snapshot.fetchedAt);
  await store.patchSession({
    student_name: snapshot.studentName,
    session_alive: true,
    needs_manual_captcha: false,
    last_error: null,
  });
  return snapshot;
}

/// Tek çağrıda: canlılık kontrolü + tarama + kalıcılık.
export async function refreshAll(
  service: ObsService,
  cfg: Config,
  store: Store,
  deadline: number,
): Promise<Snapshot> {
  await ensureAlive(service, cfg, store, deadline);
  return await scrapeAndSave(service, cfg, store, deadline);
}

/// Snapshot yaşı (ms); kayıt yoksa null.
export function snapshotAgeMs(fetchedAt: string): number {
  return Date.now() - Date.parse(fetchedAt);
}
