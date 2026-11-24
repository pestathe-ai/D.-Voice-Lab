import 'package:d_voce/core/text_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';

/// Crea una pagina finta di PDF, con intestazione e numero di pagina.
const words = ['alfa', 'beta', 'gamma', 'delta', 'epsilon', 'zeta', 'eta', 'theta', 'iota', 'kappa'];

String page(int n, List<String> body) =>
    ['IL NOME DEL LIBRO', '', ...body, '', '$n'].join('\r\n');

void main() {
  test('riconosce i titoli dei capitoli', () {
    for (final t in ['Capitolo 1', 'CAPITOLO XII', 'Capitolo primo', 'Chapter 3', 'Parte seconda', 'Prologo', 'Epilogo.']) {
      expect(isChapterHeading(t), isTrue, reason: t);
    }
    for (final t in [
      'Parte del denaro era sparita e nessuno sapeva dove fosse finita davvero.',
      'Il capitolo successivo',
      'Era una notte buia e tempestosa.',
      '',
    ]) {
      expect(isChapterHeading(t), isFalse, reason: t);
    }
  });

  test('toglie intestazioni ripetute e numeri di pagina', () {
    final pages = [
      for (var i = 1; i <= 6; i++) page(i, ['Testo ${words[i]} della pagina, abbastanza lungo da sembrare vero.']),
    ];
    final cleaned = stripPageFurniture(pages);
    for (var i = 0; i < 6; i++) {
      expect(cleaned[i].join(' '), isNot(contains('IL NOME DEL LIBRO')));
      expect(cleaned[i].where((l) => l == '${i + 1}'), isEmpty);
      expect(cleaned[i].join(' '), contains('Testo ${words[i + 1]} della pagina'));
    }
  });

  test('ricuce righe e parole spezzate in paragrafi', () {
    final lines = [
      'Era una mattina fredda di novembre e il commissario cammi-',
      'nava lentamente lungo il porto, pensando a quello che gli',
      'aveva detto la signora la sera prima, al telefono.',
      'Poi si fermò.',
      'Il mare era grigio e immobile come una lastra di piombo',
      'sotto il cielo basso, e i gabbiani gridavano sopra le barche.',
    ];
    final paras = linesToParagraphs(lines);
    expect(paras, hasLength(2));
    expect(paras.first, contains('il commissario camminava lentamente'));
    expect(paras.first, endsWith('Poi si fermò.'));
    expect(paras.last, startsWith('Il mare era grigio'));
  });

  test('divide in capitoli usando i titoli nel testo', () {
    final text = [
      'Dedica a mia madre.',
      '',
      'Capitolo 1',
      'Il porto',
      '',
      'Era una mattina fredda di novembre.',
      '',
      'Capitolo 2',
      '',
      'La sera arrivò presto quel giorno.',
      '',
      'Capitolo 3',
      '',
      'E poi venne la notte.',
    ].join('\n');
    final chapters = chaptersFromPlainText(text);
    expect(chapters.map((c) => c.title).toList(), [
      'Inizio',
      'Capitolo 1 – Il porto',
      'Capitolo 2',
      'Capitolo 3',
    ]);
    expect(chapters[1].text, contains('Era una mattina fredda'));
    expect(chapters[1].text, startsWith('Capitolo 1'));
  });

  test('i numeri romani da soli diventano capitoli', () {
    final text = ['I', '', 'Primo pezzo di storia.', '', 'II', '', 'Secondo pezzo.'].join('\n');
    final chapters = chaptersFromPlainText(text);
    expect(chapters.map((c) => c.title).toList(), ['Capitolo 1', 'Capitolo 2']);
  });

  test('senza titoli divide in parti', () {
    final paras = List.generate(40, (i) => 'Paragrafo $i ${'parola ' * 150}');
    final chapters = splitIntoChapters(paras);
    expect(chapters.length, greaterThan(1));
    expect(chapters.first.title, 'Parte 1');
    expect(chapters.map((c) => c.text).join('\n'), paras.join('\n'));

    final short = chaptersFromPlainText('Un testo breve.\n\nDi due paragrafi.');
    expect(short.single.title, 'Testo completo');
  });

  test('PDF con indice: un capitolo per voce dell\'indice', () {
    final pages = [
      for (var i = 1; i <= 8; i++) page(i, ['Contenuto ${words[i]} del libro di prova, con una frase.']),
    ];
    final chapters = chaptersFromPdfPages(pages, outline: const [
      OutlineEntry('Primo', 1),
      OutlineEntry('Secondo', 4),
      OutlineEntry('Terzo', 7),
    ]);
    expect(chapters.map((c) => c.title).toList(), ['Primo', 'Secondo', 'Terzo']);
    expect(chapters[1].text, contains('Contenuto ${words[4]}'));
    expect(chapters[1].text, contains('Contenuto ${words[6]}'));
    expect(chapters[1].text, isNot(contains('Contenuto ${words[7]}')));
  });

  test('titolo dal nome del file', () {
    expect(titleFromFileName('Il_nome_della_rosa.pdf'), 'Il nome della rosa');
    expect(titleFromFileName('libro.epub'), 'libro');
  });
}
