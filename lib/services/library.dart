import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/book.dart';

/// La libreria: i libri importati, salvati sul telefono con il punto in cui
/// eri arrivato.
class Library extends ChangeNotifier {
  late Directory _root;
  final List<BookMeta> _books = [];
  bool _ready = false;

  bool get ready => _ready;

  /// I libri, dal più recente.
  List<BookMeta> get books {
    final list = [..._books];
    list.sort((a, b) => (b.lastOpened ?? b.addedAt).compareTo(a.lastOpened ?? a.addedAt));
    return list;
  }

  File get _index => File(p.join(_root.path, 'index.json'));
  File _bookFile(String id) => File(p.join(_root.path, '$id.json'));

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _root = Directory(p.join(docs.path, 'books'));
    await _root.create(recursive: true);
    if (_index.existsSync()) {
      try {
        final list = jsonDecode(await _index.readAsString()) as List;
        for (final j in list) {
          final meta = BookMeta.fromJson(Map<String, Object?>.from(j as Map));
          if (_bookFile(meta.id).existsSync()) _books.add(meta);
        }
      } catch (_) {
        // Indice rovinato: si ricomincia (i file dei libri restano).
      }
    }
    _ready = true;
    notifyListeners();
  }

  BookMeta? byId(String id) {
    for (final b in _books) {
      if (b.id == id) return b;
    }
    return null;
  }

  Future<void> _saving = Future.value();

  /// Le scritture dell'indice si mettono in fila, così non si sovrappongono.
  Future<void> _saveIndex() {
    final data = jsonEncode([for (final b in _books) b.toJson()]);
    final path = _index.path;
    _saving = _saving.catchError((Object _) {}).then((_) async {
      final tmp = File('$path.tmp');
      await tmp.writeAsString(data, flush: true);
      await tmp.rename(path);
    });
    return _saving;
  }

  String _newId() {
    final r = math.Random();
    return '${DateTime.now().millisecondsSinceEpoch}_${r.nextInt(1 << 30)}';
  }

  Future<BookMeta> add(ImportedBook book, {required String lang}) async {
    final id = _newId();
    final chapters = [for (final c in book.chapters) c.toJson()];
    final path = _bookFile(id).path;
    await _writeJson(path, chapters);
    final meta = BookMeta(
      id: id,
      title: book.title,
      author: book.author,
      format: book.format,
      lang: lang,
      addedAt: DateTime.now(),
      chapterCount: book.chapters.length,
      totalChars: book.totalChars,
    );
    final cover = book.coverBytes;
    if (cover != null) {
      if (book.format == 'pdf') {
        // La prima pagina del PDF resta disponibile come copertina di riserva.
        await File(firstPagePath(id)).writeAsBytes(cover);
      }
      await _writeCover(meta, cover);
    }
    _books.add(meta);
    await _saveIndex();
    notifyListeners();
    return meta;
  }

  // ---------------------------------------------------------------------
  // Copertine

  /// Percorso della copertina (null se il libro non ne ha). Il nome cambia
  /// a ogni nuova copertina, così l'immagine si aggiorna subito.
  String? coverPath(BookMeta b) =>
      b.coverVersion == 0 ? null : p.join(_root.path, '${b.id}_cover_${b.coverVersion}.img');

  /// La prima pagina di un PDF salvata durante l'importazione, se c'è.
  String firstPagePath(String id) => p.join(_root.path, '${id}_p1.png');

  Future<void> _writeCover(BookMeta b, Uint8List bytes) async {
    final old = coverPath(b);
    b.coverVersion++;
    await File(coverPath(b)!).writeAsBytes(bytes, flush: true);
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
  }

  Future<void> setCover(BookMeta b, Uint8List bytes) async {
    await _writeCover(b, bytes);
    await _saveIndex();
    notifyListeners();
  }

  Future<void> removeCover(BookMeta b) async {
    final old = coverPath(b);
    b.coverVersion = 0;
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    await _saveIndex();
    notifyListeners();
  }

  /// Carica i capitoli di un libro (in un isolate: i libri sono grandi).
  Future<List<Chapter>> loadChapters(String id) async {
    final path = _bookFile(id).path;
    final raw = await _readChapters(path);
    return [for (final j in raw) Chapter.fromJson(j)];
  }

  Future<void> remove(String id) async {
    _books.removeWhere((b) => b.id == id);
    final f = _bookFile(id);
    if (f.existsSync()) await f.delete();
    // Copertine e prima pagina.
    try {
      for (final e in _root.listSync()) {
        if (p.basename(e.path).startsWith('${id}_')) e.deleteSync();
      }
    } catch (_) {}
    await _saveIndex();
    notifyListeners();
  }

  /// Salva le modifiche a titolo, lingua, voce o posizione.
  Future<void> update(BookMeta meta, {bool notify = true}) async {
    await _saveIndex();
    if (notify) notifyListeners();
  }
}

// Funzioni di primo livello: all'isolate arrivano solo stringhe e liste.
Future<void> _writeJson(String path, Object data) =>
    Isolate.run(() => File(path).writeAsStringSync(jsonEncode(data)));

Future<List<Map<String, Object?>>> _readChapters(String path) => Isolate.run(() {
      final list = jsonDecode(File(path).readAsStringSync()) as List;
      return [for (final j in list) Map<String, Object?>.from(j as Map)];
    });
