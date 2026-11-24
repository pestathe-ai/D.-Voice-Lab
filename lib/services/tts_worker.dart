import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class TtsException implements Exception {
  TtsException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SynthResult {
  SynthResult(this.samples, this.sampleRate);
  final Float32List samples;
  final int sampleRate;
}

/// Fa girare la sintesi vocale in un isolate separato, così l'interfaccia
/// resta fluida mentre la voce viene generata.
///
/// Le richieste vengono eseguite una alla volta, nell'ordine di arrivo.
class TtsWorker {
  Isolate? _isolate;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  Future<void>? _starting;
  final Map<int, Completer<Map<Object?, Object?>>> _pending = {};
  int _nextId = 0;

  String? _loadedModel;
  int sampleRate = 0;

  String? get loadedModel => _loadedModel;

  Future<void> _ensureStarted() {
    if (_toWorker != null) return Future.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    final rp = ReceivePort();
    _fromWorker = rp;
    final ready = Completer<SendPort>();
    rp.listen((dynamic msg) {
      if (msg is SendPort) {
        if (!ready.isCompleted) ready.complete(msg);
        return;
      }
      if (msg is Map) {
        final id = msg['id'];
        if (id is int) _pending.remove(id)?.complete(msg);
      }
    });
    _isolate = await Isolate.spawn(_workerMain, rp.sendPort, debugName: 'tts');
    _toWorker = await ready.future;
  }

  Future<Map<Object?, Object?>> _call(Map<String, Object?> msg) async {
    await _ensureStarted();
    final id = _nextId++;
    final completer = Completer<Map<Object?, Object?>>();
    _pending[id] = completer;
    _toWorker!.send(<String, Object?>{...msg, 'id': id});
    final res = await completer.future;
    if (res['ok'] != true) {
      throw TtsException((res['error'] as String?) ?? 'Errore sconosciuto');
    }
    return res;
  }

  /// Carica una voce Piper (VITS). Non fa nulla se è già quella caricata.
  Future<void> loadPiper({
    required String model,
    required String tokens,
    int threads = 2,
  }) =>
      _load(_piperSpec(model, tokens, threads));

  /// Carica il pacchetto Supertonic contenuto in [dir].
  Future<void> loadSupertonic({required String dir, int threads = 2}) =>
      _load(_supertonicSpec(dir, threads));

  static Map<String, Object?> _piperSpec(String model, String tokens, int threads) =>
      {'key': model, 'engine': 'piper', 'model': model, 'tokens': tokens, 'threads': threads};

  static Map<String, Object?> _supertonicSpec(String dir, int threads) =>
      {'key': dir, 'engine': 'supertonic', 'dir': dir, 'threads': threads};

  Future<void>? _loading;
  String? _loadingKey;

  Future<void> _load(Map<String, Object?> spec) async {
    final key = spec['key'] as String;
    if (_loadedModel == key) return;
    if (_loadingKey == key && _loading != null) return _loading;
    _loadingKey = key;
    final future = () async {
      final res = await _call({'cmd': 'load', 'spec': spec});
      sampleRate = res['sampleRate'] as int;
      _loadedModel = key;
    }();
    _loading = future;
    try {
      await future;
    } finally {
      if (_loadingKey == key) {
        _loading = null;
        _loadingKey = null;
      }
    }
  }

  /// Voce Piper: genera l'audio a partire dai fonemi (una lista per frase).
  /// Ogni richiesta porta con sé la voce da usare: se nel frattempo ne è
  /// stata caricata un'altra (ad esempio per una prova), viene ricaricata.
  Future<SynthResult> synthPhonemes(
    List<List<int>> codepoints, {
    required String model,
    required String tokens,
    int threads = 2,
    double speed = 1.0,
  }) =>
      _synth({
        'cmd': 'synth',
        'cp': codepoints,
        'speed': speed,
        'spec': _piperSpec(model, tokens, threads),
      });

  /// Voce Supertonic: genera l'audio direttamente dal testo.
  Future<SynthResult> synthText(
    String text, {
    required String dir,
    required int sid,
    required String lang,
    int threads = 2,
    double speed = 1.0,
    int steps = 6,
  }) =>
      _synth({
        'cmd': 'synth',
        'text': text,
        'sid': sid,
        'lang': lang,
        'steps': steps,
        'speed': speed,
        'spec': _supertonicSpec(dir, threads),
      });

  Future<SynthResult> _synth(Map<String, Object?> msg) async {
    final res = await _call(msg);
    final rate = res['sampleRate'] as int;
    final key = res['key'] as String?;
    if (key != null) {
      _loadedModel = key;
      sampleRate = rate;
    }
    final data = res['samples'] as TransferableTypedData;
    final samples = data.materialize().asFloat32List();
    return SynthResult(samples, rate);
  }

  void dispose() {
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.complete({'ok': false, 'error': 'Interrotto'});
      }
    }
    _pending.clear();
    _isolate?.kill(priority: Isolate.immediate);
    _fromWorker?.close();
    _isolate = null;
    _toWorker = null;
    _fromWorker = null;
    _starting = null;
    _loadedModel = null;
  }
}

