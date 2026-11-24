/// Lettura dei file EPUB (ebook) senza librerie esterne: un EPUB è uno ZIP
/// con dentro pagine HTML, un elenco dell'ordine di lettura (spine) e un
/// indice (toc).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'book.dart';

class EpubException implements Exception {
  EpubException(this.message);
  final String message;
  @override
  String toString() => message;
}

const Map<String, String> _entities = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ',
  'laquo': '«', 'raquo': '»', 'ldquo': '“', 'rdquo': '”', 'lsquo': '‘',
  'rsquo': '’', 'hellip': '…', 'mdash': '—', 'ndash': '–', 'egrave': 'è',
  'eacute': 'é', 'agrave': 'à', 'aacute': 'á', 'igrave': 'ì', 'iacute': 'í',
  'ograve': 'ò', 'oacute': 'ó', 'ugrave': 'ù', 'uacute': 'ú', 'Egrave': 'È',
  'Eacute': 'É', 'Agrave': 'À', 'Igrave': 'Ì', 'Ograve': 'Ò', 'Ugrave': 'Ù',
  'ccedil': 'ç', 'Ccedil': 'Ç', 'ntilde': 'ñ', 'auml': 'ä', 'ouml': 'ö',
  'uuml': 'ü', 'Auml': 'Ä', 'Ouml': 'Ö', 'Uuml': 'Ü', 'szlig': 'ß',
  'copy': '©', 'reg': '®', 'deg': '°', 'middot': '·', 'shy': '',
  'euro': '€', 'times': '×', 'bull': '•', 'iexcl': '¡', 'iquest': '¿',
};

String decodeEntities(String s) => s.replaceAllMapped(
      RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'),
      (m) {
        final e = m.group(1)!;
        try {
          if (e.startsWith('#x')) return String.fromCharCode(int.parse(e.substring(2), radix: 16));
          if (e.startsWith('#')) return String.fromCharCode(int.parse(e.substring(1)));
        } catch (_) {
          return ' ';
        }
        return _entities[e] ?? m.group(0)!;
      },
    );

