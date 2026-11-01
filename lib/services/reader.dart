import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:piper_phonemize/piper_phonemize.dart' as piper;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/text_chunker.dart';
import '../core/voice_catalog.dart';
import '../core/wav.dart';
import 'tts_worker.dart';
import 'voice_store.dart';

enum ReaderState { idle, preparing, playing, paused }

/// Quante frasi preparare in anticipo mentre se ne ascolta una.
const int _kAhead = 2;

/// Legge il testo una frase alla volta: genera l'audio della frase
/// corrente e intanto prepara le successive.
class Reader extends ChangeNotifier {
  Reader(this.store);

  final VoiceStore store;
  final TtsWorker _worker = TtsWorker();
  final AudioPlayer _player = AudioPlayer();
  late Directory _tmp;
  late SharedPreferences _prefs;
  StreamSubscription<void>? _completeSub;
  Future<void>? _phonemizerInit;

  ReaderState state = ReaderState.idle;
  List<String> chunks = const [];
  int index = 0;
  String? error;

  String? _voiceId;
  double _speed = 1.0;
  String draft = '';

  int _session = 0;
  int _playToken = 0;
  final Map<int, Future<String?>> _cache = {};
  String? _pendingPath;
  bool _midChunk = false;

  bool exporting = false;
  double exportProgress = 0;
  bool _exportCancel = false;

