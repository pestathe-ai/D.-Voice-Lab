/// La pagina che D. Voce prepara per Microsoft Edge: il testo pulito del
/// libro, da dove eri arrivato, da far leggere con "Leggi ad alta voce".
library;

import 'dart:convert';

import 'book.dart';
import 'text_chunker.dart';

/// Quanti caratteri mettere in una pagina (circa 2 ore e mezza di ascolto).
const int kEdgePageChars = 130000;

/// Un paragrafo con la sua posizione nel libro.
class EdgeParagraph {
  const EdgeParagraph(this.chapter, this.chunk, this.text);
  final int chapter;

  /// Prima "frase" (pezzo del lettore) del paragrafo nel capitolo.
  final int chunk;
  final String text;
}

/// I paragrafi di un capitolo con l'indice della loro prima frase: la stessa
/// numerazione usata dal lettore interno, così il segnalibro coincide.
List<EdgeParagraph> paragraphsOf(Chapter ch, int chapterIndex) {
  final out = <EdgeParagraph>[];
  var k = 0;
  for (final raw in ch.text.split('\n')) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    final n = splitIntoChunks(t).length;
    if (n == 0) continue;
    out.add(EdgeParagraph(chapterIndex, k, t));
    k += n;
  }
  return out;
}

class EdgePage {
  const EdgePage({required this.html, this.nextChapter, this.nextChunk});
  final String html;

  /// Da dove riparte la pagina successiva (null se il libro è finito).
  final int? nextChapter;
  final int? nextChunk;
}

const _esc = HtmlEscape(HtmlEscapeMode.element);

/// Costruisce la pagina a partire dal capitolo [chapter] e dalla frase
/// [chunk]. [posUrl] riceve la posizione mentre si ascolta; [returnUrl] è
/// il collegamento per tornare a D. Voce; [nextUrl] costruisce il link alla
/// pagina successiva.
EdgePage buildEdgePage({
  required String bookTitle,
  required List<Chapter> chapters,
  required int chapter,
  required int chunk,
  required String posUrl,
  required String returnUrl,
  required String Function(int chapter, int chunk) nextUrl,
  int maxChars = kEdgePageChars,
}) {
  final body = StringBuffer();
  var chars = 0;
  int? nextChapter;
  int? nextChunk;

  outer:
  for (var c = chapter; c < chapters.length; c++) {
    final paras = paragraphsOf(chapters[c], c);
    var startIdx = 0;
    if (c == chapter) {
      // Il paragrafo che contiene la frase dove eri arrivato.
      for (var i = 0; i < paras.length; i++) {
        if (paras[i].chunk <= chunk) startIdx = i;
      }
    }
    final title = chapters[c].title.trim();
    final firstText = paras.isEmpty ? '' : paras[startIdx].text;
    if (startIdx == 0 && title.isNotEmpty && !firstText.startsWith(title.split(' – ').first)) {
      body.writeln('<h2>${_esc.convert(title)}</h2>');
    }
    for (var i = startIdx; i < paras.length; i++) {
      final para = paras[i];
      if (chars >= maxChars && !(c == chapter && i == startIdx)) {
        nextChapter = c;
        nextChunk = para.chunk;
        break outer;
      }
      final tag = i == 0 && para.text.length < 90 ? 'h3' : 'p';
      body.writeln('<$tag data-c="${para.chapter}" data-k="${para.chunk}">'
          '${_esc.convert(para.text)}</$tag>');
      chars += para.text.length;
    }
  }

  final end = nextChapter == null
      ? '<p class="end">Fine del libro.</p>'
      : '<p class="end"><a href="${_esc.convert(nextUrl(nextChapter, nextChunk!))}">'
          'Continua l\'ascolto</a></p>';

  final html = '''<!doctype html>
<html lang="it">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_esc.convert(bookTitle)}</title>
<style>
  :root { color-scheme: dark; }
  body { background:#0d1018; color:#ede9e1; margin:0; padding:24px 20px 120px;
         font:19px/1.7 Georgia, "Noto Serif", serif; }
  h2 { font:700 24px/1.3 sans-serif; color:#f28c38; margin:40px 0 16px; }
  h3 { font:700 20px/1.4 sans-serif; margin:28px 0 12px; }
  p { margin:0 0 16px; }
  .end { margin-top:40px; text-align:center; font-family:sans-serif; }
  a { color:#f28c38; }
  #back { position:fixed; right:14px; bottom:14px; background:#f28c38; color:#14213d;
          font:700 15px sans-serif; padding:12px 16px; border-radius:24px;
          text-decoration:none; box-shadow:0 4px 14px #0008; }
</style>
</head>
<body>
<article id="book">
$body$end
</article>
<a id="back" href="${_esc.convert(returnUrl)}" aria-hidden="true">Torna a D. Voce</a>
<script>
(function () {
  var last = '';
  function current() {
    var els = document.querySelectorAll('[data-c]');
    var limit = window.innerHeight * 0.3;
    var pick = els.length ? els[0] : null;
    for (var i = 0; i < els.length; i++) {
      if (els[i].getBoundingClientRect().bottom > limit) { pick = els[i]; break; }
    }
    return pick;
  }
  function report() {
    var el = current();
    if (!el) return;
    var c = el.getAttribute('data-c'), k = el.getAttribute('data-k');
    var back = document.getElementById('back');
    back.href = ${jsonEncode(returnUrl)}.replace('__C__', c).replace('__K__', k);
    var key = c + ':' + k;
    if (key === last) return;
    last = key;
    try { fetch(${jsonEncode(posUrl)} + '&c=' + c + '&k=' + k, { cache: 'no-store' }).catch(function () {}); } catch (e) {}
  }
  setInterval(report, 4000);
  window.addEventListener('scroll', function () { setTimeout(report, 500); }, { passive: true });
  setTimeout(report, 1000);
})();
</script>
</body>
</html>
''';
  return EdgePage(html: html, nextChapter: nextChapter, nextChunk: nextChunk);
}
