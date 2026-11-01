import 'package:d_voce/core/text_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('testo vuoto o senza parole non produce frasi', () {
    expect(splitIntoChunks(''), isEmpty);
    expect(splitIntoChunks('   \n\n  '), isEmpty);
    expect(splitIntoChunks('... !!! ---'), isEmpty);
  });

  test('divide alle fine delle frasi', () {
    const t = 'Questa è la prima frase abbastanza lunga da stare da sola. '
        'Questa invece è la seconda frase, anche lei piuttosto lunga! '
        'E la terza arriva con un punto di domanda finale?';
    final c = splitIntoChunks(t);
    expect(c, hasLength(3));
    expect(c.first, startsWith('Questa è la prima'));
    expect(c.last, endsWith('finale?'));
  });

  test('unisce le frasi molto brevi', () {
    final c = splitIntoChunks('Ciao. Come stai? Io bene, grazie mille davvero.');
    expect(c, hasLength(1));
    expect(c.single, 'Ciao. Come stai? Io bene, grazie mille davvero.');
  });

  test('non unisce paragrafi diversi', () {
    final c = splitIntoChunks('Titolo\n\nCorpo del testo.');
    expect(c, ['Titolo', 'Corpo del testo.']);
  });

  test('normalizza gli spazi', () {
    final c = splitIntoChunks('Molti    spazi\tqui   dentro, ma va bene lo stesso.');
    expect(c.single, 'Molti spazi qui dentro, ma va bene lo stesso.');
  });

  test('spezza le frasi troppo lunghe senza superare il limite', () {
    final long = List.generate(120, (i) => 'parola$i').join(' ');
    final withCommas = List.generate(30, (i) => 'questo è il pezzo numero $i').join(', ');
    for (final t in [long, withCommas]) {
      final c = splitIntoChunks(t, maxLen: 100);
      expect(c.length, greaterThan(1));
      for (final chunk in c) {
        expect(chunk.length, lessThanOrEqualTo(100));
      }
      // Nessuna parola persa.
      expect(c.join(' ').split(' ').length, t.split(' ').length);
    }
  });

  test('taglia una parola lunghissima', () {
    final url = 'https://esempio.it/${'a' * 400}';
    final c = splitIntoChunks(url, maxLen: 100);
    expect(c.every((x) => x.length <= 100), isTrue);
    expect(c.join(), url);
  });
}
