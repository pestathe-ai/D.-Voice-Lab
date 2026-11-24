/// Pulisce il testo estratto da PDF e file di testo e lo divide in capitoli.
///
/// Nei PDF il testo arriva "a righe": bisogna togliere numeri di pagina,
/// intestazioni e piè di pagina ripetuti, ricucire le parole spezzate dal
/// trattino a fine riga e rimettere insieme i paragrafi.
library;

import 'book.dart';
import 'italian_normalizer.dart' show romanToInt;

int? romanValue(String s) => romanToInt(s);

/// Dimensione indicativa di una "parte" quando il libro non ha capitoli
/// riconoscibili (circa mezz'ora di ascolto).
const int kFallbackPartChars = 25000;

// I numeri romani minuscoli (i, ii, xiv) sono numeri di pagina; quelli
// maiuscoli da soli su una riga sono quasi sempre titoli di capitolo.
final RegExp _pageNumber = RegExp(
  r'^(?:[-–—\s]*\d{1,4}[-–—\s]*|[ivxlcdm]{1,7}|(?:[Pp]ag(?:ina|\.)?|[Pp]age|PAGE|p\.)\s*\d{1,4}(?:\s*(?:di|of|/)\s*\d{1,4})?|\d{1,4}\s*(?:/|di|of)\s*\d{1,4})$',
);

const String _numberWords =
    'uno|due|tre|quattro|cinque|sei|sette|otto|nove|dieci|undici|dodici|tredici|'
    'quattordici|quindici|sedici|diciassette|diciotto|diciannove|venti|'
    'primo|prima|secondo|seconda|terzo|terza|quarto|quarta|quinto|quinta|sesto|sesta|'
    'settimo|settima|ottavo|ottava|nono|nona|decimo|decima|'
    'one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|'
    'first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth';

final RegExp _numberedHeading = RegExp(
  '^(?:capitolo|chapter|cap\\.|parte|part|libro|book|capítulo|chapitre|kapitel)'
  '\\s+(?:\\d{1,3}|[IVXLCDM]{1,7}|$_numberWords)\\b',
  caseSensitive: false,
);

final RegExp _namedHeading = RegExp(
  r"^(?:prologo|prologue|epilogo|epilogue|introduzione|introduction|prefazione|preface|"
  r"postfazione|afterword|ringraziamenti|acknowledgements|appendice|appendix|"
  r"premessa|nota dell'autore|nota del traduttore|conclusione|conclusioni)\s*[.:]?$",
  caseSensitive: false,
);

final RegExp _romanUpper = RegExp(r'^[IVXLCDM]{1,7}\.?$');
final RegExp _terminal = RegExp(r'[.!?…:;»”"’)\]]$');
final RegExp _endsWithHyphen = RegExp(r'\p{L}-$', unicode: true);
final RegExp _startsLower = RegExp(r'^\p{Ll}', unicode: true);

/// true se la riga sembra il titolo di un capitolo.
bool isChapterHeading(String line) {
  final t = line.trim();
  if (t.isEmpty || t.length > 80) return false;
  if (_numberedHeading.hasMatch(t)) {
    // "Capitolo 3" sì, "Parte 3 del denaro è stata spesa." no.
    return !(t.length > 40 && t.endsWith('.'));
  }
  return _namedHeading.hasMatch(t);
}

String _key(String line) => line
    .toLowerCase()
    .replaceAll(RegExp(r'\d+'), '#')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<String> _splitLines(String page) => page
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('­', '') // trattino "morbido"
    .replaceAll(' ', ' ')
    .replaceAll('ﬁ', 'fi')
    .replaceAll('ﬂ', 'fl')
    .split('\n')
    .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
    .toList();

