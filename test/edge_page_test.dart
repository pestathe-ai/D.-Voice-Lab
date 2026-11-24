import 'package:d_voce/core/book.dart';
import 'package:d_voce/core/edge_page.dart';
import 'package:d_voce/core/text_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const chapters = [
    Chapter(
      title: 'Capitolo 1',
      text: 'Capitolo 1\nPrima frase del libro. Seconda frase, un po\' più lunga della prima.\n'
          'Un altro paragrafo <con> caratteri & speciali.',
    ),
    Chapter(title: 'Capitolo 2', text: 'Capitolo 2\nIl secondo capitolo inizia qui.'),
  ];

  EdgePage build(int c, int k, {int max = kEdgePageChars}) => buildEdgePage(
        bookId: '1',
        positionAt: 123,
        bookUrl: 'http://x/book?id=1',
        bookTitle: 'Libro',
        chapters: chapters,
        chapter: c,
        chunk: k,
        posUrl: 'http://x/pos?id=1',
        returnUrl: 'intent://pos?id=1&c=__C__&k=__K__#Intent;end',
        nextUrl: (c, k) => 'http://x/book?id=1&c=$c&k=$k',
        maxChars: max,
      );

  test('i paragrafi usano la stessa numerazione del lettore', () {
    final paras = paragraphsOf(chapters[0], 0);
    final chunks = splitIntoChunks(chapters[0].text);
    for (final p in paras) {
      expect(chunks[p.chunk], startsWith(p.text.substring(0, 8)));
    }
  });

  test('pagina completa, con testo protetto e fine del libro', () {
    final page = build(0, 0);
    expect(page.html, contains('Prima frase del libro.'));
    expect(page.html, contains('&lt;con&gt; caratteri &amp; speciali'));
    expect(page.html, contains('Il secondo capitolo inizia qui.'));
    expect(page.html, contains('Fine del libro.'));
    expect(page.nextChapter, isNull);
    expect(page.html, contains('var SERVER_AT = 123;'));
    expect(page.html, contains("localStorage.getItem(KEY)"));
    expect(page.html, isNot(contains(r'$')), reason: 'nessuna interpolazione dimenticata');
  });

  test('riparte dal paragrafo dove eri arrivato', () {
    final paras = paragraphsOf(chapters[0], 0);
    final page = build(0, paras.last.chunk);
    expect(page.html, isNot(contains('Prima frase del libro.')));
    expect(page.html, contains('Un altro paragrafo'));
  });

  test('i libri lunghi si dividono in più pagine', () {
    final page = build(0, 0, max: 10);
    expect(page.nextChapter, isNotNull);
    expect(page.html, contains('Continua l\'ascolto'));
  });
}
