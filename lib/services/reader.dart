import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:piper_phonemize/piper_phonemize.dart' as piper;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/book.dart';
import '../core/italian_normalizer.dart';
import '../core/text_chunker.dart';
import '../core/voice_catalog.dart';
import '../core/wav.dart';
import 'library.dart';
import 'system_tts.dart';
import 'tts_worker.dart';
import 'voice_store.dart';

enum ReaderState { idle, preparing, playing, paused }

/// Una voce che si può scegliere: del telefono (Google, Samsung…) oppure
/// una delle voci scaricabili che girano dentro l'app.
class VoiceChoice {
  const VoiceChoice._({
    required this.id,
    required this.name,
    required this.description,
    this.system,
    this.offline,
  });

  factory VoiceChoice.system(SystemVoice v) => VoiceChoice._(
        id: v.id,
        name: v.label,
        description: v.description,
        system: v,
      );

  factory VoiceChoice.offline(VoiceInfo v) => VoiceChoice._(
        id: v.id,
        name: v.name,
        description: v.description,
        offline: v,
      );

  final String id;
  final String name;
  final String description;
  final SystemVoice? system;
  final VoiceInfo? offline;

  bool get isSystem => system != null;
}

/// Quante frasi preparare in anticipo mentre se ne ascolta una.
const int _kAhead = 3;

/// Le voci naturali parlano un filo lente: a velocità "1×" si accelerano
/// appena per avere il ritmo di un audiolibro.
const double _kSupertonicBaseSpeed = 1.05;

/// Qualità delle voci naturali: più passi = voce più pulita ma più lenta
/// da preparare.
enum VoiceQuality { normal, high }

/// Il lettore: legge un libro una frase alla volta, genera in anticipo le
/// frasi successive, passa da un capitolo all'altro e ricorda il punto.
class Reader extends ChangeNotifier {
  Reader(this.store, this.library);

  final VoiceStore store;
  final Library library;
  final TtsWorker _worker = TtsWorker();
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _previewPlayer = AudioPlayer();
  final SystemTts _sys = SystemTts();
  late Directory _tmp;
  late SharedPreferences _prefs;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<void>? _previewSub;
  Future<void>? _phonemizerInit;

  ReaderState state = ReaderState.idle;
  String? error;

  // Libro aperto
  BookMeta? book;
  List<Chapter> chapters = const [];
  int chapterIndex = 0;
  List<String> chunks = const [];
  int index = 0;
  bool loadingBook = false;

  // Impostazioni
  String? _voiceId;
  double _speed = 1.0;
  VoiceQuality quality = VoiceQuality.normal;

  // Timer di spegnimento
  DateTime? sleepAt;
  bool sleepAtChapterEnd = false;
  Timer? _sleepTimer;

  // Prova voce
  String? previewingVoiceId;
  bool _sysPreview = false;

  // Voci del telefono
  List<SystemVoice> systemVoices = const [];
  String _systemVoicesLang = '';
  bool systemVoicesLoaded = false;

  /// true mentre si legge con una voce del telefono.
  bool _sysMode = false;
  int _sysQueuedUntil = -1;

  int _session = 0;
  int _playToken = 0;
  final Map<int, Future<String?>> _cache = {};
  String? _pendingPath;
  bool _midChunk = false;