/// Toglie da ogni pagina numeri di pagina e righe ripetute in alto e in
/// basso (titolo del libro, nome dell'autore…). Restituisce le righe.
List<List<String>> stripPageFurniture(List<String> pages) {
  final lines = pages.map(_splitLines).toList();
  final n = lines.length;

  final repeated = <String>{};
  if (n >= 4) {
    final counts = <String, int>{};
    for (final page in lines) {
      final nonEmpty = page.where((l) => l.isNotEmpty).toList();
      final edge = <String>{
        ...nonEmpty.take(2).map(_key),
        ...nonEmpty.reversed.take(2).map(_key),
      };
      for (final k in edge) {
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    final threshold = (n * 0.3).ceil() < 3 ? 3 : (n * 0.3).ceil();
    counts.forEach((k, c) {
      if (c >= threshold && k.length <= 70 && k.isNotEmpty) repeated.add(k);
    });
  }

  bool removable(String l) =>
      l.isEmpty || _pageNumber.hasMatch(l) || repeated.contains(_key(l));

  return [
    for (final page in lines)
      () {
        var start = 0;
        var end = page.length;
        var removed = 0;
        while (start < end && removed < 4 && removable(page[start])) {
          if (page[start].isNotEmpty) removed++;
          start++;
        }
        removed = 0;
        while (end > start && removed < 4 && removable(page[end - 1])) {
          if (page[end - 1].isNotEmpty) removed++;
          end--;
        }
        return page.sublist(start, end);
      }(),
  ];
}

int _median(List<int> values) {
  if (values.isEmpty) return 0;
  final s = [...values]..sort();
  return s[s.length ~/ 2];
}

/// Rimette insieme le righe in paragrafi.
List<String> linesToParagraphs(List<String> lines) {
  final lengths = [for (final l in lines) if (l.trim().length > 20) l.trim().length];
  final median = _median(lengths);
  // Righe lunghissime: il testo non è "a capo fisso", ogni riga è un paragrafo.
  final unwrapped = median == 0 || median > 150;

  final out = <String>[];
  var buf = '';
  void flush() {
    final t = buf.trim();
    if (t.isNotEmpty) out.add(t);
    buf = '';
  }

  for (final raw in lines) {
    final t = raw.trim();
    if (t.isEmpty) {
      flush();
      continue;
    }
    if (isChapterHeading(t) || _romanUpper.hasMatch(t)) {
      flush();
      out.add(t);
      continue;
    }
    if (unwrapped) {
      flush();
      out.add(t);
      continue;
    }
    if (buf.isEmpty) {
      buf = t;
    } else if (_endsWithHyphen.hasMatch(buf) && _startsLower.hasMatch(t)) {
      buf = buf.substring(0, buf.length - 1) + t;
    } else {
      buf = '$buf $t';
    }
    if (_terminal.hasMatch(t) && t.length < median * 0.8) flush();
  }
  flush();
  return out;
}

/// Divide i paragrafi in capitoli usando i titoli trovati nel testo.
/// Se i titoli sono meno di due, divide in parti di lunghezza simile.
List<Chapter> splitIntoChapters(List<String> paragraphs) {
  final chapters = <Chapter>[];
  var title = '';
  var body = <String>[];

  void close() {
    final text = body.join('\n').trim();
    if (text.isEmpty) return;
    chapters.add(Chapter(title: title, text: text));
  }

  var headings = 0;
  for (var i = 0; i < paragraphs.length; i++) {
    final p = paragraphs[i];
    final roman = _romanUpper.hasMatch(p) ? romanValue(p.replaceAll('.', '')) : null;
    if (isChapterHeading(p) || roman != null) {
      headings++;
      close();
      if (roman != null) {
        title = 'Capitolo $roman';
        body = [title];
      } else {
        title = p.replaceAll(RegExp(r'[.:]+$'), '');
        body = [p];
      }
      // Un sottotitolo breve subito dopo il titolo fa parte del titolo.
      if (i + 1 < paragraphs.length) {
        final next = paragraphs[i + 1];
        if (next.length <= 70 &&
            !_terminal.hasMatch(next) &&
            !isChapterHeading(next)) {
          title = '$title – $next';
          body.add(next);
          i++;
        }
      }
    } else {
      body.add(p);
    }
  }
  close();

  if (headings < 2) return splitBySize(paragraphs);

  // Testo prima del primo capitolo (dediche, note…): diventa "Inizio".
  return [
    for (final c in chapters)
      c.title.isEmpty ? Chapter(title: 'Inizio', text: c.text) : c,
  ];
}

/// Divide in parti di circa [target] caratteri, sempre tra un paragrafo
/// e l'altro.
List<Chapter> splitBySize(List<String> paragraphs, {int target = kFallbackPartChars}) {
  final parts = <Chapter>[];
  var body = <String>[];
  var size = 0;
  void close() {
    if (body.isEmpty) return;
    parts.add(Chapter(title: 'Parte ${parts.length + 1}', text: body.join('\n')));
    body = [];
    size = 0;
  }

  for (final p in paragraphs) {
    body.add(p);
    size += p.length + 1;
    if (size >= target) close();
  }
  // Un'ultima parte troppo corta si unisce alla precedente.
  if (body.isNotEmpty && parts.isNotEmpty && size < target ~/ 4) {
    final last = parts.removeLast();
    parts.add(Chapter(title: last.title, text: '${last.text}\n${body.join('\n')}'));
    body = [];
  }
  close();
  if (parts.length == 1) {
    return [Chapter(title: 'Testo completo', text: parts.single.text)];
  }
  return parts;
}

/// Una voce dell'indice di un PDF: titolo e pagina (da 1).
class OutlineEntry {
  const OutlineEntry(this.title, this.page);
  final String title;
  final int page;
}

/// Costruisce i capitoli di un PDF a partire dal testo delle pagine e,
/// se c'è, dall'indice incorporato nel file.
List<Chapter> chaptersFromPdfPages(List<String> pages, {List<OutlineEntry> outline = const []}) {
  final cleaned = stripPageFurniture(pages);

  // Indice del PDF: si usano le voci in ordine di pagina, una per pagina.
  final entries = <OutlineEntry>[];
  for (final e in [...outline]..sort((a, b) => a.page.compareTo(b.page))) {
    if (e.page < 1 || e.page > pages.length) continue;
    if (e.title.trim().isEmpty) continue;
    if (entries.isNotEmpty && entries.last.page == e.page) continue;
    entries.add(OutlineEntry(e.title.trim(), e.page));
  }

  if (entries.length >= 2) {
    final chapters = <Chapter>[];
    List<String> linesOf(int from, int to) =>
        [for (var i = from; i < to; i++) ...cleaned[i]];

    final before = linesToParagraphs(linesOf(0, entries.first.page - 1)).join('\n');
    for (var i = 0; i < entries.length; i++) {
      final from = entries[i].page - 1;
      final to = i + 1 < entries.length ? entries[i + 1].page - 1 : pages.length;
      var text = linesToParagraphs(linesOf(from, to)).join('\n');
      if (i == 0 && before.trim().isNotEmpty) {
        if (before.length > 1500) {
          chapters.add(Chapter(title: 'Inizio', text: before));
        } else {
          text = '$before\n$text';
        }
      }
      if (text.trim().isEmpty) continue;
      chapters.add(Chapter(title: entries[i].title, text: text));
    }
    if (chapters.length >= 2) return chapters;
  }

  final all = [for (final p in cleaned) ...p];
  return splitIntoChapters(linesToParagraphs(all));
}

/// Capitoli di un file di testo semplice.
List<Chapter> chaptersFromPlainText(String text) =>
    splitIntoChapters(linesToParagraphs(_splitLines(text)));

/// Titolo leggibile a partire dal nome del file.
String titleFromFileName(String name) {
  var t = name;
  final dot = t.lastIndexOf('.');
  if (dot > 0) t = t.substring(0, dot);
  t = t.replaceAll(RegExp(r'[_]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? 'Senza titolo' : t;
}
