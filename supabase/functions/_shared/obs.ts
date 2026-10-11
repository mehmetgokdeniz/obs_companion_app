import { parseHTML } from 'npm:linkedom';

import { parseAttendance, parseGrades, parseSchedule } from './grade_parser.ts';
import { parseMenu } from './menu_parser.ts';
import type { AttendanceRecord, Course, ScheduleEntry } from './models.ts';

/// OBS oturumunu yöneten servis.
/// packages/obs_core/lib/src/obs_service.dart portu.

/// Servis katmanından fırlatılan, kullanıcıya gösterilebilir hatalar.
export class ObsException extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ObsException';
  }
}

export function isObsException(e: unknown): e is ObsException {
  return e instanceof ObsException;
}

/// Giriş formunun sunucudan çekilen gizli alanları.
export interface LoginResult {
  viewState: string;
  viewStateGenerator: string;
  requestVerificationToken: string;
  captcha: Uint8Array | null;
}

/// Giriş denemesinin sonucu: başarılı mı, hata mesajı ne?
export interface LoginResultStatus {
  success: boolean;
  sessionCookie: string | null;
  error: string | null;
}

const USER_AGENT =
  'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
  + '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

const TIMEOUT_MARKER = '/oibs/redirect.aspx';
const REQUEST_TIMEOUT_MS = 20_000;

const COOKIE_ATTRIBUTES = new Set([
  'path',
  'domain',
  'expires',
  'max-age',
  'secure',
  'httponly',
  'samesite',
  'version',
  'comment',
]);

export class ObsService {
  readonly baseUrl: string;
  readonly loginUrl: string;
  readonly captchaUrl: string;
  readonly homeUrl: string;

  private readonly cookies = new Map<string, string>();

  /// Menüden çözülen sayfa adresleri. Anahtar: menüdeki görünen başlık.
  private readonly pages = new Map<string, string>();

  /// Öğrenci adı ve numarası, ana sayfadan okunur.
  studentName: string | null = null;

  captchaBytes: Uint8Array | null = null;

  constructor(baseUrl = 'https://obs.alparslan.edu.tr') {
    this.baseUrl = baseUrl.replace(/\/+$/, '');
    this.loginUrl = `${this.baseUrl}/oibs/std/login.aspx`;
    this.captchaUrl = `${this.baseUrl}/oibs/captcha/CaptchaImg.aspx`;
    this.homeUrl = `${this.baseUrl}/oibs/std/index.aspx?curOp=0`;
  }

  /// Toplanan oturum çerezinin başlığı.
  get sessionCookie(): string {
    return [...this.cookies.entries()].map(([k, v]) => `${k}=${v}`).join('; ');
  }

