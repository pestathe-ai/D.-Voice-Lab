import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Una copertina trovata online.
class CoverCandidate {
  const CoverCandidate({required this.url, required this.source, this.title = ''});
  final String url;
  final String source;
  final String title;
}

/// Cerca le copertine su Open Library e Google Books (servizi pubblici e
/// gratuiti, pensati proprio per questo).
class CoverSearch {
  CoverSearch({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<Object?> _getJson(Uri uri) async {
    final req = await _client.getUrl(uri).timeout(const Duration(seconds: 12));
    req.headers.set(HttpHeaders.userAgentHeader, 'DVoce/0.3 (app audiolibri personale)');
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null;
    }
    final body = await res.transform(utf8.decoder).join();
    return jsonDecode(body);
  }

  /// Cerca le copertine per [title] (e [author], se c'è).
  Future<List<CoverCandidate>> search(String title, {String author = ''}) async {
    final t = cleanTitleForSearch(title);
    if (t.isEmpty) return const [];
    final results = <CoverCandidate>[];
    final seen = <String>{};
    void add(CoverCandidate c) {
      if (seen.add(c.url)) results.add(c);
    }

    final futures = await Future.wait<List<CoverCandidate>>([
      _openLibrary(t, author).catchError((Object _) => <CoverCandidate>[]),
      _googleBooks(t, author).catchError((Object _) => <CoverCandidate>[]),
    ]);
    // Si alternano le due fonti: i primi risultati di ognuna sono i migliori.
    final a = futures[0];
    final b = futures[1];
    for (var i = 0; i < a.length || i < b.length; i++) {
      if (i < a.length) add(a[i]);
      if (i < b.length) add(b[i]);
    }
    return results.take(16).toList();
  }

  Future<List<CoverCandidate>> _openLibrary(String title, String author) async {
    final params = {
      'title': title,
      if (author.trim().isNotEmpty) 'author': author.trim(),
      'limit': '12',
      'fields': 'title,author_name,cover_i',
    };
    final json = await _getJson(Uri.https('openlibrary.org', '/search.json', params));
    if (json is! Map) return const [];
    final docs = json['docs'];
    if (docs is! List) return const [];
    return [
      for (final d in docs)
        if (d is Map && d['cover_i'] is int)
          CoverCandidate(
            url: 'https://covers.openlibrary.org/b/id/${d['cover_i']}-L.jpg?default=false',
            source: 'Open Library',
            title: '${d['title'] ?? ''}',
          ),
    ];
  }

  Future<List<CoverCandidate>> _googleBooks(String title, String author) async {
    var q = 'intitle:$title';
    if (author.trim().isNotEmpty) q += ' inauthor:${author.trim()}';
    final json = await _getJson(Uri.https('www.googleapis.com', '/books/v1/volumes', {
      'q': q,
      'maxResults': '12',
      'printType': 'books',
    }));
    if (json is! Map) return const [];
    final items = json['items'];
    if (items is! List) return const [];
    final out = <CoverCandidate>[];
    for (final it in items) {
      if (it is! Map) continue;
      final info = it['volumeInfo'];
      if (info is! Map) continue;
      final links = info['imageLinks'];
      if (links is! Map) continue;
      final raw = (links['extraLarge'] ?? links['large'] ?? links['medium'] ??
              links['thumbnail'] ?? links['smallThumbnail'])
          ?.toString();
      if (raw == null || raw.isEmpty) continue;
      final url = raw
          .replaceFirst('http://', 'https://')
          .replaceAll('&edge=curl', '');
      out.add(CoverCandidate(url: url, source: 'Google Libri', title: '${info['title'] ?? ''}'));
    }
    return out;
  }

  /// Scarica un'immagine; null se non è un'immagine valida.
  Future<Uint8List?> download(String url) async {
    try {
      final req = await _client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 12));
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final type = res.headers.contentType?.primaryType ?? '';
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
        if (builder.length > 8 * 1024 * 1024) return null;
      }
      final bytes = builder.takeBytes();
      if (bytes.length < 2000) return null; // segnaposto vuoti
      if (type.isNotEmpty && type != 'image') return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// La prima copertina che si riesce davvero a scaricare.
  Future<Uint8List?> findFirst(String title, {String author = ''}) async {
    final list = await search(title, author: author);
    for (final c in list.take(4)) {
      final bytes = await download(c.url);
      if (bytes != null) return bytes;
    }
    return null;
  }

  void close() => _client.close(force: true);
}

/// Toglie dal titolo le parti che confondono la ricerca: estensioni,
/// parentesi, "ebook", numeri di versione…
String cleanTitleForSearch(String title) {
  var t = title;
  t = t.replaceAll(RegExp(r'\.(pdf|epub|txt|md)$', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), ' ');
  t = t.replaceAll(RegExp(r'\b(ebook|e-book|epub|pdf|ita|italiano|copia|scan|v\d+(\.\d+)*)\b', caseSensitive: false), ' ');
  t = t.replaceAll(RegExp(r'[_\-–—]+'), ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}
