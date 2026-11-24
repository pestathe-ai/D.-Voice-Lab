import 'package:d_voce/services/covers.dart';
import 'package:d_voce/services/system_tts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('voci del telefono: filtro per lingua e ordine', () {
    final raw = [
      {'name': 'it-it-x-itc-local', 'locale': 'it-IT', 'quality': 'normal', 'network_required': '0', 'features': ''},
      {'name': 'it-it-x-itd-network', 'locale': 'it-IT', 'quality': 'very high', 'network_required': '1', 'features': ''},
      {'name': 'en-us-x-sfg-local', 'locale': 'en-US', 'quality': 'high', 'network_required': '0', 'features': ''},
      {'name': 'it-it-x-kda-local', 'locale': 'it-IT', 'quality': 'high', 'network_required': '0', 'features': 'notInstalled'},
      {'name': 'it-it-x-itc-local', 'locale': 'it-IT', 'quality': 'normal', 'network_required': '0', 'features': ''},
      'spazzatura',
    ];
    final voices = parseSystemVoices(raw, 'it');
    expect(voices.map((v) => v.name).toList(), [
      'it-it-x-itd-network',
      'it-it-x-itc-local',
      'it-it-x-kda-local',
    ]);
    expect(voices.map((v) => v.label).toList(), ['Voce 1', 'Voce 2', 'Voce 3']);
    expect(voices.first.network, isTrue);
    expect(voices.first.id, 'sys:it-it-x-itd-network');
    expect(voices.last.installed, isFalse);
    expect(voices[1].description, contains('senza internet'));
  });

  test('titolo pulito per cercare la copertina', () {
    expect(cleanTitleForSearch('Il_nome_della_rosa (ebook ITA).pdf'), 'Il nome della rosa');
    expect(cleanTitleForSearch('Dune [v2.1] epub'), 'Dune');
    expect(cleanTitleForSearch('   '), '');
  });
}