  private baseHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': USER_AGENT,
      'Accept-Language': 'tr-TR,tr;q=0.9',
      'Referer': this.homeUrl,
    };
    const cookie = this.sessionCookie;
    if (cookie.length > 0) headers['Cookie'] = cookie;
    return headers;
  }

  private signal(): AbortSignal {
    return AbortSignal.timeout(REQUEST_TIMEOUT_MS);
  }

  private async send(request: () => Promise<Response>): Promise<Response> {
    try {
      return await request();
    } catch (e) {
      throw new ObsException(`Bağlantı hatası: ${e}`);
    }
  }

  /// Giriş formunun gizli alanlarını ve CAPTCHA görselini toplar.
  ///
  /// Bu GET'ler de login POST'uyla **aynı** başlıkları göndermek zorunda:
  /// OBS, User-Agent'a göre farklı login sayfası varyantı döndürüyor ve o
  /// sayfanın viewstate'i ile yapılan POST, "Oturum zaman aşımına uğradı"
  /// hatasıyla reddediliyor.
  async prepareLogin(): Promise<LoginResult> {
    const response = await this.send(() =>
      fetch(this.loginUrl, {
        headers: this.baseHeaders(),
        signal: this.signal(),
      })
    );

    if (response.status !== 200) {
      throw new ObsException(`Giriş sayfası yüklenemedi (HTTP ${response.status}).`);
    }

    const body = await bodyText(response);
    const { document } = parseHTML(body);
    this.absorbCookies(response);

    const captcha = await this.downloadCaptcha();

    return {
      viewState: hiddenValue(document, '__VIEWSTATE'),
      viewStateGenerator: hiddenValue(document, '__VIEWSTATEGENERATOR'),
      requestVerificationToken: hiddenValue(document, '__RequestVerificationToken'),
      captcha,
    };
  }

  private async downloadCaptcha(): Promise<Uint8Array | null> {
    const response = await this.send(() =>
      fetch(this.captchaUrl, {
        headers: this.baseHeaders(),
        signal: this.signal(),
      })
    );
    if (response.status !== 200) return null;
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.length === 0) return null;
    this.absorbCookies(response);
    this.captchaBytes = bytes;
    return bytes;
  }

  /// Giriş yapar. Başarılıysa oturum bilgisi taşıyan sonuç döner.
  async login(params: {
    studentId: string;
    password: string;
    securityCode: string;
    viewState: string;
    viewStateGenerator: string;
    requestVerificationToken: string;
  }): Promise<LoginResultStatus> {
    // Yönlendirme takibi kapatilir: OBS giriş POST'unu daima 302 ile
    // yanitliyor ve gercek hata mesaji (orn. "Guvenlik kodu hatali") POST'un
    // kendi govdesinde yaziliyor. Takip acik kalirsa o govde kayboluyor.
    const body = new URLSearchParams({
      '__LASTFOCUS': '',
      '__EVENTTARGET': 'btnLogin',
      '__EVENTARGUMENT': '',
      '__VIEWSTATE': params.viewState,
      '__VIEWSTATEGENERATOR': params.viewStateGenerator,
      '__SCROLLPOSITIONX': '0',
      '__SCROLLPOSITIONY': '0',
      '__RequestVerificationToken': params.requestVerificationToken,
      'txtParamT01': params.studentId,
      'txtParamT02': params.password,
      'txtParamT1': params.password,
      'txtSecCode': params.securityCode,
      'txt_scrWidth': '0',
      'txt_scrHeight': '0',
    });

    const response = await this.send(() =>
      fetch(this.loginUrl, {
        method: 'POST',
        headers: {
          ...this.baseHeaders(),
          'Referer': this.loginUrl,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body,
        redirect: 'manual',
        signal: this.signal(),
      })
    );

    this.absorbCookies(response);

    // Basarisiz giriste sunucu POST'un govdesine gercek hatayi yazar.
    const text = await bodyText(response);
    const error = extractError(text);
    if (error != null && !isLoggedInPage(text)) {
      return failure(humanize(error));
    }

    // Basarili giriste 302 doner; yonlendirmeyi takip edip ana sayfaya
    // ulasiliyor mu diye bakmamiz gerekir.
    if (response.status === 302 || response.status === 301) {
      const location = response.headers.get('location');
      if (location == null) {
        return failure('Giriş sonucu okunamadı.');
      }

      const target = location.startsWith('http') ? location : `${this.baseUrl}${location}`;
      const redirect = await this.send(() =>
        fetch(target, {
          headers: this.baseHeaders(),
          signal: this.signal(),
        })
      );
      this.absorbCookies(redirect);
      const redirectBody = await bodyText(redirect);

      if (isLoggedInPage(redirectBody)) {
        return success(this.sessionCookie);
      }
      return failure(extractError(redirectBody) ?? 'Giriş başarısız.');
    }

    if (isLoggedInPage(text)) {
      return success(this.sessionCookie);
    }
    return failure(extractError(text) ?? 'Giriş başarısız.');
  }

  /// Ana sayfayı açar, menü bağlantılarını çözer ve öğrenci bilgisini okur.
  async discoverPages(): Promise<void> {
    const response = await this.send(() =>
      fetch(this.homeUrl, {
        headers: { ...this.baseHeaders(), 'Referer': this.loginUrl },
        signal: this.signal(),
      })
    );
    const body = await bodyText(response);

    if (!isLoggedInPage(body)) {
      throw new ObsException('Oturum açık değil, tekrar giriş yapmalısın.');
    }

    const { document } = parseHTML(body);
    // Öğrenci adı #lblOgrenciAdSoyad2 span'inde duruyor; içerik
    // "250912032 - AD SOYAD" biçiminde, okul noyu ayıklıyoruz.
    const raw = document.querySelector('#lblOgrenciAdSoyad2')?.textContent?.trim()
      ?? document.querySelector('#lblOgrenciAdSoyad')?.textContent?.trim()
      ?? null;
    this.studentName = studentNameFrom(raw);

    this.pages.clear();
    for (const link of parseMenu(body, this.baseUrl)) {
      this.pages.set(link.title, link.url);
    }
  }

  /// Menüde adı geçen sayfayı getirir.
  private async fetchPageByTitle(titles: string[]): Promise<string | null> {
    for (const title of titles) {
      const url = this.pages.get(title);
      if (url == null) continue;

      const response = await this.send(() =>
        fetch(url, {
          headers: this.baseHeaders(),
          signal: this.signal(),
        })
      );
      const body = await bodyText(response);

      // Oturum düşmüşse sunucu yönlendirme sayfasını döner.
      if (body.includes(TIMEOUT_MARKER) || body.includes('Yönlendirme Yapılıyor')) {
        throw new ObsException('Oturum süresi doldu, tekrar giriş yapmalısın.');
      }
      if (response.status === 404) {
        throw new ObsException('Sayfa bulunamadı, OBS menüsü değişmiş olabilir.');
      }

      return body;
    }
    return null;
  }

  async fetchGrades(): Promise<Course[]> {
    const html = await this.fetchPageByTitle(['Not Listesi']);
    if (html == null) {
      throw new ObsException('Not Listesi sayfası bulunamadı.');
    }
    return parseGrades(html);
  }

  async fetchSchedule(): Promise<ScheduleEntry[]> {
    const html = await this.fetchPageByTitle(['Ders Programı', 'Bölüm Ders Programı']);
    if (html == null) {
      throw new ObsException('Ders Programı sayfası bulunamadı.');
    }
    return parseSchedule(html);
  }

  async fetchAttendance(): Promise<AttendanceRecord[]> {
    const html = await this.fetchPageByTitle(['Devamsızlık Durumu']);
    if (html == null) {
      throw new ObsException('Devamsızlık sayfası bulunamadı.');
    }
    return parseAttendance(html);
  }

  /// Oturum hâlâ geçerli mi?
  async isSessionAlive(): Promise<boolean> {
    const response = await this.send(() =>
      fetch(this.homeUrl, {
        headers: { ...this.baseHeaders(), 'Referer': this.loginUrl },
        signal: this.signal(),
      })
    );
    // Ana sayfa, oturum yokken de 200 döner ama yönlendirme sayfasının
    // gövdesini verir; bu yüzden yalnızca durum koduna bakmak yanıltıcıdır.
    const body = await bodyText(response);
    return isLoggedInPage(body);
  }

  private absorbCookies(response: Response): void {
    for (const cookie of response.headers.getSetCookie()) {
      // Her parçanın ilk "isim=deger" çifti çerezin kendisidir; geri kalanı
      // niteliklerdir (path, HttpOnly, SameSite, Max-Age vb.).
      const pair = cookie.split(';')[0].trim();
      const eq = pair.indexOf('=');
      if (eq <= 0) continue;

      const name = pair.substring(0, eq).trim();
      if (!isCookieName(name)) continue;

      const value = pair.substring(eq + 1).trim().replaceAll('"', '');
      if (value.length === 0) continue;

      this.cookies.set(name, value);
    }
  }

  restoreSession(cookie: string): void {
    for (const part of cookie.split(';')) {
      const eq = part.indexOf('=');
      if (eq <= 0) continue;
      this.cookies.set(part.substring(0, eq).trim(), part.substring(eq + 1).trim());
    }
  }
}

