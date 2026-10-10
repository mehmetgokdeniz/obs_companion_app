import 'package:html/parser.dart' as parser;

/// OBS'in gizlediği menü bağlantılarını çözer.
///
/// OBS'te her menü satırı `/oibs/start.aspx?gkm=<token>` biçiminde bir
/// bağlantı taşır ve gerçek sayfa adı sunucuda saklanır. Menü, yalnızca
/// kullanıcının kendi oturumuyla açıldığında okunabilir.
class MenuLink {
  final String title;
  final String url;

  const MenuLink(this.title, this.url);
}

List<MenuLink> parseMenu(String html) {
  final document = parser.parse(html);
  final links = <MenuLink>[];

  for (final anchor in document.querySelectorAll('a.nav-link')) {
    final title = _clean(anchor.querySelector('p')?.text ?? anchor.text);
    if (title.isEmpty) continue;

    // Bağlantı ya doğrudan href ile ya da menu_close(...) içinde olur.
    final href = anchor.attributes['href'] ?? '';
    final onclick = anchor.attributes['onclick'] ?? '';

    final url = href.contains('start.aspx')
        ? href
        : _extractUrl(onclick);

    if (url == null) continue;
    links.add(MenuLink(title, _absolutize(url)));
  }

  return links;
}

/// `menu_close(this,'/oibs/start.aspx?gkm=...')` içindeki adresi çeker.
String? _extractUrl(String onclick) {
  final match = RegExp(r"'(/oibs/[^']+)'").firstMatch(onclick);
  if (match == null) return null;

  // HTML kaçışlarını geri al.
  return match.group(1)!
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}

/// Adresi mutlak URL'ye çevirir.
String _absolutize(String url) {
  if (url.startsWith('http')) return url;
  if (url.startsWith('/')) return 'https://obs.alparslan.edu.tr$url';
  return 'https://obs.alparslan.edu.tr/oibs/std/$url';
}

String _clean(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();