// ---------------------------------------------------------------------------
// Codice che gira dentro l'isolate.

void _workerMain(SendPort toMain) {
  final rp = ReceivePort();
  toMain.send(rp.sendPort);

  sherpa.OfflineTts? tts;
  var bindingsReady = false;
  var isSupertonic = false;
  String? loadedKey;

  /// Carica la voce descritta da [spec] se non è già quella caricata.
  int ensureLoaded(Map<String, Object?> spec) {
    final key = spec['key'] as String;
    final current = tts;
    if (current != null && loadedKey == key) return current.sampleRate;
    tts?.free();
    tts = null;
    loadedKey = null;
    final threads = spec['threads'] as int;
    final sherpa.OfflineTtsModelConfig model;
    if (spec['engine'] == 'supertonic') {
      final dir = spec['dir'] as String;
      model = sherpa.OfflineTtsModelConfig(
        supertonic: sherpa.OfflineTtsSupertonicModelConfig(
          durationPredictor: '$dir/duration_predictor.int8.onnx',
          textEncoder: '$dir/text_encoder.int8.onnx',
          vectorEstimator: '$dir/vector_estimator.int8.onnx',
          vocoder: '$dir/vocoder.int8.onnx',
          ttsJson: '$dir/tts.json',
          unicodeIndexer: '$dir/unicode_indexer.bin',
          voiceStyle: '$dir/voice.bin',
        ),
        numThreads: threads,
        debug: false,
      );
    } else {
      model = sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: spec['model'] as String,
          tokens: spec['tokens'] as String,
        ),
        numThreads: threads,
        debug: false,
      );
    }
    final created = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(model: model, maxNumSentences: 1),
    );
    final rate = created.sampleRate;
    if (rate <= 0) {
      created.free();
      throw TtsException('Non riesco ad aprire questa voce. Prova a riscaricarla.');
    }
    tts = created;
    loadedKey = key;
    isSupertonic = spec['engine'] == 'supertonic';
    return rate;
  }

  rp.listen((dynamic raw) {
    final msg = raw as Map;
    final id = msg['id'] as int;
    try {
      if (!bindingsReady) {
        sherpa.initBindings();
        bindingsReady = true;
      }
      final cmd = msg['cmd'] as String;
      if (cmd == 'load') {
        final rate = ensureLoaded(Map<String, Object?>.from(msg['spec'] as Map));
        toMain.send(<String, Object?>{'id': id, 'ok': true, 'sampleRate': rate});
      } else if (cmd == 'synth') {
        final spec = msg['spec'];
        if (spec is Map) ensureLoaded(Map<String, Object?>.from(spec));
        final engine = tts;
        if (engine == null) {
          throw TtsException('Nessuna voce caricata');
        }
        Float32List samples = Float32List(0);
        var rate = engine.sampleRate;
        final speed = (msg['speed'] as num).toDouble();
        sherpa.GeneratedAudio? audio;
        if (isSupertonic) {
          final text = (msg['text'] as String?) ?? '';
          if (text.trim().isNotEmpty) {
            audio = engine.generateWithConfig(
              text: text,
              config: sherpa.OfflineTtsGenerationConfig(
                sid: msg['sid'] as int,
                speed: speed,
                extra: {
                  'lang': msg['lang'] as String,
                  'num_steps': msg['steps'] as int,
                },
              ),
            );
          }
        } else {
          final cp = <List<int>>[
            for (final s in (msg['cp'] as List?) ?? const [])
              if ((s as List).isNotEmpty) List<int>.from(s),
          ];
          if (cp.isNotEmpty) {
            audio = engine.generateWithConfig(
              text: '',
              config: sherpa.OfflineTtsGenerationConfig(
                speed: speed,
                silenceScale: 0.2,
                phonemeCodepoints: cp,
              ),
            );
          }
        }
        if (audio != null) {
          samples = audio.samples;
          if (audio.sampleRate > 0) rate = audio.sampleRate;
        }
        toMain.send(<String, Object?>{
          'id': id,
          'ok': true,
          'sampleRate': rate,
          'key': loadedKey,
          'samples': TransferableTypedData.fromList([samples]),
        });
      } else {
        throw TtsException('Comando sconosciuto: $cmd');
      }
    } catch (e) {
      toMain.send(<String, Object?>{'id': id, 'ok': false, 'error': e.toString()});
    }
  });
}