/// Cerez adları harf, rakam, tire ve alt çizgiden oluşur; nitelik adları
/// ("path", "SameSite") da bu kalıba uyar, bu yüzden ayrıca eleniyorlar.
function isCookieName(name: string): boolean {
  if (!/^[A-Za-z0-9_\-.]+$/.test(name)) return false;
  return !COOKIE_ATTRIBUTES.has(name.toLowerCase());
}

function isLoggedInPage(body: string): boolean {
  if (body.includes(TIMEOUT_MARKER)) return false;
  return body.includes('id="btnLogout"') || body.includes('IFRAME1') ||
    body.includes('id="proMenu"');
}

/// "250912032 - MEHMET GÖKDENİZ" -> "MEHMET GÖKDENİZ".
function studentNameFrom(raw: string | null): string | null {
  if (raw == null || raw.length === 0) return null;
  const dash = raw.indexOf(' - ');
  const name = dash >= 0 ? raw.substring(dash + 3) : raw;
  const trimmed = name.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function hiddenValue(document: Document, name: string): string {
  const el = document.querySelector(`input[name="${name}"]`);
  return el?.getAttribute('value') ?? '';
}

function extractError(body: string): string | null {
  // OBS hata mesajini lblSonuclar icine yazar; ancak "class" niteligi
  // "id"den once gelir, bu yuzden sadece id'ye bakmak yetmez.
  const match = /<span[^>]*\bid\s*=\s*['"]lblSonuclar['"][^>]*>(.*?)<\/span>/is.exec(body);
  if (match == null) return null;

  const { document } = parseHTML(`<span>${match[1]}</span>`);
  const text = (document.querySelector('span')?.textContent ?? '')
    .replace(/\s+/g, ' ')
    .trim();
  return text.length === 0 ? null : text;
}

/// Sunucunun ham mesajini kullaniciya daha anlasilir hale getirir.
function humanize(serverMessage: string): string {
  const lower = serverMessage.toLowerCase();

  if (lower.includes('güvenlik kodu') || lower.includes('guvenlik kodu')) {
    return 'Güvenlik kodunu yanlış girdin. Görseldeki rakamların toplamını yaz.';
  }
  if (lower.includes('kullanıcı') || lower.includes('kullanici')) {
    return 'Öğrenci numaranı kontrol et.';
  }
  if (lower.includes('şifre') || lower.includes('sifre')) {
    return 'Şifren yanlış, tekrar dene.';
  }
  if (lower.includes('oturum')) {
    return 'Oturum zaman aşımına uğradı. Lütfen tekrar dene.';
  }

  return serverMessage;
}

function success(sessionCookie: string): LoginResultStatus {
  return { success: true, sessionCookie, error: null };
}

function failure(error: string): LoginResultStatus {
  return { success: false, sessionCookie: null, error };
}

/// Yanıt gövdesini charset bilgisine göre çözer; bilinmeyen charset'te
/// utf-8'e düşer (eski Dart sunucusunun davranışıyla aynı).
async function bodyText(response: Response): Promise<string> {
  const bytes = new Uint8Array(await response.arrayBuffer());
  const charset = /charset=([^;\s]+)/i.exec(response.headers.get('content-type') ?? '')?.[1];
  if (charset != null) {
    try {
      return new TextDecoder(charset.replace(/^["']|["']$/g, '')).decode(bytes);
    } catch {
      // Bilinmeyen charset: utf-8 ile devam et.
    }
  }
  return new TextDecoder('utf-8').decode(bytes);
}
