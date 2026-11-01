import 'package:d_voce/core/voice_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('le voci hanno percorsi coerenti', () {
    expect(kVoices, isNotEmpty);
    final ids = kVoices.map((v) => v.id).toSet();
    expect(ids.length, kVoices.length);
    for (final v in kVoices) {
      expect(v.id, startsWith('it_IT-'));
      expect(v.url, endsWith('/vits-piper-${v.id}.tar.bz2'));
      expect(v.modelFile, '${v.id}.onnx');
      expect(v.sample, contains(v.name));
    }
  });

  test('voiceById', () {
    expect(voiceById('it_IT-paola-medium')?.name, 'Paola');
    expect(voiceById('non-esiste'), isNull);
    expect(voiceById(null), isNull);
  });
}
