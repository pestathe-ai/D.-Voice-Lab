// Prova "vera" della voce: gira solo in CI, quando viene indicato
// l'archivio di una voce scaricata (variabile DVOCE_VOICE_ARCHIVE).
import 'dart:io';
import 'dart:typed_data';

import 'package:d_voce/core/text_chunker.dart';
import 'package:d_voce/core/voice_catalog.dart';
import 'package:d_voce/core/wav.dart';
import 'package:d_voce/services/voice_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piper_phonemize/piper_phonemize.dart' as piper;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void main() {
  final archive = Platform.environment['DVOCE_VOICE_ARCHIVE'];
  final out = Platform.environment['DVOCE_OUT'] ?? 'prova.wav';
  final skip = archive == null ? 'DVOCE_VOICE_ARCHIVE non impostata' : null;

  test('estrazione della voce come fa l\'app', () async {
    final dest = await Directory.systemTemp.createTemp('dvoce_x');
    extractVoiceArchive(archive!, dest.path);
    final folders = dest.listSync().whereType<Directory>().toList();
    expect(folders, hasLength(1));
    final files = folders.single.listSync().map((e) => e.path.split('/').last).toSet();
    expect(files, contains('tokens.txt'));
    expect(files.where((f) => f.endsWith('.onnx')), hasLength(1));
    expect(files, isNot(contains('espeak-ng-data')));
    final id = folders.single.path.split('/').last.replaceFirst('vits-piper-', '');
    expect(voiceById(id), isNotNull, reason: 'voce $id non presente nel catalogo');
  }, skip: skip);

  test('sintesi italiana reale', () async {
    final dest = await Directory.systemTemp.createTemp('dvoce_s');
    final r = await Process.run('tar', ['xjf', archive!, '-C', dest.path]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final folder = dest.listSync().whereType<Directory>().single;
    final model = folder
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('.onnx'))
        .path;
    final tokens = '${folder.path}/tokens.txt';

    piper.initBindings();
    final ret = piper.PiperPhonemize.initialize('${folder.path}/espeak-ng-data');
    expect(ret, greaterThanOrEqualTo(0), reason: 'phonemizer init');

    sherpa.initBindings();
    final tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(model: model, tokens: tokens),
          numThreads: 2,
        ),
      ),
    );
    expect(tts.sampleRate, greaterThan(0));

    const text = 'Buongiorno! Questa è una prova di D. Voce. '
        'Il testo viene letto direttamente sul telefono, anche senza internet. '
        'Perché, però, l\'accento di città e di più deve essere giusto.';
    final writer = await WavFileWriter.open(out, tts.sampleRate);
    final sw = Stopwatch()..start();
    for (final chunk in splitIntoChunks(text)) {
      final cp = piper.PiperPhonemize.phonemize(chunk, voice: kEspeakVoice)
          .where((s) => s.isNotEmpty)
          .toList();
      expect(cp, isNotEmpty, reason: 'nessun fonema per: $chunk');
      final audio = tts.generateWithConfig(
        text: '',
        config: sherpa.OfflineTtsGenerationConfig(phonemeCodepoints: cp),
      );
      expect(audio.samples.length, greaterThan(audio.sampleRate ~/ 2));
      final peak = audio.samples.fold<double>(0, (m, v) => v.abs() > m ? v.abs() : m);
      expect(peak, greaterThan(0.05), reason: 'audio muto');
      await writer.addSamples(Float32List.fromList(audio.samples));
      await writer.addSilence(const Duration(milliseconds: 250));
    }
    await writer.close();
    tts.free();
    // ignore: avoid_print
    print('DVOCE_RESULT audio=${writer.duration.inMilliseconds}ms '
        'tempo=${sw.elapsedMilliseconds}ms rate=${writer.sampleRate}');
    expect(writer.duration, greaterThan(const Duration(seconds: 5)));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
}