  bool get active => state != ReaderState.idle;
  bool get playing => state == ReaderState.playing || state == ReaderState.preparing;
  double get speed => _speed;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _voiceId = _prefs.getString('voice');
    _speed = _prefs.getDouble('speed') ?? 1.0;
    quality = (_prefs.getString('quality') == 'high') ? VoiceQuality.high : VoiceQuality.normal;
    final t = await getTemporaryDirectory();
    _tmp = Directory(p.join(t.path, 'dvoce_audio'));
    if (_tmp.existsSync()) {
      try {
        await _tmp.delete(recursive: true);
      } catch (_) {}
    }
    await _tmp.create(recursive: true);
    await _player.setReleaseMode(ReleaseMode.stop);
    await _previewPlayer.setReleaseMode(ReleaseMode.stop);
    _completeSub = _player.onPlayerComplete.listen((_) => _onComplete());
    _previewSub = _previewPlayer.onPlayerComplete.listen((_) {
      previewingVoiceId = null;
      notifyListeners();
    });
    _sys.onUtteranceDone = _onSysDone;
    _sys.onError = _onSysError;
    try {
      await _sys.init();
      final engine = _prefs.getString('engine');
      if (engine != null && _sys.engines.any((e) => e['name'] == engine)) {
        await _sys.setEngine(engine);
      }
    } catch (_) {}
    await refreshSystemVoices();
  }

  /// Rilegge le voci del telefono per la lingua del libro aperto.
  Future<void> refreshSystemVoices({bool force = false}) async {
    final lang = _lang;
    if (!force && systemVoicesLoaded && _systemVoicesLang == lang) return;
    try {
      systemVoices = await _sys.voices(lang);
    } catch (_) {
      systemVoices = const [];
    }
    _systemVoicesLang = lang;
    systemVoicesLoaded = true;
    notifyListeners();
  }

  List<Map<String, String>> get engines => _sys.engines;
  String? get engine => _sys.engine;

  Future<void> setEngine(String name) async {
    final wasPlaying = playing;
    if (active) await pause();
    await _sys.setEngine(name);
    await _prefs.setString('engine', name);
    await refreshSystemVoices(force: true);
    if (wasPlaying) await play();
  }

  // -------------------------------------------------------------------------
  // Voci e impostazioni

  /// Tutte le voci che si possono usare adesso: prima quelle del telefono,
  /// poi quelle scaricate nell'app.
  List<VoiceChoice> get availableVoices => [
        for (final v in systemVoices)
          if (v.installed) VoiceChoice.system(v),
        for (final v in store.installed) VoiceChoice.offline(v),
      ];

  VoiceChoice? _resolve(String? id) {
    if (id == null) return null;
    if (id.startsWith('sys:')) {
      for (final v in systemVoices) {
        if (v.id == id && v.installed) return VoiceChoice.system(v);
      }
      return null;
    }
    final v = voiceById(id);
    if (v != null && store.isInstalled(v)) return VoiceChoice.offline(v);
    return null;
  }

  /// La voce con cui si legge il libro aperto (o la voce generale).
  VoiceChoice? get voice {
    final own = _resolve(book?.voiceId);
    if (own != null) return own;
    final general = _resolve(_voiceId);
    if (general != null) return general;
    final all = availableVoices;
    return all.isEmpty ? null : all.first;
  }

  /// Sceglie la voce per il libro aperto e la rende anche quella generale.
  Future<void> selectVoice(VoiceChoice v) async {
    final b = book;
    if (b != null) {
      b.voiceId = v.id;
      unawaited(library.update(b, notify: false));
    }
    _voiceId = v.id;
    await _prefs.setString('voice', v.id);
    await _restartWithNewSettings();
    notifyListeners();
  }

  /// Dopo un cambio di voce o velocità la lettura riprende dalla frase
  /// corrente con le impostazioni nuove.
  Future<void> _restartWithNewSettings() async {
    if (!active) return;
    final needsSys = voice?.isSystem == true;
    if (!_sysMode && !needsSys) {
      _invalidateAhead();
      return;
    }
    final wasPaused = state == ReaderState.paused;
    if (_sysMode) {
      await _sys.stop();
    } else {
      _playToken++;
      await _player.stop();
    }
    _resetPlayback();
    if (wasPaused) {
      state = ReaderState.paused;
      _restartOnResume = true;
      notifyListeners();
    } else {
      await play();
    }
  }

  bool _restartOnResume = false;

  void setSpeed(double value) {
    _speed = value;
    _prefs.setDouble('speed', value);
    if (_sysMode && active) {
      unawaited(_restartWithNewSettings());
    } else if (active) {
      _invalidateAhead();
    }
    notifyListeners();
  }

  void setQuality(VoiceQuality q) {
    quality = q;
    _prefs.setString('quality', q == VoiceQuality.high ? 'high' : 'normal');
    if (active) _invalidateAhead();
    notifyListeners();
  }

  /// Le frasi già preparate con le impostazioni vecchie si rifanno.
  void _invalidateAhead() {
    _cache.removeWhere((i, _) => i > index);
    _prefetch(index, _session);
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Motore

  int get _threads => math.max(1, math.min(4, Platform.numberOfProcessors ~/ 2));

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
    if (v.engine == VoiceEngine.supertonic) {
      await _worker.loadSupertonic(dir: store.packDir(v.pack), threads: _threads);
    } else {
      await _ensurePhonemizer();
      await _worker.loadPiper(
        model: store.modelPath(v),
        tokens: store.tokensPath(v),
        threads: _threads,
      );
    }
  }

  String get _lang => book?.lang ?? 'it';

  Future<SynthResult> _synth(VoiceInfo v, String text, String lang) async {
    final spoken = lang == 'it' ? normalizeItalian(text) : text;
    if (v.engine == VoiceEngine.supertonic) {
      return _worker.synthText(
        spoken,
        dir: store.packDir(v.pack),
        threads: _threads,
        sid: v.sid,
        lang: lang,
        speed: _speed * _kSupertonicBaseSpeed,
        steps: quality == VoiceQuality.high ? 8 : 5,
      );
    }
    await _ensurePhonemizer();
    final cp = piper.PiperPhonemize.phonemize(spoken, voice: kEspeakVoice)
        .where((s) => s.isNotEmpty)
        .toList();
    if (cp.isEmpty) return SynthResult(Float32List(0), 0);
    return _worker.synthPhonemes(
      cp,
      model: store.modelPath(v),
      tokens: store.tokensPath(v),
      threads: _threads,
      speed: _speed,
    );
  }

  // -------------------------------------------------------------------------
  // Libro

  /// Apre un libro e si posiziona dove eri arrivato (senza partire).
  Future<void> openBook(BookMeta meta) async {
    if (book?.id == meta.id && chapters.isNotEmpty) return;
    await stop();
    loadingBook = true;
    book = meta;
    chapters = const [];
    chunks = const [];
    notifyListeners();
    try {
      chapters = await library.loadChapters(meta.id);
    } catch (e) {
      error = 'Non riesco ad aprire il libro: $e';
      book = null;
      loadingBook = false;
      notifyListeners();
      return;
    }
    loadingBook = false;
    if (chapters.isEmpty) {
      error = 'Il libro è vuoto.';
      book = null;
      notifyListeners();
      return;
    }
    // Dopo una lunga pausa si riparte una frase prima, per riprendere il filo.
    final last = meta.lastOpened;
    final longPause = last != null && DateTime.now().difference(last) > const Duration(minutes: 10);
    final startChunk = longPause && meta.chunk > 0 ? meta.chunk - 1 : meta.chunk;
    _loadChapter(meta.chapter.clamp(0, chapters.length - 1).toInt(), chunk: startChunk);
    unawaited(refreshSystemVoices());
    meta.lastOpened = DateTime.now();
    unawaited(library.update(meta));
    notifyListeners();
  }

  /// Chiude il libro (ad esempio se viene eliminato).
  Future<void> closeBook() async {
    await stop();
    book = null;
    chapters = const [];
    chunks = const [];
    index = 0;
    notifyListeners();
  }

  void _loadChapter(int i, {int chunk = 0}) {
    chapterIndex = i;
    chunks = splitIntoChunks(chapters[i].text);
    if (chunks.isEmpty) chunks = [chapters[i].title.isEmpty ? ' ' : chapters[i].title];
    index = chunk.clamp(0, chunks.length - 1).toInt();
  }

  /// Avanzamento complessivo del libro, da 0 a 1.
  double get bookProgress {
    if (chapters.isEmpty) return 0;
    var before = 0;
    var total = 0;
    for (var i = 0; i < chapters.length; i++) {
      final len = chapters[i].text.length;
      if (i < chapterIndex) before += len;
      total += len;
    }
    if (total == 0) return 0;
    final inChapter = chunks.isEmpty ? 0.0 : index / chunks.length;
    return (before + inChapter * chapters[chapterIndex].text.length) / total;
  }

  /// Tempo già ascoltato nel capitolo (stima).
  Duration get chapterElapsed {
    var chars = 0;
    for (var i = 0; i < index && i < chunks.length; i++) {
      chars += chunks[i].length;
    }
    return Duration(seconds: (chars / 14 / _speed).round());
  }

  /// Tempo di ascolto rimasto nel capitolo (stima).
  Duration get chapterRemaining {
    var chars = 0;
    for (var i = index; i < chunks.length; i++) {
      chars += chunks[i].length;
    }
    return Duration(seconds: (chars / 14 / _speed).round());
  }

  void _savePosition() {
    final b = book;
    if (b == null) return;
    b.chapter = chapterIndex;
    b.chunk = index;
    b.progress = bookProgress;
    b.lastOpened = DateTime.now();
    unawaited(library.update(b, notify: false));
  }

  // -------------------------------------------------------------------------
  // Lettura

  /// Parte (o riprende) dal punto corrente.
  Future<void> play() async {
    await stopPreview();
    if (state == ReaderState.paused) return resume();
    if (active) return;
    if (book == null || chunks.isEmpty) return;
    final choice = voice;
    if (choice == null) {
      error = 'Nessuna voce disponibile: scegline una in "Voci".';
      notifyListeners();
      return;
    }
    error = null;
    final sysVoice = choice.system;
    if (sysVoice != null) {
      await _sysPlay(sysVoice);
      return;
    }
    final v = choice.offline!;
    state = ReaderState.preparing;
    notifyListeners();
    final session = _session;
    try {
      await _ensureEngine(v);
    } catch (e) {
      if (session == _session) {
        _resetPlayback();
        error = 'Errore nel preparare la voce: $e';
        notifyListeners();
      }
      return;
    }
    if (session != _session) return;
    unawaited(_playIndex(index));
  }

  Future<void> togglePlay() async {
    if (state == ReaderState.playing || state == ReaderState.preparing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<String?> _prepare(int i, int session) {
    return _cache.putIfAbsent(i, () async {
      final v = voice?.offline;
      if (v == null) throw TtsException('Nessuna voce installata');
      final res = await _synth(v, chunks[i], _lang);
      if (res.samples.isEmpty || session != _session) return null;
      final path = p.join(_tmp.path, 's${session}_${chapterIndex}_${i}_${DateTime.now().microsecondsSinceEpoch}.wav');
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
      await _chapterFinished();
      return;
    }
    index = i;
    _pendingPath = null;
    _savePosition();
    notifyListeners();

    String? path;
    try {
      path = await _prepare(i, session);
    } catch (e) {
      if (token == _playToken && session == _session) {
        _resetPlayback();
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

  Future<void> _chapterFinished() async {
    final last = chapterIndex + 1 >= chapters.length;
    if (last) {
      // Libro finito: ci si ferma sull'ultima frase.
      index = chunks.length - 1;
      final b = book;
      if (b != null) {
        b.progress = 1;
        unawaited(library.update(b, notify: false));
      }
      _resetPlayback();
      notifyListeners();
      return;
    }
    final stopHere = sleepAtChapterEnd;
    _switchChapter(chapterIndex + 1);
    if (stopHere) {
      cancelSleepTimer();
      _resetPlayback();
      _savePosition();
      notifyListeners();
      return;
    }
    if (_sysMode) {
      await _sysStart(0);
    } else {
      unawaited(_playIndex(0));
    }
  }

  void _switchChapter(int i, {int chunk = 0}) {
    _session++;
    _playToken++;
    _cache.clear();
    _pendingPath = null;
    _midChunk = false;
    _loadChapter(i, chunk: chunk);
    _cleanTmp();
  }

  Future<void> pause() async {
    if (_sysMode) {
      await _sys.stop();
    } else if (state == ReaderState.playing) {
      await _player.pause();
    }
    if (active) {
      state = ReaderState.paused;
      _savePosition();
      notifyListeners();
    }
  }

  Future<void> resume() async {
    if (state != ReaderState.paused) return;
    await stopPreview();
    if (_restartOnResume) {
      _restartOnResume = false;
      state = ReaderState.idle;
      return play();
    }
    final sysVoice = voice?.system;
    if (_sysMode && sysVoice != null) {
      await _sysPlay(sysVoice);
      return;
    }
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

  /// Salta a una frase del capitolo corrente.
  Future<void> seek(int target) async {
    if (chunks.isEmpty) return;
    final int t = target.clamp(0, chunks.length - 1).toInt();
    if (!active) {
      index = t;
      _savePosition();
      notifyListeners();
      return;
    }
    final wasPaused = state == ReaderState.paused;
    if (_sysMode) {
      await _sys.stop();
      if (wasPaused) {
        index = t;
        _savePosition();
        notifyListeners();
      } else {
        await _sysStart(t);
      }
      return;
    }
    _playToken++;
    _midChunk = false;
    _pendingPath = null;
    await _player.stop();
    if (!wasPaused) state = ReaderState.preparing;
    unawaited(_playIndex(t));
  }

  /// Salta avanti o indietro di circa [d] (es. 30 secondi), stimando la
  /// durata delle frasi dalla loro lunghezza.
  Future<void> skipBy(Duration d) async {
    if (chunks.isEmpty) return;
    final forward = !d.isNegative;
    var chars = (d.inMilliseconds.abs() / 1000 * 14 * _speed).round();
    var t = index;
    if (forward) {
      while (chars > 0 && t + 1 < chunks.length) {
        chars -= chunks[t].length;
        t++;
      }
    } else {
      while (chars > 0 && t > 0) {
        t--;
        chars -= chunks[t].length;
      }
    }
    if (t != index) await seek(t);
  }

  Future<void> next() => seek(index + 1);
  Future<void> previous() => seek(index - 1);

  /// Va a un capitolo; se stava leggendo, continua da lì.
  Future<void> goToChapter(int i, {int chunk = 0}) async {
    if (chapters.isEmpty) return;
    final int target = i.clamp(0, chapters.length - 1).toInt();
    final wasActive = active;
    final wasPaused = state == ReaderState.paused;
    if (_sysMode) {
      await _sys.stop();
      _switchChapter(target, chunk: chunk);
      _savePosition();
      if (wasActive && !wasPaused) {
        await _sysStart(index);
      } else {
        notifyListeners();
      }
      return;
    }
    await _player.stop();
    _switchChapter(target, chunk: chunk);
    _savePosition();
    if (wasActive && !wasPaused) {
      state = ReaderState.preparing;
      notifyListeners();
      unawaited(_playIndex(index));
    } else if (wasActive) {
      state = ReaderState.paused;
      notifyListeners();
      unawaited(_playIndex(index));
    } else {
      notifyListeners();
    }
  }

  Future<void> nextChapter() => goToChapter(chapterIndex + 1);

  /// Se si è già a metà capitolo torna al suo inizio, altrimenti al precedente.
  Future<void> previousChapter() =>
      goToChapter(index > 2 ? chapterIndex : chapterIndex - 1);

  Future<void> stop() async {
    await stopPreview();
    _savePosition();
    final wasSys = _sysMode;
    _resetPlayback();
    if (wasSys) await _sys.stop();
    await _player.stop();
    notifyListeners();
    _cleanTmp();
  }

  void _resetPlayback() {
    _session++;
    _playToken++;
    state = ReaderState.idle;
    _cache.clear();
    _pendingPath = null;
    _midChunk = false;
    _sysMode = false;
    _restartOnResume = false;
  }

  // -------------------------------------------------------------------------
  // Lettura con le voci del telefono

  String _spoken(String text) => _lang == 'it' ? normalizeItalian(text) : text;

  Future<void> _sysPlay(SystemVoice v) async {
    _sysMode = true;
    state = ReaderState.preparing;
    notifyListeners();
    try {
      await _sys.configure(v, _speed);
    } catch (e) {
      _resetPlayback();
      error = 'Non riesco a usare questa voce del telefono: $e';
      notifyListeners();
      return;
    }
    await _sysStart(index);
  }

  /// Parte dalla frase [i] e mette in coda anche le due successive.
  Future<void> _sysStart(int i) async {
    if (i >= chunks.length) {
      await _chapterFinished();
      return;
    }
    _sysMode = true;
    index = i;
    _sysQueuedUntil = i - 1;
    state = ReaderState.playing;
    _savePosition();
    notifyListeners();
    await _sysFill();
  }

  Future<void> _sysFill() async {
    while (_sysQueuedUntil < index + 2 && _sysQueuedUntil + 1 < chunks.length) {
      _sysQueuedUntil++;
      await _sys.enqueue(_spoken(chunks[_sysQueuedUntil]));
    }
  }

  void _onSysDone() {
    if (_sysPreview) {
      _sysPreview = false;
      previewingVoiceId = null;
      notifyListeners();
      return;
    }
    if (!_sysMode || state != ReaderState.playing) return;
    index++;
    if (index >= chunks.length) {
      index = chunks.length - 1;
      unawaited(_chapterFinished());
      return;
    }
    _savePosition();
    notifyListeners();
    unawaited(_sysFill());
  }

  void _onSysError(String message) {
    if (_sysPreview) {
      _sysPreview = false;
      previewingVoiceId = null;
      error = 'Questa voce non funziona adesso. Se è una voce che usa internet, '
          'controlla la connessione.';
      notifyListeners();
      return;
    }
    if (!_sysMode || state != ReaderState.playing) return;
    unawaited(pause());
    error = 'La voce si è interrotta. Se usa internet controlla la connessione, '
        'oppure scegli una voce che funziona senza internet.';
    notifyListeners();
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
  // Timer di spegnimento

  void setSleepTimer(Duration d) {
    _sleepTimer?.cancel();
    sleepAtChapterEnd = false;
    sleepAt = DateTime.now().add(d);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final at = sleepAt;
      if (at == null) return;
      if (DateTime.now().isAfter(at)) {
        cancelSleepTimer();
        unawaited(pause());
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void setSleepAtChapterEnd() {
    _sleepTimer?.cancel();
    sleepAt = null;
    sleepAtChapterEnd = true;
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepAt = null;
    sleepAtChapterEnd = false;
    notifyListeners();
  }

  bool get sleepTimerOn => sleepAt != null || sleepAtChapterEnd;

  Duration? get sleepRemaining {
    final at = sleepAt;
    if (at == null) return null;
    final d = at.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  // -------------------------------------------------------------------------
  // Prova delle voci

  Future<void> preview(VoiceChoice c) async {
    if (playing) await pause();
    await stopPreview();
    previewingVoiceId = c.id;
    notifyListeners();
    final sys = c.system;
    if (sys != null) {
      try {
        _sysPreview = true;
        await _sys.configure(sys, _speed);
        await _sys.enqueue(_sampleFor(sys.locale));
      } catch (e) {
        _sysPreview = false;
        previewingVoiceId = null;
        error = 'Non riesco a far parlare questa voce: $e';
        notifyListeners();
      }
      return;
    }
    final v = c.offline!;
    try {
      final res = await _synth(v, v.sample, 'it');
      if (previewingVoiceId != v.id) return;
      final path = p.join(_tmp.path, 'preview_${v.id}_${DateTime.now().microsecondsSinceEpoch}.wav');
      await File(path).writeAsBytes(encodeWav(res.samples, res.sampleRate));
      if (previewingVoiceId != v.id) return;
      await _previewPlayer.play(DeviceFileSource(path));
    } catch (e) {
      previewingVoiceId = null;
      error = 'Non riesco a far parlare ${v.name}: $e';
      notifyListeners();
    }
  }

  static String _sampleFor(String locale) {
    final l = locale.toLowerCase();
    if (l.startsWith('en')) return 'Hello! This is the voice that will read your books, chapter after chapter.';
    if (l.startsWith('es')) return '¡Hola! Esta es la voz que leerá tus libros, capítulo tras capítulo.';
    if (l.startsWith('fr')) return 'Bonjour ! Voici la voix qui lira tes livres, chapitre après chapitre.';
    if (l.startsWith('de')) return 'Hallo! Das ist die Stimme, die dir deine Bücher vorliest, Kapitel für Kapitel.';
    return 'Ciao! Sono la voce che leggerà i tuoi libri, capitolo dopo capitolo. '
        'Era una mattina fredda di novembre, e il mare era grigio e immobile.';
  }

  Future<void> stopPreview() async {
    if (previewingVoiceId == null) return;
    previewingVoiceId = null;
    if (_sysPreview) {
      _sysPreview = false;
      await _sys.stop();
    }
    await _previewPlayer.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _completeSub?.cancel();
    _previewSub?.cancel();
    _player.dispose();
    _previewPlayer.dispose();
    _worker.dispose();
    super.dispose();
  }
}
