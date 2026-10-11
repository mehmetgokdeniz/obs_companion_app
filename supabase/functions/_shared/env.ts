/// Edge function yapılandırması (secret'lar).

export interface Config {
  /// Uygulamanın Bearer olarak taşıdığı erişim anahtarı.
  apiToken: string;
  /// PostgREST/RPC erişimi (yalnızca function içinden kullanılır).
  supabaseUrl: string;
  serviceRoleKey: string;
  obsBaseUrl: string;
  obsUsername: string;
  obsPassword: string;
  ocrEnabled: boolean;
}

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ConfigError';
  }
}

export function loadConfig(): Config {
  const apiToken = Deno.env.get('API_TOKEN') ?? '';
  if (apiToken.length === 0) {
    throw new ConfigError('Sunucu yapılandırması eksik (API_TOKEN).');
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (supabaseUrl.length === 0 || serviceRoleKey.length === 0) {
    throw new ConfigError('Sunucu yapılandırması eksik (SUPABASE_URL/SERVICE_ROLE_KEY).');
  }

  return {
    apiToken,
    supabaseUrl,
    serviceRoleKey,
    obsBaseUrl: Deno.env.get('OBS_BASE_URL') ?? 'https://obs.alparslan.edu.tr',
    obsUsername: Deno.env.get('OBS_USERNAME') ?? '',
    obsPassword: Deno.env.get('OBS_PASSWORD') ?? '',
    ocrEnabled: (Deno.env.get('OCR_ENABLED') ?? 'true').toLowerCase() !== 'false',
  };
}
