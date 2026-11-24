import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/voice_catalog.dart';

enum VoiceStatus { notInstalled, downloading, installing, installed }

/// Scarica, installa ed elimina i pacchetti di voci sul telefono.
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
    // Resti di installazioni interrotte.
    for (final e in _root.listSync()) {
      final name = p.basename(e.path);
      if (name.startsWith('_tmp_') || name.endsWith('.tar.bz2') || name.endsWith('.tar')) {
        try {
          e.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
    _ready = true;
    notifyListeners();
  }

  String packDir(VoicePack pack) => p.join(_root.path, pack.folderName);

  String modelPath(VoiceInfo v) => p.join(packDir(v.pack), '${v.pack.id}.onnx');
  String tokensPath(VoiceInfo v) => p.join(packDir(v.pack), 'tokens.txt');

  bool isPackInstalled(VoicePack pack) =>
      _ready &&
      _busy[pack.id] == null &&
      pack.requiredFiles.every((f) => File(p.join(packDir(pack), f)).existsSync());

  bool isInstalled(VoiceInfo v) => isPackInstalled(v.pack);

  VoiceStatus status(VoicePack pack) {
    final busy = _busy[pack.id];
    if (busy != null) return busy;
    return isPackInstalled(pack) ? VoiceStatus.installed : VoiceStatus.notInstalled;
  }

  /// Avanzamento del download, da 0 a 1 (null se sconosciuto).
  double? progress(VoicePack pack) => _progress[pack.id];

  List<VoiceInfo> get installed => kVoices.where(isInstalled).toList();

  bool get anyInstalled => kPacks.any(isPackInstalled);

  Future<void> download(VoicePack pack) async {
    if (_busy[pack.id] != null) return;
    _cancelled.remove(pack.id);
    _busy[pack.id] = VoiceStatus.downloading;
    _progress[pack.id] = 0;
    notifyListeners();

    final archive = File(p.join(_root.path, pack.archiveName));
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _clients[pack.id] = client;
    try {
      final req = await client.getUrl(Uri.parse(pack.url));
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
          if (_cancelled.contains(pack.id)) {
            throw const _Cancelled();
          }
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) _progress[pack.id] = received / total;
          final now = DateTime.now();
          if (now.difference(lastNotify).inMilliseconds > 200) {
            lastNotify = now;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && received < total) {
        throw const HttpException('Download interrotto: riprova con una connessione stabile.');
      }

      _busy[pack.id] = VoiceStatus.installing;
      _progress.remove(pack.id);
      notifyListeners();

      // Si estrae in una cartella temporanea e poi si sposta: così una voce
      // a metà non sembra mai "installata".
      final tmp = Directory(p.join(_root.path, '_tmp_${pack.id}'));
      if (tmp.existsSync()) await tmp.delete(recursive: true);
      await tmp.create(recursive: true);
      await _extractInBackground(archive.path, tmp.path);
      final extracted = Directory(p.join(tmp.path, pack.folderName));
      final missing = pack.requiredFiles
          .where((f) => !File(p.join(extracted.path, f)).existsSync())
          .toList();
      if (missing.isNotEmpty) {
        await tmp.delete(recursive: true);
        throw FileSystemException('Archivio delle voci incompleto (${missing.join(', ')})');
      }
      final dest = Directory(packDir(pack));
      if (dest.existsSync()) await dest.delete(recursive: true);
      await extracted.rename(dest.path);
      await tmp.delete(recursive: true);
    } on _Cancelled {
      // L'utente ha annullato: nessun errore da mostrare.
    } catch (_) {
      // Chiudere la connessione per annullare provoca un errore di rete:
      // se è stato l'utente ad annullare, non è un vero errore.
      if (!_cancelled.contains(pack.id)) rethrow;
    } finally {
      client.close(force: true);
      _clients.remove(pack.id);
      if (archive.existsSync()) {
        try {
          await archive.delete();
        } catch (_) {}
      }
      _busy.remove(pack.id);
      _progress.remove(pack.id);
      notifyListeners();
    }
  }

  void cancel(VoicePack pack) {
    _cancelled.add(pack.id);
    _clients[pack.id]?.close(force: true);
  }

  Future<void> delete(VoicePack pack) async {
    final dir = Directory(packDir(pack));
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

/// Estrae il .tar.bz2 di un pacchetto dentro [destDir], passando da file
/// su disco (i pacchetti grandi non stanno comodi in memoria).
/// I dati di espeak-ng inclusi negli archivi Piper non servono (l'app usa
/// i propri), quindi vengono saltati per risparmiare spazio.
void extractVoiceArchive(String archivePath, String destDir) {
  final tarPath = '$archivePath.tar';
  final input = InputFileStream(archivePath);
  final tarOut = OutputFileStream(tarPath);
  try {
    BZip2Decoder().decodeStream(input, tarOut);
  } finally {
    input.closeSync();
    tarOut.closeSync();
  }

  final tarIn = InputFileStream(tarPath);
  try {
    final archive = TarDecoder().decodeStream(tarIn);
    final root = p.normalize(destDir);
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name;
      if (name.contains('espeak-ng-data/')) continue;
      final outPath = p.normalize(p.join(root, name));
      if (!p.isWithin(root, outPath)) continue; // sicurezza: niente ../
      File(outPath).parent.createSync(recursive: true);
      final out = OutputFileStream(outPath);
      try {
        file.writeContent(out);
      } finally {
        out.closeSync();
      }
    }
  } finally {
    tarIn.closeSync();
    try {
      File(tarPath).deleteSync();
    } catch (_) {}
  }
}
