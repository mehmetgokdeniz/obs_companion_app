/// GET /all[?refresh=1] — tüm veri (eski /api/v1/all ile aynı JSON).
///
/// Taze snapshot varsa DB'den okunur (anlık yanıt); değilse lease alınıp
/// OBS'ten çekilir. Meşgulse eldeki veriyle döner.
import { json } from '../_shared/auth.ts';
import { apiEntry } from '../_shared/api.ts';
import { snapshotToJson } from '../_shared/models.ts';
import { isObsException } from '../_shared/obs.ts';
import {
  CACHE_TTL_MS,
  newDeadline,
  refreshAll,
  newService,
  snapshotAgeMs,
} from '../_shared/session.ts';

const LEASE_SECONDS = 180;

Deno.serve((req) =>
  apiEntry(req, async (req, cfg, store) => {
    const force = new URL(req.url).searchParams.get('refresh') === '1';

    const existing = await store.getSnapshot();
    if (!force && existing != null && snapshotAgeMs(existing.fetched_at) < CACHE_TTL_MS) {
      return json(200, existing.payload);
    }

    const owner = crypto.randomUUID();
    if (!await store.acquireLease(owner, LEASE_SECONDS)) {
      // OBS tarafı meşgul: taze veri yoksa bile eldekiyle dön (eski sunucu
      // tek süreçte bu durumu yaşamazdı; burada bayat veri hatasız olandan iyidir).
      if (existing != null) return json(200, existing.payload);
      return json(502, { error: 'Sunucu şu an meşgul; birazdan tekrar dene.' });
    }

    try {
      const service = await newService(cfg, store);
      const snapshot = await refreshAll(service, cfg, store, newDeadline());
      return json(200, snapshotToJson(snapshot));
    } catch (e) {
      if (!isObsException(e)) throw e;
      await store.patchSession({ last_error: e.message }).catch(() => {});
      const session = await store.getSession();
      return json(502, {
        error: e.message,
        ...(session?.needs_manual_captcha ? { needsManualCaptcha: true } : {}),
      });
    } finally {
      await store.releaseLease(owner).catch(() => {});
    }
  }),
);
