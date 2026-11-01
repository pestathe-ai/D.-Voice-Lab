import 'dart:io';
import 'dart:typed_data';

/// Converte campioni float (-1..1) in PCM 16 bit little-endian.
Uint8List floatToPcm16(Float32List samples) {
  final out = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    var v = samples[i];
    if (v.isNaN) v = 0;
    if (v > 1) v = 1;
    if (v < -1) v = -1;
    out.setInt16(i * 2, (v * 32767).round(), Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Intestazione WAV (RIFF) per audio mono a 16 bit.
Uint8List wavHeader({required int sampleRate, required int dataBytes}) {
  final h = ByteData(44);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      h.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  h.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  h.setUint32(16, 16, Endian.little); // dimensione blocco fmt
  h.setUint16(20, 1, Endian.little); // PCM
  h.setUint16(22, 1, Endian.little); // mono
  h.setUint32(24, sampleRate, Endian.little);
  h.setUint32(28, sampleRate * 2, Endian.little); // byte al secondo
  h.setUint16(32, 2, Endian.little); // byte per campione
  h.setUint16(34, 16, Endian.little); // bit per campione
  ascii(36, 'data');
  h.setUint32(40, dataBytes, Endian.little);
  return h.buffer.asUint8List();
}

/// File WAV completo in memoria.
Uint8List encodeWav(Float32List samples, int sampleRate) {
  final pcm = floatToPcm16(samples);
  final header = wavHeader(sampleRate: sampleRate, dataBytes: pcm.length);
  return (BytesBuilder(copy: false)
        ..add(header)
        ..add(pcm))
      .takeBytes();
}

/// Scrive un WAV un pezzo alla volta, senza tenere tutto in memoria.
/// Serve per salvare in un unico file la lettura di un testo lungo.
class WavFileWriter {
  WavFileWriter._(this._raf, this.sampleRate);

  final RandomAccessFile _raf;
  final int sampleRate;
  int _dataBytes = 0;

  static Future<WavFileWriter> open(String path, int sampleRate) async {
    final raf = await File(path).open(mode: FileMode.write);
    await raf.writeFrom(wavHeader(sampleRate: sampleRate, dataBytes: 0));
    return WavFileWriter._(raf, sampleRate);
  }

  int get dataBytes => _dataBytes;

  Duration get duration =>
      Duration(microseconds: (_dataBytes / 2 / sampleRate * 1e6).round());

  Future<void> addSamples(Float32List samples) async {
    final pcm = floatToPcm16(samples);
    await _raf.writeFrom(pcm);
    _dataBytes += pcm.length;
  }

  /// Aggiunge una breve pausa (silenzio) tra un paragrafo e l'altro.
  Future<void> addSilence(Duration d) async {
    final n = (sampleRate * d.inMicroseconds / 1e6).round();
    final bytes = Uint8List(n * 2);
    await _raf.writeFrom(bytes);
    _dataBytes += bytes.length;
  }

  Future<void> close() async {
    await _raf.setPosition(0);
    await _raf.writeFrom(wavHeader(sampleRate: sampleRate, dataBytes: _dataBytes));
    await _raf.close();
  }
}
