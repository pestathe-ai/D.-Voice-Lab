/// Un libro nella libreria: titolo, capitoli e testo.
library;

import 'dart:typed_data';

class Chapter {
  const Chapter({required this.title, required this.text});

  final String title;
  final String text;

  Map<String, Object?> toJson() => {'title': title, 'text': text};

  factory Chapter.fromJson(Map<String, Object?> j) => Chapter(
        title: (j['title'] as String?) ?? '',
        text: (j['text'] as String?) ?? '',
      );
}

/// Dati di un libro senza il testo (per mostrare la libreria in fretta).
class BookMeta {
  BookMeta({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.lang,
    required this.addedAt,
    required this.chapterCount,
    required this.totalChars,
    this.chapter = 0,
    this.chunk = 0,
    this.progress = 0,
    this.lastOpened,
    this.voiceId,
    this.coverVersion = 0,
    this.positionAt = 0,
  });

  final String id;
  String title;
  String author;
  final String format;
  String lang;
  final DateTime addedAt;
  final int chapterCount;
  final int totalChars;

  /// Dove eri arrivato: capitolo e frase dentro il capitolo.
  int chapter;
  int chunk;

  /// Avanzamento complessivo, da 0 a 1.
  double progress;
  DateTime? lastOpened;

  /// Voce scelta per questo libro (null = quella generale).
  String? voiceId;

  /// 0 = nessuna copertina; cresce ogni volta che la copertina cambia.
  int coverVersion;

  /// Quando è stato spostato il segno l'ultima volta (millisecondi).
  int positionAt;

  /// Sposta il segno (capitolo e frase) e ne annota l'ora.
  void setPosition(int newChapter, int newChunk, {int? at}) {
    if (newChapter != chapter || newChunk != chunk) {
      chapter = newChapter;
      chunk = newChunk;
      positionAt = at ?? DateTime.now().millisecondsSinceEpoch;
    }
  }

  /// Durata stimata dell'ascolto (circa 14 caratteri al secondo).
  Duration get estimatedDuration => Duration(seconds: totalChars ~/ 14);

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'format': format,
        'lang': lang,
        'addedAt': addedAt.toIso8601String(),
        'chapterCount': chapterCount,
        'totalChars': totalChars,
        'chapter': chapter,
        'chunk': chunk,
        'progress': progress,
        'lastOpened': lastOpened?.toIso8601String(),
        'voiceId': voiceId,
        'coverVersion': coverVersion,
        'positionAt': positionAt,
      };

  factory BookMeta.fromJson(Map<String, Object?> j) => BookMeta(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? 'Senza titolo',
        author: (j['author'] as String?) ?? '',
        format: (j['format'] as String?) ?? 'txt',
        lang: (j['lang'] as String?) ?? 'it',
        addedAt: DateTime.tryParse((j['addedAt'] as String?) ?? '') ?? DateTime.now(),
        chapterCount: (j['chapterCount'] as num?)?.toInt() ?? 0,
        totalChars: (j['totalChars'] as num?)?.toInt() ?? 0,
        chapter: (j['chapter'] as num?)?.toInt() ?? 0,
        chunk: (j['chunk'] as num?)?.toInt() ?? 0,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        lastOpened: DateTime.tryParse((j['lastOpened'] as String?) ?? ''),
        voiceId: j['voiceId'] as String?,
        coverVersion: (j['coverVersion'] as num?)?.toInt() ?? 0,
        positionAt: (j['positionAt'] as num?)?.toInt() ?? 0,
      );
}

/// Risultato dell'importazione di un file, prima di salvarlo.
class ImportedBook {
  ImportedBook({
    required this.title,
    required this.author,
    required this.format,
    required this.chapters,
    this.coverBytes,
  });

  String title;
  String author;
  final String format;
  final List<Chapter> chapters;

  /// Copertina trovata dentro il file (EPUB) o la prima pagina (PDF).
  Uint8List? coverBytes;

  int get totalChars => chapters.fold(0, (s, c) => s + c.text.length);
}
