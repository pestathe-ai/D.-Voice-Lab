import 'package:d_voce/core/languages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('riconosce la lingua del testo', () {
    expect(
      guessLanguage('Era una mattina fredda di novembre e il commissario camminava lungo il porto, '
          'pensando a quello che gli aveva detto la signora. Non era la prima volta che '
          'succedeva, e anche questo lo preoccupava per una ragione che non sapeva dire.'),
      'it',
    );
    expect(
      guessLanguage('It was a bright cold day in April, and the clocks were striking thirteen. '
          'Winston Smith, his chin nuzzled into his breast in an effort to escape the vile wind, '
          'slipped quickly through the glass doors of Victory Mansions, though not quickly enough.'),
      'en',
    );
    expect(guessLanguage('troppo corto'), 'it');
  });

  test('nomi delle lingue', () {
    expect(languageName('it'), 'Italiano');
    expect(languageName('xx'), 'xx');
    expect(kLanguages.length, 31);
    expect(isSupportedLanguage('fr'), isTrue);
  });
}
