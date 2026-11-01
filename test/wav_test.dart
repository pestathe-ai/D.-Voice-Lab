import 'dart:io';
import 'dart:typed_data';

import 'package:d_voce/core/wav.dart';
import 'package:flutter_test/flutter_test.dart';

int _u32(Uint8List b, int o) => ByteData.sublistView(b).getUint32(o, Endian.little);
int _u16(Uint8List b, int o) => ByteData.sublistView(b).getUint16(o, Endian.little);

void main() {
  test('converte i campioni e limita i valori fuori scala', () {
    final pcm = floatToPcm16(Float32List.fromList([0, 1, -1, 2, -2, 0.5]));
    final d = ByteData.sublistView(pcm);
    expect(d.getInt16(0, Endian.little), 0);
    expect(d.getInt16(2, Endian.little), 32767);
    expect(d.getInt16(4, Endian.little), -32767);
    expect(d.getInt16(6, Endian.little), 32767);
    expect(d.getInt16(8, Endian.little), -32767);
    expect(d.getInt16(10, Endian.little), 16384);
  });

  test('intestazione WAV corretta', () {
    final wav = encodeWav(Float32List(100), 22050);
    expect(wav.length, 44 + 200);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(_u32(wav, 4), 36 + 200);
    expect(_u16(wav, 22), 1);
    expect(_u32(wav, 24), 22050);
    expect(_u32(wav, 28), 44100);
    expect(_u16(wav, 34), 16);
    expect(_u32(wav, 40), 200);
  });

  test('WavFileWriter scrive a pezzi e aggiorna l\'intestazione', () async {
    final dir = await Directory.systemTemp.createTemp('dvoce');
    final path = '${dir.path}/out.wav';
    final w = await WavFileWriter.open(path, 16000);
    await w.addSamples(Float32List(1600));
    await w.addSilence(const Duration(milliseconds: 100));
    await w.addSamples(Float32List(800));
    await w.close();

    final bytes = await File(path).readAsBytes();
    const dataBytes = (1600 + 1600 + 800) * 2;
    expect(bytes.length, 44 + dataBytes);
    expect(_u32(bytes, 40), dataBytes);
    expect(_u32(bytes, 4), 36 + dataBytes);
    expect(w.duration, const Duration(milliseconds: 250));
    await dir.delete(recursive: true);
  });
}
