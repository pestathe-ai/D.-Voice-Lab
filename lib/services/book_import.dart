import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/book.dart';
import '../core/epub.dart';
import '../core/text_cleanup.dart';

class ImportException implements Exception {
  ImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

const List<String> kSupportedExtensions = ['pdf', 'epub', 'txt', 'md'];

bool _pdfrxReady = false;

/// Trasforma un file (PDF, EPUB, TXT) in un libro con capitoli.
/// [onProgress] riceve un valore da 0 a 1 mentre si leggono le pagine.
Future<ImportedBook> importBook(
  String fileName,
  Uint8List bytes, {
  void Function(double progress)? onProgress,
}) async {
  final ext = p.extension(fileName).toLowerCase().replaceFirst('.', '');
  final fallbackTitle = titleFromFileName(fileName);
  switch (ext) {
    case 'pdf':
      return _importPdf(fallbackTitle, bytes, onProgress);
    case 'epub':
      return _epubInIsolate(bytes, fallbackTitle);
    case 'txt':
    case 'md':
    case 'text':
      final chapters = await _textInIsolate(_decodeText(bytes));
      if (chapters.isEmpty) throw ImportException('Il file è vuoto.');
      return ImportedBook(title: fallbackTitle, author: '', format: 'txt', chapters: chapters);
    default:
      throw ImportException('Formato non supportato: scegli un file PDF, EPUB o TXT.');
  }
}

/// Un testo incollato diventa un "libro" con i suoi capitoli.
Future<ImportedBook> importPastedText(String title, String text) async {
  final chapters = await _textInIsolate(text);
  if (chapters.isEmpty) throw ImportException('Non c\'è niente da leggere.');
  return ImportedBook(
    title: title.trim().isEmpty ? 'Testo incollato' : title.trim(),
    author: '',
    format: 'testo',
    chapters: chapters,
  );
}

// Funzioni di primo livello: così all'isolate arrivano solo i dati.
Future<ImportedBook> _epubInIsolate(Uint8List bytes, String title) =>
    Isolate.run(() => parseEpub(bytes, fallbackTitle: title));

Future<List<Chapter>> _textInIsolate(String text) =>
    Isolate.run(() => chaptersFromPlainText(text));

Future<List<Chapter>> _pdfInIsolate(List<String> pages, List<OutlineEntry> outline) =>
    Isolate.run(() => chaptersFromPdfPages(pages, outline: outline));

String _decodeText(Uint8List bytes) {
  String s;
  try {
    s = utf8.decode(bytes);
  } on FormatException {
    s = latin1.decode(bytes);
  }
  return s.replaceFirst('﻿', '');
}

Future<ImportedBook> _importPdf(
  String title,
  Uint8List bytes,
  void Function(double)? onProgress,
) async {
  if (!_pdfrxReady) {
    await pdfrxFlutterInitialize();
    _pdfrxReady = true;
  }
  final tmpDir = await getTemporaryDirectory();
  final tmp = File(p.join(tmpDir.path, 'import_${DateTime.now().microsecondsSinceEpoch}.pdf'));
  await tmp.writeAsBytes(bytes, flush: true);

  PdfDocument? doc;
  try {
    try {
      doc = await PdfDocument.openFile(tmp.path);
    } catch (e) {
      throw ImportException(
        'Non riesco ad aprire il PDF. Se è protetto da password, toglila e riprova.',
      );
    }
    final pages = <String>[];
    final n = doc.pages.length;
    for (var i = 0; i < n; i++) {
      final text = await doc.pages[i].loadText();
      pages.add(text?.fullText ?? '');
      onProgress?.call((i + 1) / n);
    }

    final chars = pages.fold<int>(0, (s, t) => s + t.trim().length);
    if (chars < 50 * (n < 10 ? n : 10)) {
      throw ImportException(
        'Questo PDF sembra fatto di immagini (pagine fotografate): '
        'non contiene testo da leggere.',
      );
    }

    final outline = <OutlineEntry>[];
    try {
      final nodes = await doc.loadOutline();
      void walk(List<PdfOutlineNode> list, int depth) {
        for (final node in list) {
          final page = node.dest?.pageNumber;
          if (page != null) outline.add(OutlineEntry(node.title, page));
          if (depth < 1) walk(node.children, depth + 1);
        }
      }

      // Si usano i capitoli principali; i sottocapitoli solo se sono pochi.
      walk(nodes, 1);
      if (outline.length < 3) {
        outline.clear();
        walk(nodes, 0);
      }
    } catch (_) {
      // Nessun indice nel PDF: i capitoli si cercano nel testo.
    }

    final chapters = await _pdfInIsolate(pages, outline);
    if (chapters.isEmpty) throw ImportException('Nel PDF non ho trovato testo da leggere.');
    Uint8List? cover;
    try {
      cover = await _renderFirstPage(doc.pages.first);
    } catch (_) {
      // Senza anteprima si va avanti lo stesso.
    }
    return ImportedBook(
      title: title,
      author: '',
      format: 'pdf',
      chapters: chapters,
      coverBytes: cover,
    );
  } finally {
    await doc?.dispose();
    try {
      await tmp.delete();
    } catch (_) {}
  }
}

/// Disegna la prima pagina del PDF come immagine PNG (copertina di riserva).
Future<Uint8List?> _renderFirstPage(PdfPage page) async {
  const targetWidth = 600;
  final ratio = page.height / page.width;
  final w = targetWidth;
  final h = (targetWidth * ratio).round();
  if (h <= 0 || h > 3000) return null;
  final img = await page.render(
    fullWidth: w.toDouble(),
    fullHeight: h.toDouble(),
    backgroundColor: 0xffffffff,
  );
  if (img == null) return null;
  try {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      img.pixels,
      img.width,
      img.height,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    final image = await completer.future;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  } finally {
    img.dispose();
  }
}
