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
  required String bookId,
  required int positionAt,
  required String bookUrl,
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
      // Ogni frase è un blocco a sé: così i tasti avanti/indietro di Edge
      // saltano di una frase e il segno si può mettere su ogni frase.
      final sentences = splitIntoChunks(para.text);
      final firstSentence = (c == chapter && i == startIdx)
          ? (chunk - para.chunk).clamp(0, sentences.length - 1).toInt()
          : 0;
      final heading = i == 0 && para.text.length < 90 && sentences.length == 1;
      for (var j = firstSentence; j < sentences.length; j++) {
        final cls = j == firstSentence ? 's first' : 's';
        final tag = heading ? 'h3' : 'p';
        body.writeln('<$tag class="$cls" data-c="${para.chapter}" data-k="${para.chunk + j}">'
            '${_esc.convert(sentences[j])}</$tag>');
      }
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
  p { margin:0 0 4px; }
  p.first, h3.first { margin-top:18px; }
  .end { margin-top:40px; text-align:center; font-family:sans-serif; }
  a { color:#f28c38; }
  [data-c] { cursor:pointer; }
  .mark { outline:2px solid #f28c38; outline-offset:4px; border-radius:4px; }
  #toast { position:fixed; left:50%; bottom:76px; transform:translateX(-50%); background:#222a3b;
           color:#ede9e1; font:14px sans-serif; padding:10px 14px; border-radius:12px;
           opacity:0; transition:opacity .3s; pointer-events:none; }
  #back { position:fixed; right:14px; bottom:14px; background:#f28c38; color:#14213d;
          font:700 15px sans-serif; padding:12px 16px; border-radius:24px;
          text-decoration:none; box-shadow:0 4px 14px #0008; }
</style>
</head>
<body>
<article id="book">
$body$end
</article>
<div id="toast" aria-hidden="true"></div>
<a id="back" href="${_esc.convert(returnUrl)}" aria-hidden="true">Torna a D. Voce</a>
<script>
(function () {
  var KEY = 'dvoce:' + ${jsonEncode(bookId)};
  var SERVER_AT = $positionAt;
  var BOOK_URL = ${jsonEncode(bookUrl)};
  var POS_URL = ${jsonEncode(posUrl)};
  var RETURN_URL = ${jsonEncode(returnUrl)};

  // Il segno salvato qui da Edge è più recente di quello di D. Voce?
  // Allora si riparte da lì (D. Voce prepara la pagina da quel punto).
  try {
    var saved = JSON.parse(localStorage.getItem(KEY) || 'null');
    var first = document.querySelector('[data-c]');
    if (saved && saved.t > SERVER_AT && first &&
        (String(saved.c) !== first.getAttribute('data-c') || String(saved.k) !== first.getAttribute('data-k'))) {
      location.replace(BOOK_URL + '&c=' + saved.c + '&k=' + saved.k + '&t=' + saved.t + '&fromls=1');
      return;
    }
  } catch (e) {}

  var last = '';
  var pinned = null;
  function toast(msg) {
    var t = document.getElementById('toast');
    t.textContent = msg;
    t.style.opacity = 1;
    setTimeout(function () { t.style.opacity = 0; }, 1800);
  }
  function save(c, k, force) {
    var now = Date.now();
    var key = c + ':' + k;
    document.getElementById('back').href =
      RETURN_URL.replace('__C__', c).replace('__K__', k).replace('__T__', now);
    if (key === last && !force) return;
    last = key;
    try { localStorage.setItem(KEY, JSON.stringify({ c: +c, k: +k, t: now })); } catch (e) {}
    var url = POS_URL + '&c=' + c + '&k=' + k + '&t=' + now;
    try {
      if (navigator.sendBeacon) { navigator.sendBeacon(url); }
      else { fetch(url, { cache: 'no-store' }).catch(function () {}); }
    } catch (e) {}
  }
  // Il paragrafo che si sta leggendo: quello evidenziato da Edge, se si
  // riesce a vederlo, altrimenti il primo visibile in alto.
  function current() {
    try {
      var sel = window.getSelection && window.getSelection();
      if (sel && sel.rangeCount && !sel.isCollapsed) {
        var n = sel.getRangeAt(0).startContainer;
        while (n && n.nodeType !== 1) n = n.parentNode;
        while (n && !(n.getAttribute && n.getAttribute('data-c'))) n = n.parentNode;
        if (n) return n;
      }
    } catch (e) {}
    var els = document.querySelectorAll('[data-c]');
    var limit = window.innerHeight * 0.3;
    var pick = els.length ? els[0] : null;
    for (var i = 0; i < els.length; i++) {
      if (els[i].getBoundingClientRect().bottom > limit) { pick = els[i]; break; }
    }
    return pick;
  }
  function report() {
    if (pinned) return;
    var el = current();
    if (el) save(el.getAttribute('data-c'), el.getAttribute('data-k'), false);
  }
  // Tocca un paragrafo per mettere il segno lì.
  document.getElementById('book').addEventListener('click', function (ev) {
    var n = ev.target;
    while (n && !(n.getAttribute && n.getAttribute('data-c'))) n = n.parentNode;
    if (!n || ev.target.tagName === 'A') return;
    var old = document.querySelector('.mark');
    if (old) old.classList.remove('mark');
    n.classList.add('mark');
    pinned = n;
    save(n.getAttribute('data-c'), n.getAttribute('data-k'), true);
    toast('Segno messo su questa frase');
    setTimeout(function () { pinned = null; }, 60000);
  });
  setInterval(report, 3000);
  window.addEventListener('scroll', function () { setTimeout(report, 400); }, { passive: true });
  document.addEventListener('selectionchange', function () { setTimeout(report, 200); });
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'hidden') report();
  });
  window.addEventListener('pagehide', report);
  setTimeout(report, 1500);
})();
</script>
</body>
</html>
''';
  return EdgePage(html: html, nextChapter: nextChapter, nextChunk: nextChunk);
}
