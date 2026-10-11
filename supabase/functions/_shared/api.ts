/// API uçları için ortak giriş: yapılandırma + token/rate-limit koruması +
/// beklenmeyen hataların500'e çevrilmesi.
import { guard, json } from './auth.ts';
import { ConfigError, loadConfig, type Config } from './env.ts';
import { Store } from './store.ts';

export async function apiEntry(
  req: Request,
  handler: (req: Request, cfg: Config, store: Store) => Promise<Response>,
): Promise<Response> {
  let cfg: Config;
  try {
    cfg = loadConfig();
  } catch (e) {
    const message = e instanceof ConfigError ? e.message : 'Yapılandırma hatası.';
    return json(500, { error: message });
  }

  const denied = guard(req, cfg.apiToken);
  if (denied != null) return denied;

  try {
    return await handler(req, cfg, new Store(cfg));
  } catch (e) {
    console.error('api error:', e);
    return json(500, { error: 'Beklenmeyen sunucu hatası.' });
  }
}