  bool get active => state != ReaderState.idle;
  double get speed => _speed;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _voiceId = _prefs.getString('voice');
    _speed = _prefs.getDouble('speed') ?? 1.0;
    draft = _prefs.getString('draft') ?? '';
    final t = await getTemporaryDirectory();
    _tmp = Directory(p.join(t.path, 'dvoce_audio'));
    if (_tmp.existsSync()) {
      try {
        await _tmp.delete(recursive: true);
      } catch (_) {}
    }
    await _tmp.create(recursive: true);
    await _player.setReleaseMode(ReleaseMode.stop);
    _completeSub = _player.onPlayerComplete.listen((_) => _onComplete());
  }

  /// La voce scelta, se installata; altrimenti la prima installata.
  VoiceInfo? get voice {
    final chosen = voiceById(_voiceId);
    if (chosen != null && store.isInstalled(chosen)) return chosen;
    final installed = store.installed;
    return installed.isEmpty ? null : installed.first;
  }

  Future<void> selectVoice(VoiceInfo v) async {
    if (v.id == _voiceId) return;
    _voiceId = v.id;
    await _prefs.setString('voice', v.id);
    if (active) await stop();
    notifyListeners();
  }

  void setSpeed(double value) {
    _speed = value;
    _prefs.setDouble('speed', value);
    if (active) {
      // Le frasi già preparate hanno la velocità vecchia: si rifanno.
      _cache.removeWhere((i, _) => i > index);
      _prefetch(index, _session);
    }
    notifyListeners();
  }

  void saveDraft(String text) {
    draft = text;
    _prefs.setString('draft', text);
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Motore

  int get _threads =>
      math.max(1, math.min(4, Platform.numberOfProcessors ~/ 2));

  Future<void> _ensurePhonemizer() {
    return _phonemizerInit ??= () async {
      try {
        await piper.initBindingsAsync();
        final dir = await piper.extractEspeakNgData();
        final r = piper.PiperPhonemize.initialize(dir);
        if (r < 0) {
          throw TtsException('Non riesco a preparare la pronuncia italiana.');
        }
      } catch (e) {
        _phonemizerInit = null;
        rethrow;
      }
    }();
  }

  Future<void> _ensureEngine(VoiceInfo v) async {
    await _ensurePhonemizer();
    await _worker.load(
      model: store.modelPath(v),
      tokens: store.tokensPath(v),
      threads: _threads,
    );
  }

  List<List<int>> _phonemize(String text) => piper.PiperPhonemize.phonemize(
    text,
    voice: kEspeakVoice,
  ).where((s) => s.isNotEmpty).toList();

  // -------------------------------------------------------------------------
  // Lettura

  Future<void> start(String text, {int from = 0, VoiceInfo? withVoice}) async {
    await stop();
    final v = withVoice ?? voice;
    if (v == null) {
      error = 'Scarica prima una voce.';
      notifyListeners();
      return;
    }
    final list = splitIntoChunks(text);
    if (list.isEmpty) {
      error = 'Non c\'è niente da leggere.';
      notifyListeners();
      return;
    }
    chunks = list;
    index = from.clamp(0, list.length - 1).toInt();
    error = null;
    state = ReaderState.preparing;
    notifyListeners();

    final session = _session;
    try {
      await _ensureEngine(v);
    } catch (e) {
      if (session == _session) {
        _reset();
        error = 'Errore nel preparare la voce: $e';
        notifyListeners();
      }
      return;
    }
    if (session != _session) return;
    unawaited(_playIndex(index));
  }

  /// Fa sentire la frase di prova di una voce.
  Future<void> preview(VoiceInfo v) => start(v.sample, withVoice: v);

  Future<String?> _prepare(int i, int session) {
    return _cache.putIfAbsent(i, () async {
      final cp = _phonemize(chunks[i]);
      if (cp.isEmpty) return null;
      final res = await _worker.synth(cp, speed: _speed);
      if (res.samples.isEmpty || session != _session) return null;
      final path = p.join(_tmp.path, 's${session}_${i}_${_speed.toStringAsFixed(2)}.wav');
      await File(path).writeAsBytes(encodeWav(res.samples, res.sampleRate));
      return path;
    });
  }

  void _prefetch(int i, int session) {
    for (var j = i + 1; j <= i + _kAhead && j < chunks.length; j++) {
      _prepare(j, session).catchError((Object _) => null);
    }
  }

  Future<void> _playIndex(int i) async {
    final token = ++_playToken;
    final session = _session;
    if (i >= chunks.length) {
      await _finish();
      return;
    }
    index = i;
    _pendingPath = null;
    notifyListeners();

    String? path;
    try {
      path = await _prepare(i, session);
    } catch (e) {
      if (token == _playToken && session == _session) {
        _reset();
        error = 'Errore durante la lettura: $e';
        notifyListeners();
      }
      return;
    }
    if (token != _playToken || session != _session) return;
    _prefetch(i, session);

    if (path == null) {
      // Frase senza suoni da leggere (es. solo simboli): si passa oltre.
      unawaited(_playIndex(i + 1));
      return;
    }
    if (state == ReaderState.paused) {
      _pendingPath = path;
      return;
    }
    _midChunk = true;
    state = ReaderState.playing;
    notifyListeners();
    await _player.play(DeviceFileSource(path));
  }

  void _onComplete() {
    if (state != ReaderState.playing) return;
    _midChunk = false;
    final done = index;
    final old = _cache.remove(done);
    old?.then((path) {
      if (path != null) File(path).delete().catchError((Object _) => File(path));
    }).catchError((Object _) {});
    unawaited(_playIndex(done + 1));
  }

  Future<void> pause() async {
    if (state == ReaderState.playing) {
      await _player.pause();
    }
    if (active) {
      state = ReaderState.paused;
      notifyListeners();
    }
  }

  Future<void> resume() async {
    if (state != ReaderState.paused) return;
    final pending = _pendingPath;
    if (pending != null) {
      _pendingPath = null;
      _midChunk = true;
      state = ReaderState.playing;
      notifyListeners();
      await _player.play(DeviceFileSource(pending));
    } else if (_midChunk) {
      state = ReaderState.playing;
      notifyListeners();
      await _player.resume();
    } else {
      // La frase è ancora in preparazione: partirà appena pronta.
      state = ReaderState.preparing;
      notifyListeners();
    }
  }

  Future<void> togglePause() =>
      state == ReaderState.paused ? resume() : pause();

  /// Salta a una frase (avanti, indietro o dal cursore).
  Future<void> seek(int target) async {
    if (!active || chunks.isEmpty) return;
    final int t = target.clamp(0, chunks.length - 1).toInt();
    final wasPaused = state == ReaderState.paused;
    _playToken++;
    _midChunk = false;
    _pendingPath = null;
    await _player.stop();
    if (!wasPaused) state = ReaderState.preparing;
    unawaited(_playIndex(t));
  }

  Future<void> next() => seek(index + 1);
  Future<void> previous() => seek(index - 1);

  Future<void> stop() async {
    _reset();
    await _player.stop();
    notifyListeners();
    _cleanTmp();
  }

  Future<void> _finish() async {
    _reset();
    notifyListeners();
    _cleanTmp();
  }

  void _reset() {
    _session++;
    _playToken++;
    state = ReaderState.idle;
    chunks = const [];
    index = 0;
    _cache.clear();
    _pendingPath = null;
    _midChunk = false;
  }

  void _cleanTmp() {
    final session = _session;
    // Si cancellano solo i file delle letture precedenti.
    _tmp.list().listen((f) {
      final name = p.basename(f.path);
      final m = RegExp(r'^s(\d+)_').firstMatch(name);
      if (m != null && int.parse(m.group(1)!) < session) {
        f.delete().catchError((Object _) => f);
      }
    }, onError: (Object _) {});
  }

  // -------------------------------------------------------------------------
  // Salvataggio in un file audio

  /// Crea un unico file WAV con la lettura di tutto il testo.
  /// Restituisce il percorso, oppure null se annullato.
  Future<String?> exportAudio(String text) async {
    await stop();
    final v = voice;
    if (v == null) throw TtsException('Scarica prima una voce.');
    final list = splitIntoChunks(text);
    if (list.isEmpty) throw TtsException('Non c\'è niente da leggere.');

    exporting = true;
    exportProgress = 0;
    _exportCancel = false;
    notifyListeners();

    WavFileWriter? writer;
    String? path;
    try {
      await _ensureEngine(v);
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'audio'));
      await dir.create(recursive: true);
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp =
          '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
      path = p.join(dir.path, 'D-Voce_$stamp.wav');

      for (var i = 0; i < list.length; i++) {
        if (_exportCancel) break;
        final cp = _phonemize(list[i]);
        if (cp.isNotEmpty) {
          final res = await _worker.synth(cp, speed: _speed);
          if (res.samples.isNotEmpty) {
            writer ??= await WavFileWriter.open(path, res.sampleRate);
            await writer.addSamples(res.samples);
            await writer.addSilence(const Duration(milliseconds: 250));
          }
        }
        exportProgress = (i + 1) / list.length;
        notifyListeners();
      }
      await writer?.close();
      writer = null;

      final file = File(path);
      if (_exportCancel || !file.existsSync()) {
        if (file.existsSync()) await file.delete();
        return null;
      }
      return path;
    } catch (_) {
      await writer?.close();
      if (path != null) {
        final f = File(path);
        if (f.existsSync()) await f.delete();
      }
      rethrow;
    } finally {
      exporting = false;
      notifyListeners();
    }
  }

  void cancelExport() {
    _exportCancel = true;
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _player.dispose();
    _worker.dispose();
    super.dispose();
  }
}