/// Converte una pagina HTML in testo, un paragrafo per riga.
String htmlToText(String html) {
  var s = html;
  s = s.replaceAll(RegExp(r'<head[\s\S]*?</head>', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
  // Note a piè di pagina come <sup>1</sup>: non si leggono.
  s = s.replaceAll(RegExp(r'<sup[\s\S]*?</sup>', caseSensitive: false), '');
  s = s.replaceAll(
    RegExp(r'<(br|/p|/div|/h[1-6]|/li|/tr|/blockquote|/section|/title|hr)\b[^>]*>', caseSensitive: false),
    '\n',
  );
  s = s.replaceAll(RegExp(r'<(p|div|h[1-6]|li|blockquote|section)\b[^>]*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = decodeEntities(s);
  final lines = s
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .toList();
  return lines.join('\n');
}

/// Il primo titolo (h1..h3) di una pagina HTML, se c'è.
String? firstHeading(String html) {
  final m = RegExp(r'<h([1-3])\b[^>]*>([\s\S]*?)</h\1>', caseSensitive: false).firstMatch(html);
  if (m == null) return null;
  final t = decodeEntities(m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), ' '))
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return t.isEmpty || t.length > 120 ? null : t;
}

String _attr(String tag, String name) {
  final m = RegExp('\\b$name\\s*=\\s*("([^"]*)"|\'([^\']*)\')', caseSensitive: false).firstMatch(tag);
  if (m == null) return '';
  return m.group(2) ?? m.group(3) ?? '';
}

String _tagText(String xml, String tag) {
  final m = RegExp('<(?:[a-z]+:)?$tag\\b[^>]*>([\\s\\S]*?)</(?:[a-z]+:)?$tag>', caseSensitive: false)
      .firstMatch(xml);
  if (m == null) return '';
  return decodeEntities(m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '')).replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

String _cleanHref(String href) {
  var h = href;
  final hash = h.indexOf('#');
  if (hash >= 0) h = h.substring(0, hash);
  try {
    h = Uri.decodeFull(h);
  } catch (_) {}
  return p.posix.normalize(h);
}

ImportedBook parseEpub(Uint8List bytes, {String fallbackTitle = 'Senza titolo'}) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw EpubException('Il file EPUB è danneggiato o non valido.');
  }

  final files = <String, ArchiveFile>{};
  for (final f in zip.files) {
    if (f.isFile) files[p.posix.normalize(f.name)] = f;
  }
  String? read(String path) {
    final f = files[p.posix.normalize(path)];
    if (f == null) return null;
    return _decode(f.content);
  }

  // 1. Dove si trova il file .opf?
  var opfPath = '';
  final container = read('META-INF/container.xml');
  if (container != null) {
    final m = RegExp(r'<rootfile\b[^>]*>', caseSensitive: false).firstMatch(container);
    if (m != null) opfPath = _attr(m.group(0)!, 'full-path');
  }
  if (opfPath.isEmpty) {
    opfPath = files.keys.firstWhere((k) => k.toLowerCase().endsWith('.opf'), orElse: () => '');
  }
  final opf = opfPath.isEmpty ? null : read(opfPath);
  if (opf == null) throw EpubException('Nel file EPUB manca l\'elenco dei contenuti.');
  final base = p.posix.dirname(opfPath) == '.' ? '' : p.posix.dirname(opfPath);
  String resolve(String dir, String href) =>
      _cleanHref(dir.isEmpty ? href : p.posix.join(dir, href));

  final title = _tagText(opf, 'title');
  final author = _tagText(opf, 'creator');

  // 2. Manifest: id -> file.
  final manifest = <String, String>{};
  final mediaTypes = <String, String>{};
  final properties = <String, String>{};
  for (final m in RegExp(r'<(?:[a-z]+:)?item\b[^>]*>', caseSensitive: false).allMatches(opf)) {
    final tag = m.group(0)!;
    final id = _attr(tag, 'id');
    final href = _attr(tag, 'href');
    if (id.isEmpty || href.isEmpty) continue;
    manifest[id] = resolve(base, href);
    mediaTypes[id] = _attr(tag, 'media-type');
    properties[id] = _attr(tag, 'properties');
  }

  // 3. Ordine di lettura.
  final spine = <String>[];
  for (final m in RegExp(r'<(?:[a-z]+:)?itemref\b[^>]*>', caseSensitive: false).allMatches(opf)) {
    final idref = _attr(m.group(0)!, 'idref');
    final href = manifest[idref];
    if (href != null && !spine.contains(href)) spine.add(href);
  }
  if (spine.isEmpty) throw EpubException('Il file EPUB non contiene pagine da leggere.');

  // 4. Indice: file -> titolo (EPUB 3 "nav", poi EPUB 2 "toc.ncx").
  final tocTitles = <String, String>{};
  final navId = properties.entries
      .firstWhere((e) => e.value.split(' ').contains('nav'), orElse: () => const MapEntry('', ''))
      .key;
  if (navId.isNotEmpty) {
    final navPath = manifest[navId]!;
    final nav = read(navPath);
    if (nav != null) {
      final navDir = p.posix.dirname(navPath) == '.' ? '' : p.posix.dirname(navPath);
      for (final a in RegExp(r'<a\b([^>]*)>([\s\S]*?)</a>', caseSensitive: false).allMatches(nav)) {
        final href = _attr(a.group(1)!, 'href');
        final text = decodeEntities(a.group(2)!.replaceAll(RegExp(r'<[^>]+>'), ' '))
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (href.isEmpty || text.isEmpty) continue;
        tocTitles.putIfAbsent(resolve(navDir, href), () => text);
      }
    }
  }
  if (tocTitles.isEmpty) {
    final ncxId = mediaTypes.entries
        .firstWhere((e) => e.value == 'application/x-dtbncx+xml', orElse: () => const MapEntry('', ''))
        .key;
    final ncxPath = ncxId.isNotEmpty ? manifest[ncxId]! : '';
    final ncx = ncxPath.isEmpty ? null : read(ncxPath);
    if (ncx != null) {
      final ncxDir = p.posix.dirname(ncxPath) == '.' ? '' : p.posix.dirname(ncxPath);
      for (final np in RegExp(r'<navPoint\b[\s\S]*?<content\b[^>]*>', caseSensitive: false).allMatches(ncx)) {
        final block = np.group(0)!;
        final label = _tagText(block, 'text');
        final content = RegExp(r'<content\b[^>]*>', caseSensitive: false).firstMatch(block);
        final src = content == null ? '' : _attr(content.group(0)!, 'src');
        if (label.isEmpty || src.isEmpty) continue;
        tocTitles.putIfAbsent(resolve(ncxDir, src), () => label);
      }
    }
  }

  // 5. Testo di ogni pagina, nell'ordine.
  final chapters = <Chapter>[];
  var pendingText = '';
  for (var i = 0; i < spine.length; i++) {
    final html = read(spine[i]);
    if (html == null) continue;
    final text = htmlToText(html);
    if (text.isEmpty) continue;
    final tocTitle = tocTitles[spine[i]];
    final heading = firstHeading(html);
    final words = RegExp(r'\S+').allMatches(text).length;

    // Pagine minuscole senza titolo (copertina, frontespizio): si uniscono
    // alla successiva.
    if (tocTitle == null && words < 60 && i + 1 < spine.length) {
      pendingText = pendingText.isEmpty ? text : '$pendingText\n$text';
      continue;
    }
    final full = pendingText.isEmpty ? text : '$pendingText\n$text';
    pendingText = '';
    final chTitle = tocTitle ?? heading ?? 'Capitolo ${chapters.length + 1}';
    chapters.add(Chapter(title: chTitle, text: full));
  }
  if (pendingText.isNotEmpty) {
    chapters.add(Chapter(title: 'Capitolo ${chapters.length + 1}', text: pendingText));
  }
  if (chapters.isEmpty) throw EpubException('Nel file EPUB non ho trovato testo da leggere.');

  // Copertina: EPUB 3 (properties="cover-image") o EPUB 2 (<meta name="cover">).
  Uint8List? cover;
  String? coverId = properties.entries
      .where((e) => e.value.split(' ').contains('cover-image'))
      .map((e) => e.key)
      .firstOrNull;
  if (coverId == null) {
    for (final m in RegExp(r'<meta\b[^>]*>', caseSensitive: false).allMatches(opf)) {
      final tag = m.group(0)!;
      if (_attr(tag, 'name').toLowerCase() == 'cover') {
        coverId = _attr(tag, 'content');
        break;
      }
    }
  }
  if (coverId == null || !(mediaTypes[coverId] ?? '').startsWith('image/')) {
    coverId = mediaTypes.entries
        .where((e) => e.value.startsWith('image/') &&
            ('${e.key} ${manifest[e.key]}').toLowerCase().contains('cover'))
        .map((e) => e.key)
        .firstOrNull;
  }
  final coverPath = coverId == null ? null : manifest[coverId];
  if (coverPath != null) {
    final f = files[p.posix.normalize(coverPath)];
    if (f != null) cover = Uint8List.fromList(f.content);
  }

  return ImportedBook(
    title: title.isEmpty ? fallbackTitle : title,
    author: author,
    format: 'epub',
    chapters: chapters,
    coverBytes: cover,
  );
}
