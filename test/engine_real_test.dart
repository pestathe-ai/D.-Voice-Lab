// Prova "vera" delle voci: gira solo in CI, quando viene indicato
// l'archivio di un pacchetto scaricato (variabili DVOCE_PACK_ARCHIVE e
// DVOCE_PACK_ID). Usa lo stesso codice dell'app: estrazione, isolate della
// sintesi, normalizzazione dell'italiano e divisione in frasi.
import 'dart:io';

import 'package:d_voce/core/italian_normalizer.dart';
import 'package:d_voce/core/text_chunker.dart';
import 'package:d_voce/core/voice_catalog.dart';
import 'package:d_voce/core/wav.dart';
import 'package:d_voce/services/tts_worker.dart';
import 'package:d_voce/services/voice_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piper_phonemize/piper_phonemize.dart' as piper;

const _text = 'Capitolo I. Era una mattina fredda di novembre del 1984, '
    'e il dott. Rossi camminava lentamente lungo il porto. '
    'Alle 7:30 il mare era grigio, immobile; i gabbiani gridavano sopra le barche. '
    '«Perché proprio oggi?» si chiese, e per un attimo sorrise.';

void main() {
  final archive = Platform.environment['DVOCE_PACK_ARCHIVE'];
  final pack = packById(Platform.environment['DVOCE_PACK_ID']);
  final outDir = Platform.environment['DVOCE_OUT_DIR'] ?? 'samples';
  final skip = archive == null || pack == null ? 'DVOCE_PACK_ARCHIVE/DVOCE_PACK_ID non impostate' : null;

  late Directory installed;

  setUpAll(() async {
    if (skip != null) return;
    final dest = await Directory.systemTemp.createTemp('dvoce_x');
    final sw = Stopwatch()..start();
    extractVoiceArchive(archive!, dest.path);
    installed = Directory('${dest.path}/${pack!.folderName}');
    // ignore: avoid_print
    print('DVOCE_RESULT estrazione=${sw.elapsedMilliseconds}ms');
  });

  test('estrazione del pacchetto come fa l\'app', () {
    for (final f in pack!.requiredFiles) {
      expect(File('${installed.path}/$f').existsSync(), isTrue, reason: 'manca $f');
    }
    expect(Directory('${installed.path}/espeak-ng-data').existsSync(), isFalse);
  }, skip: skip);

  test('sintesi reale con le voci del pacchetto', () async {
    final worker = TtsWorker();
    final voices = voicesOfPack(pack!);
    final chunks = splitIntoChunks(_text);
    expect(chunks.length, greaterThan(1));
    await Directory(outDir).create(recursive: true);

    if (pack.engine == VoiceEngine.supertonic) {
      await worker.loadSupertonic(dir: installed.path, threads: 2);
    } else {
      // Per Piper servono i dati di pronuncia: si prendono dall'archivio.
      final tmp = await Directory.systemTemp.createTemp('dvoce_es');
      final r = await Process.run('tar', ['xjf', archive!, '-C', tmp.path, '--wildcards', '*/espeak-ng-data/*']);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      piper.initBindings();
      final ret = piper.PiperPhonemize.initialize('${tmp.path}/${pack.folderName}/espeak-ng-data');
      expect(ret, greaterThanOrEqualTo(0), reason: 'phonemizer init');
      await worker.loadPiper(
        model: '${installed.path}/${pack.id}.onnx',
        tokens: '${installed.path}/tokens.txt',
        threads: 2,
      );
    }

    // Per il pacchetto naturale si provano due voci (una per tipo), più
    // velocemente tutte le altre con una frase sola.
    final full = pack.engine == VoiceEngine.supertonic
        ? [voiceById('st-f3')!, voiceById('st-m2')!]
        : voices;
    for (final v in voices) {
      final isFull = full.contains(v);
      final writer = await WavFileWriter.open('$outDir/prova-${v.name.toLowerCase()}.wav', worker.sampleRate);
      final sw = Stopwatch()..start();
      for (final chunk in isFull ? chunks : chunks.take(1)) {
        final spoken = normalizeItalian(chunk);
        expect(spoken, isNot(matches(RegExp(r'\d'))), reason: 'cifre non convertite: $spoken');
        final SynthResult res;
        if (pack.engine == VoiceEngine.supertonic) {
          res = await worker.synthText(spoken, dir: installed.path, sid: v.sid, lang: 'it', steps: 5);
        } else {
          final cp = piper.PiperPhonemize.phonemize(spoken, voice: kEspeakVoice)
              .where((s) => s.isNotEmpty)
              .toList();
          res = await worker.synthPhonemes(
            cp,
            model: '${installed.path}/${pack.id}.onnx',
            tokens: '${installed.path}/tokens.txt',
          );
        }
        expect(res.samples.length, greaterThan(res.sampleRate ~/ 2), reason: 'audio troppo corto: $chunk');
        final peak = res.samples.fold<double>(0, (m, x) => x.abs() > m ? x.abs() : m);
        expect(peak, greaterThan(0.05), reason: 'audio muto');
        expect(res.sampleRate, writer.sampleRate);
        await writer.addSamples(res.samples);
        await writer.addSilence(const Duration(milliseconds: 250));
      }
      await writer.close();
      // ignore: avoid_print
      print('DVOCE_RESULT ${v.name}: audio=${writer.duration.inMilliseconds}ms '
          'tempo=${sw.elapsedMilliseconds}ms');
      if (!isFull) File('$outDir/prova-${v.name.toLowerCase()}.wav').deleteSync();
    }
    worker.dispose();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 10)));

  test('lingua straniera con la voce naturale', () async {
    final worker = TtsWorker();
    await worker.loadSupertonic(dir: installed.path, threads: 2);
    final res = await worker.synthText(
      'It was a bright cold day in April, and the clocks were striking thirteen.',
      dir: installed.path,
      sid: 5,
      lang: 'en',
    );
    expect(res.samples.length, greaterThan(res.sampleRate));
    worker.dispose();
  }, skip: skip ?? (pack?.engine == VoiceEngine.supertonic ? null : 'solo voci naturali'));
}
