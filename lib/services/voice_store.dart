import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/voice_catalog.dart';

enum VoiceStatus { notInstalled, downloading, installing, installed }

/// Scarica, installa ed elimina le voci sul telefono.
class VoiceStore extends ChangeNotifier {
  late Directory _root;
  bool _ready = false;

  final Map<String, double> _progress = {};
  final Map<String, VoiceStatus> _busy = {};
  final Set<String> _cancelled = {};
  final Map<String, HttpClient> _clients = {};

  bool get ready => _ready;

  Future<void> init() async {
    final support = await getApplicationSupportDirectory();
    _root = Directory(p.join(support.path, 'voices'));
    await _root.create(recursive: true);
    _ready = true;
    notifyListeners();
  }

  String modelPath(VoiceInfo v) => p.join(_root.path, v.folderName, v.modelFile);
  String tokensPath(VoiceInfo v) => p.join(_root.path, v.folderName, v.tokensFile);

  bool isInstalled(VoiceInfo v) =>
      _ready &&
      _busy[v.id] == null &&
      File(modelPath(v)).existsSync() &&
      File(tokensPath(v)).existsSync();

  VoiceStatus status(VoiceInfo v) {
    final busy = _busy[v.id];
    if (busy != null) return busy;
    return isInstalled(v) ? VoiceStatus.installed : VoiceStatus.notInstalled;
  }

  /// Avanzamento del download, da 0 a 1 (null se sconosciuto).
  double? progress(VoiceInfo v) => _progress[v.id];

  List<VoiceInfo> get installed => kVoices.where(isInstalled).toList();

  Future<void> download(VoiceInfo v) async {
    if (_busy[v.id] != null) return;
    _cancelled.remove(v.id);
    _busy[v.id] = VoiceStatus.downloading;
    _progress[v.id] = 0;
    notifyListeners();

    final archive = File(p.join(_root.path, v.archiveName));
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _clients[v.id] = client;
    try {
      final req = await client.getUrl(Uri.parse(v.url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('Download non riuscito (codice ${res.statusCode})');
      }
      final total = res.contentLength;
      var received = 0;
      var lastNotify = DateTime.now();
      final sink = archive.openWrite();
      try {
        await for (final chunk in res) {
          if (_cancelled.contains(v.id)) {
            throw const _Cancelled();
          }
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) _progress[v.id] = received / total;
          final now = DateTime.now();
          if (now.difference(lastNotify).inMilliseconds > 150) {
            lastNotify = now;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }

      _busy[v.id] = VoiceStatus.installing;
      _progress.remove(v.id);
      notifyListeners();

      // Si estrae in una cartella temporanea e poi si sposta: così una voce
      // a metà non sembra mai "installata".
      final tmp = Directory(p.join(_root.path, '_tmp_${v.id}'));
      if (tmp.existsSync()) await tmp.delete(recursive: true);
      await tmp.create(recursive: true);
      await _extractInBackground(archive.path, tmp.path);
      final extracted = Directory(p.join(tmp.path, v.folderName));
      if (!File(p.join(extracted.path, v.modelFile)).existsSync()) {
        await tmp.delete(recursive: true);
        throw const FileSystemException('Archivio della voce incompleto');
      }
      final dest = Directory(p.join(_root.path, v.folderName));
      if (dest.existsSync()) await dest.delete(recursive: true);
      await extracted.rename(dest.path);
      await tmp.delete(recursive: true);
    } on _Cancelled {
      // L'utente ha annullato: nessun errore da mostrare.
    } catch (_) {
      // Chiudere la connessione per annullare provoca un errore di rete:
      // se è stato l'utente ad annullare, non è un vero errore.
      if (!_cancelled.contains(v.id)) rethrow;
    } finally {
      client.close(force: true);
      _clients.remove(v.id);
      if (archive.existsSync()) {
        try {
          await archive.delete();
        } catch (_) {}
      }
      _busy.remove(v.id);
      _progress.remove(v.id);
      notifyListeners();
    }
  }

  void cancel(VoiceInfo v) {
    _cancelled.add(v.id);
    _clients[v.id]?.close(force: true);
  }

  Future<void> delete(VoiceInfo v) async {
    final dir = Directory(p.join(_root.path, v.folderName));
    if (dir.existsSync()) await dir.delete(recursive: true);
    notifyListeners();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Funzione di primo livello: la closure passata all'isolate contiene solo
/// le due stringhe, niente oggetti dell'interfaccia.
Future<void> _extractInBackground(String archivePath, String destDir) =>
    Isolate.run(() => extractVoiceArchive(archivePath, destDir));

/// Estrae il .tar.bz2 di una voce dentro [destDir].
/// I dati di espeak-ng inclusi nell'archivio non servono (l'app usa i
/// propri), quindi vengono saltati per risparmiare spazio.
void extractVoiceArchive(String archivePath, String destDir) {
  final compressed = File(archivePath).readAsBytesSync();
  final tarBytes = BZip2Decoder().decodeBytes(compressed);
  final archive = TarDecoder().decodeBytes(tarBytes);
  final root = p.normalize(destDir);
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final name = file.name;
    if (name.contains('espeak-ng-data/')) continue;
    final outPath = p.normalize(p.join(root, name));
    if (!p.isWithin(root, outPath)) continue; // sicurezza: niente ../
    final out = File(outPath);
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(file.content, flush: true);
  }
}
