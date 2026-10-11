/// GET /status — oturum/önbellek durumu (eski /api/v1/status ile aynı anahtarlar).
import { json } from '../_shared/auth.ts';
import { apiEntry } from '../_shared/api.ts';
import { snapshotAgeMs } from '../_shared/session.ts';

Deno.serve((req) =>
  apiEntry(req, async (_req, _cfg, store) => {
    const [session, snapshot, heartbeat] = await Promise.all([
      store.getSession(),
      store.getSnapshot(),
      store.getHeartbeat(),
    ]);

    return json(200, {
      sessionAlive: session?.session_alive ?? false,
      needsManualCaptcha: session?.needs_manual_captcha ?? false,
      studentName: session?.student_name ?? null,
      lastRefresh: snapshot?.fetched_at ?? null,
      cacheAgeSeconds: snapshot == null
        ? null
        : Math.max(0, Math.floor(snapshotAgeMs(snapshot.fetched_at) / 1000)),
      lastWorkerAt: heartbeat?.at ?? null,
    });
  }),
);
