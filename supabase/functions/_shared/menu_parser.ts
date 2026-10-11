import { parseHTML } from 'npm:linkedom';

/// OBS'in gizlediği menü bağlantılarını çözer.
/// packages/obs_core/lib/src/menu_parser.dart portu.
///
/// OBS'te her menü satırı `/oibs/start.aspx?gkm=<token>` biçiminde bir
/// bağlantı taşır ve gerçek sayfa adı sunucuda saklanır.

export interface MenuLink {
  title: string;
  url: string;
}

const DEFAULT_BASE_URL = 'https://obs.alparslan.edu.tr';

export function parseMenu(html: string, baseUrl = DEFAULT_BASE_URL): MenuLink[] {
  const { document } = parseHTML(html);
  const links: MenuLink[] = [];

  for (const anchor of document.querySelectorAll('a.nav-link')) {
    const p = anchor.querySelector('p');
    const title = clean((p ?? anchor).textContent ?? '');
    if (title.length === 0) continue;

    // Bağlantı ya doğrudan href ile ya da menu_close(...) içinde olur.
    const href = anchor.getAttribute('href') ?? '';
    const onclick = anchor.getAttribute('onclick') ?? '';

    const url = href.includes('start.aspx') ? href : extractUrl(onclick);
    if (url == null) continue;

    links.push({ title, url: absolutize(url, baseUrl) });
  }

  return links;
}

/// `menu_close(this,'/oibs/start.aspx?gkm=...')` içindeki adresi çeker.
function extractUrl(onclick: string): string | null {
  const match = /'(\/oibs\/[^']+)'/.exec(onclick);
  if (match == null) return null;

  // HTML kaçışlarını geri al.
  return match[1].replaceAll('&#39;', "'").replaceAll('&amp;', '&');
}

/// Adresi mutlak URL'ye çevirir.
function absolutize(url: string, baseUrl: string): string {
  if (url.startsWith('http')) return url;
  if (url.startsWith('/')) return `${baseUrl}${url}`;
  return `${baseUrl}/oibs/std/${url}`;
}

function clean(value: string): string {
  return value.replace(/\s+/g, ' ').trim();
}
