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

  /// Carica una voce (non fa nulla se è già quella caricata).
  Future<void> load({
    required String model,
    required String tokens,
    int threads = 2,
  }) async {
    if (_loadedModel == model) return;
    _loadedModel = null;
    final res = await _call({
      'cmd': 'load',
      'model': model,
      'tokens': tokens,
      'threads': threads,
    });
    sampleRate = res['sampleRate'] as int;
    _loadedModel = model;
  }

  /// Genera l'audio a partire dai fonemi (una lista per frase).
  Future<SynthResult> synth(
    List<List<int>> codepoints, {
    double speed = 1.0,
  }) async {
    final res = await _call({'cmd': 'synth', 'cp': codepoints, 'speed': speed});
    final data = res['samples'] as TransferableTypedData;
    final samples = data.materialize().asFloat32List();
    return SynthResult(samples, res['sampleRate'] as int);
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
        tts?.free();
        tts = null;
        final created = sherpa.OfflineTts(
          sherpa.OfflineTtsConfig(
            model: sherpa.OfflineTtsModelConfig(
              vits: sherpa.OfflineTtsVitsModelConfig(
                model: msg['model'] as String,
                tokens: msg['tokens'] as String,
              ),
              numThreads: msg['threads'] as int,
              debug: false,
            ),
            maxNumSentences: 1,
          ),
        );
        final rate = created.sampleRate;
        if (rate <= 0) {
          created.free();
          throw TtsException('Non riesco ad aprire questa voce. Prova a riscaricarla.');
        }
        tts = created;
        toMain.send(<String, Object?>{'id': id, 'ok': true, 'sampleRate': rate});
      } else if (cmd == 'synth') {
        final engine = tts;
        if (engine == null) {
          throw TtsException('Nessuna voce caricata');
        }
        final cp = <List<int>>[
          for (final s in msg['cp'] as List)
            if ((s as List).isNotEmpty) List<int>.from(s),
        ];
        Float32List samples = Float32List(0);
        var rate = engine.sampleRate;
        if (cp.isNotEmpty) {
          final audio = engine.generateWithConfig(
            text: '',
            config: sherpa.OfflineTtsGenerationConfig(
              speed: (msg['speed'] as num).toDouble(),
              silenceScale: 0.2,
              phonemeCodepoints: cp,
            ),
          );
          samples = audio.samples;
          if (audio.sampleRate > 0) rate = audio.sampleRate;
        }
        toMain.send(<String, Object?>{
          'id': id,
          'ok': true,
          'sampleRate': rate,
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
