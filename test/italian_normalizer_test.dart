import 'package:d_voce/core/italian_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('numeri in lettere', () {
    const cases = {
      0: 'zero',
      1: 'uno',
      3: 'tre',
      13: 'tredici',
      21: 'ventuno',
      23: 'ventitré',
      28: 'ventotto',
      100: 'cento',
      101: 'centouno',
      103: 'centotré',
      108: 'centotto',
      180: 'centottanta',
      1000: 'mille',
      1984: 'millenovecentottantaquattro',
      2000: 'duemila',
      2023: 'duemilaventitré',
      21000: 'ventunomila',
      1000000: 'un milione',
      1000003: 'un milione tre',
      2500000: 'due milioni cinquecentomila',
    };
    cases.forEach((n, w) => expect(numberToItalian(n), w, reason: '$n'));
  });

  test('numeri romani', () {
    expect(romanToInt('IV'), 4);
    expect(romanToInt('XIV'), 14);
    expect(romanToInt('MCMLXXXIV'), 1984);
    expect(romanToInt('ciao'), isNull);
    expect(romanToInt(''), isNull);
  });

  test('frasi con numeri, prezzi, orari e abbreviazioni', () {
    expect(
      normalizeItalian('Nel 1984 c\'erano 25 persone.'),
      'Nel millenovecentottantaquattro c\'erano venticinque persone.',
    );
    expect(normalizeItalian('Il dott. Rossi pagò 3,50 €.'), 'Il dottor Rossi pagò tre euro e cinquanta.');
    expect(normalizeItalian('Costa 1.200 euro'), 'Costa milleduecento euro');
    expect(normalizeItalian('Alle 10:30 in punto'), 'Alle dieci e trenta in punto');
    expect(normalizeItalian('Il 33% dei voti'), 'Il trentatré per cento dei voti');
    expect(normalizeItalian('CAPITOLO IV'), 'CAPITOLO quattro');
    expect(normalizeItalian('Capitolo XII. Il ritorno'), 'Capitolo dodici. Il ritorno');
    expect(normalizeItalian('Vedi pag. 12, ecc.'), 'Vedi pagina dodici, eccetera');
    expect(normalizeItalian('Arrivò 1° e poi 2°'), 'Arrivò primo e poi secondo');
    expect(normalizeItalian('Fuori c\'erano 20°C'), 'Fuori c\'erano venti gradi');
    expect(normalizeItalian('pi greco vale 3,14'), 'pi greco vale tre virgola quattordici');
    expect(normalizeItalian('La Sig.ra Bianchi'), 'La Signora Bianchi');
  });

  test('le frasi senza numeri restano uguali', () {
    const t = 'Era una mattina fredda di novembre, e pioveva.';
    expect(normalizeItalian(t), t);
  });
}
