import 'package:d_voce/core/voice_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('le voci hanno id unici e pacchetti coerenti', () {
    final ids = kVoices.map((v) => v.id).toSet();
    expect(ids.length, kVoices.length);
    for (final v in kVoices) {
      expect(kPacks.contains(v.pack), isTrue, reason: v.id);
      expect(v.sample, contains(v.name));
    }
  });

  test('il pacchetto naturale ha 10 voci, 5 femminili e 5 maschili', () {
    final st = voicesOfPack(kSupertonicPack);
    expect(st, hasLength(10));
    expect(st.map((v) => v.sid).toSet(), {0, 1, 2, 3, 4, 5, 6, 7, 8, 9});
    expect(st.where((v) => v.gender == VoiceGender.female).map((v) => v.sid), [0, 1, 2, 3, 4]);
    expect(st.where((v) => v.gender == VoiceGender.male).map((v) => v.sid), [5, 6, 7, 8, 9]);
  });

  test('indirizzi dei pacchetti', () {
    for (final p in kPacks) {
      expect(p.url, endsWith('/tts-models/${p.folderName}.tar.bz2'));
      expect(p.requiredFiles, isNotEmpty);
    }
    expect(kPaolaPack.requiredFiles, contains('${kPaolaPack.id}.onnx'));
  });

  test('voiceById e voce predefinita', () {
    expect(voiceById('it_IT-paola-medium')?.name, 'Paola');
    expect(voiceById(kDefaultVoiceId)?.natural, isTrue);
    expect(voiceById('non-esiste'), isNull);
    expect(voiceById(null), isNull);
  });
}
