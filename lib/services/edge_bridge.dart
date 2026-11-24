import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/book.dart';
import '../core/edge_page.dart';
import 'library.dart';

/// Ponte con Microsoft Edge: D. Voce prepara il testo del libro come una
/// pagina pulita, servita solo dentro il telefono, e la apre in Edge, che la
/// legge con le sue voci tramite "Leggi ad alta voce".
///
/// La pagina comunica a D. Voce dove sei arrivato, così il segnalibro resta
/// giusto; il pulsante "Torna a D. Voce" lo riporta anche se nel frattempo
/// Android ha messo in pausa l'app.
class EdgeBridge {
  EdgeBridge(this.library);

  final Library library;
  static const _channel = MethodChannel('dvoce/edge');

  /// Chiamata quando Edge comunica una nuova posizione nel libro.
  void Function(String bookId, int chapter, int chunk)? onPosition;

  HttpServer? _server;
  final String _token = _randomToken();

  static String _randomToken() {
    final r = math.Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'link') handleReturnLink('${call.arguments}');
      return null;
    });
    try {
      final initial = await _channel.invokeMethod<String>('initialLink');
      if (initial != null) handleReturnLink(initial);
    } catch (_) {
      // Su piattaforme senza il canale (test, desktop) non serve.
    }
  }

  Future<int> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing.port;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle, onError: (Object _) {});
    _server = server;
    return server.port;
  }

  String _base(int port) => 'http://127.0.0.1:$port/$_token';

  String returnUrl(String bookId) =>
      'intent://pos?id=$bookId&c=__C__&k=__K__#Intent;scheme=dvoce;package=dev.dvoce.d_voce;end';

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final segs = req.uri.pathSegments;
      if (segs.isEmpty || segs.first != _token) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      final q = req.uri.queryParameters;
      final id = q['id'] ?? '';
      final c = int.tryParse(q['c'] ?? '') ?? 0;
      final k = int.tryParse(q['k'] ?? '') ?? 0;
      final route = segs.length > 1 ? segs[1] : '';
      if (route == 'pos') {
        await _savePosition(id, c, k);
        res.statusCode = HttpStatus.noContent;
        await res.close();
        return;
      }
      if (route == 'book') {
        final meta = library.byId(id);
        if (meta == null) {
          res.statusCode = HttpStatus.notFound;
          await res.close();
          return;
        }
        final chapters = await library.loadChapters(id);
        final port = _server!.port;
        final page = buildEdgePage(
          bookTitle: meta.title,
          chapters: chapters,
          chapter: c.clamp(0, math.max(0, chapters.length - 1)).toInt(),
          chunk: k,
          posUrl: '${_base(port)}/pos?id=$id',
          returnUrl: returnUrl(id),
          nextUrl: (nc, nk) => '${_base(port)}/book?id=$id&c=$nc&k=$nk',
        );
        res.headers.contentType = ContentType.html;
        res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        res.add(utf8.encode(page.html));
        await res.close();
        unawaited(_savePosition(id, c, k));
        return;
      }
      res.statusCode = HttpStatus.notFound;
      await res.close();
    } catch (e) {
      try {
        res.statusCode = HttpStatus.internalServerError;
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> _savePosition(String id, int chapter, int chunk) async {
    final meta = library.byId(id);
    if (meta == null || chapter < 0 || chunk < 0) return;
    if (meta.chapter == chapter && meta.chunk == chunk) return;
    meta.chapter = chapter;
    meta.chunk = chunk;
    meta.lastOpened = DateTime.now();
    if (meta.chapterCount > 0) {
      meta.progress = (chapter / meta.chapterCount).clamp(0.0, 1.0).toDouble();
    }
    await library.update(meta);
    onPosition?.call(id, chapter, chunk);
  }

  /// Link "Torna a D. Voce": dvoce://pos?id=…&c=…&k=…
  void handleReturnLink(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'dvoce') return;
    final id = uri.queryParameters['id'];
    final c = int.tryParse(uri.queryParameters['c'] ?? '');
    final k = int.tryParse(uri.queryParameters['k'] ?? '');
    if (id == null || c == null || k == null) return;
    unawaited(_savePosition(id, c, k));
  }

  /// Apre il libro in Edge dal punto indicato. Restituisce false se Edge
  /// non è installato.
  Future<bool> open(BookMeta book, int chapter, int chunk) async {
    final port = await _ensureServer();
    final url = '${_base(port)}/book?id=${book.id}&c=$chapter&k=$chunk';
    try {
      final ok = await _channel.invokeMethod<bool>('openInEdge', {'url': url});
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('Edge: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> openStore() async {
    try {
      await _channel.invokeMethod<void>('openEdgeStore');
    } catch (_) {}
  }
}

/// Avanzamento più preciso, quando i capitoli sono già caricati.
double progressOf(List<Chapter> chapters, int chapter, int chunk) {
  if (chapters.isEmpty) return 0;
  var before = 0;
  var total = 0;
  for (var i = 0; i < chapters.length; i++) {
    final len = chapters[i].text.length;
    if (i < chapter) before += len;
    total += len;
  }
  return total == 0 ? 0 : before / total;
}
