/// PostgREST istemcisi — yalnızca service_role anahtarıyla, function içinden.
import type { Config } from './env.ts';

export interface SessionRow {
  cookie: string | null;
  saved_at: string | null;
  session_alive: boolean;
  needs_manual_captcha: boolean;
  student_name: string | null;
  last_error: string | null;
  updated_at: string;
}

export type SessionPatch = Partial<
  Pick<
    SessionRow,
    'cookie' | 'saved_at' | 'session_alive' | 'needs_manual_captcha' | 'student_name' | 'last_error'
  >
>;

export interface SnapshotRow {
  payload: Record<string, unknown>;
  fetched_at: string;
}

export interface ChallengeRow {
  id: string;
  cookie: string;
  view_state: string;
  view_state_generator: string;
  request_verification_token: string;
  image_base64: string;
  created_at: string;
  expires_at: string;
  used_at: string | null;
}

export interface NewChallenge {
  cookie: string;
  viewState: string;
  viewStateGenerator: string;
  requestVerificationToken: string;
  imageBase64: string;
}

export class Store {
  private readonly rest: string;
  private readonly headers: Record<string, string>;

  constructor(cfg: Config) {
    this.rest = `${cfg.supabaseUrl}/rest/v1`;
    this.headers = {
      'apikey': cfg.serviceRoleKey,
      'Authorization': `Bearer ${cfg.serviceRoleKey}`,
      'Content-Type': 'application/json',
    };
  }

  private async request(
    method: string,
    path: string,
    body?: unknown,
    extraHeaders: Record<string, string> = {},
  ): Promise<Response> {
    const response = await fetch(`${this.rest}${path}`, {
      method,
      headers: { ...this.headers, ...extraHeaders },
      body: body == null ? undefined : JSON.stringify(body),
    });
    if (!response.ok) {
      const detail = await response.text().catch(() => '');
      throw new Error(`DB hatası (HTTP ${response.status}): ${detail.slice(0, 300)}`);
    }
    return response;
  }

  private async rows<T>(path: string): Promise<T[]> {
    const response = await this.request('GET', path);
    return await response.json() as T[];
  }

  async getSession(): Promise<SessionRow | null> {
    const rows = await this.rows<SessionRow>('/session_state?id=eq.true&select=*');
    return rows[0] ?? null;
  }

  async patchSession(patch: SessionPatch): Promise<void> {
    await this.request('PATCH', '/session_state?id=eq.true', {
      ...patch,
      updated_at: new Date().toISOString(),
    });
  }

  async getSnapshot(): Promise<SnapshotRow | null> {
    const rows = await this.rows<SnapshotRow>('/snapshot?id=eq.true&select=*');
    return rows[0] ?? null;
  }

  async getHeartbeat(): Promise<{ at: string } | null> {
    const rows = await this.rows<{ at: string }>('/heartbeat?id=eq.true&select=at');
    return rows[0] ?? null;
  }

  async saveSnapshot(payload: Record<string, unknown>, fetchedAt: string): Promise<void> {
    await this.request('PATCH', '/snapshot?id=eq.true', { payload, fetched_at: fetchedAt });
  }

  /// Pause önleme sinyali: worker her çalıştırmada bu satırı tazeler.
  async heartbeat(): Promise<void> {
    await this.request('PATCH', '/heartbeat?id=eq.true', { at: new Date().toISOString() });
  }

  async acquireLease(owner: string, seconds: number): Promise<boolean> {
    const response = await this.request('POST', '/rpc/try_acquire_lease', {
      p_owner: owner,
      p_seconds: seconds,
    });
    return await response.json() as boolean;
  }

  async releaseLease(owner: string): Promise<void> {
    await this.request('POST', '/rpc/release_lease', { p_owner: owner });
  }

  /// Yeni challenge açar; kullanılmamış eski challenge'ları iptal eder.
  async createChallenge(challenge: NewChallenge): Promise<ChallengeRow> {
    await this.request(
      'PATCH',
      '/captcha_challenge?used_at=is.null',
      { used_at: new Date().toISOString() },
    );
    const response = await this.request(
      'POST',
      '/captcha_challenge',
      {
        cookie: challenge.cookie,
        view_state: challenge.viewState,
        view_state_generator: challenge.viewStateGenerator,
        request_verification_token: challenge.requestVerificationToken,
        image_base64: challenge.imageBase64,
        expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
      },
      { Prefer: 'return=representation' },
    );
    const rows = await response.json() as ChallengeRow[];
    return rows[0];
  }

  async activeChallenge(): Promise<ChallengeRow | null> {
    const query = new URLSearchParams({
      used_at: 'is.null',
      expires_at: `gt.${new Date().toISOString()}`,
      order: 'created_at.desc',
      limit: '1',
      select: '*',
    });
    const rows = await this.rows<ChallengeRow>(`/captcha_challenge?${query}`);
    return rows[0] ?? null;
  }

  async markChallengeUsed(id: string): Promise<void> {
    await this.request('PATCH', `/captcha_challenge?id=eq.${encodeURIComponent(id)}`, {
      used_at: new Date().toISOString(),
    });
  }
}
