import 'dart:io';

import 'package:flutter/material.dart';

import '../core/book.dart';

import '../core/languages.dart';
import '../services/library.dart';
import '../services/reader.dart';
import 'theme.dart';

/// "1 h 05 min", "12 min", "45 s".
String formatDuration(Duration d) {
  if (d.inHours >= 1) {
    final m = d.inMinutes % 60;
    return '${d.inHours} h ${m.toString().padLeft(2, '0')} min';
  }
  if (d.inMinutes >= 1) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}

/// "1×", "1,25×".
String fmtSpeed(double s) {
  var t = s.toStringAsFixed(2);
  while (t.contains('.') && (t.endsWith('0') || t.endsWith('.'))) {
    t = t.substring(0, t.length - 1);
  }
  return '${t.replaceAll('.', ',')}×';
}

/// "12:05" per il conto alla rovescia del timer.
String formatClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// La copertina di un libro: l'immagine salvata o, se manca, una copertina
/// disegnata con titolo e autore.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.book,
    required this.library,
    this.size = 120,
    this.radius = 10,
    this.playing = false,
  });

  final BookMeta book;
  final Library library;
  final double size;
  final double radius;
  final bool playing;

  static const _palettes = [
    [Color(0xFF1D3A8A), Color(0xFF0E1A42)],
    [Color(0xFF2E6B5E), Color(0xFF123029)],
    [Color(0xFF8A3B1D), Color(0xFF3E180A)],
    [Color(0xFF5B3C88), Color(0xFF251543)],
    [Color(0xFF6B5B1D), Color(0xFF2E260A)],
    [Color(0xFF1D6B8A), Color(0xFF0A2E3E)],
  ];

  @override
  Widget build(BuildContext context) {
    final path = library.coverPath(book);
    Widget child;
    if (path != null) {
      child = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else {
      child = _placeholder();
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (playing)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Brand.orange, shape: BoxShape.circle),
                  child: const Icon(Icons.graphic_eq_rounded, color: Brand.ink, size: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    final colors = _palettes[book.title.hashCode.abs() % _palettes.length];
    final small = size < 80;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.09),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: size * 0.18, height: 3, color: Brand.orange),
            SizedBox(height: size * 0.06),
            Expanded(
              child: Text(
                small ? book.title.characters.take(1).toString().toUpperCase() : book.title,
                maxLines: small ? 1 : 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Brand.paper,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  fontSize: small ? size * 0.42 : size * 0.11,
                ),
              ),
            ),
            if (!small && book.author.isNotEmpty)
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Brand.paper.withValues(alpha: 0.75),
                  fontSize: size * 0.075,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Barra in fondo alla libreria con il libro che stai ascoltando.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.reader, required this.onOpen});

  final Reader reader;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = reader.book!;
    final ch = reader.chapters.isEmpty ? null : reader.chapters[reader.chapterIndex];
    final playing = reader.playing;
    return Material(
      color: const Color(0xFF1C2230),
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: onOpen,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: reader.bookProgress,
                minHeight: 2,
                backgroundColor: Colors.white12,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  children: [
                    CoverArt(book: b, library: reader.library, size: 44, radius: 6),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            b.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (ch != null)
                            Text(
                              ch.title.isEmpty ? 'Capitolo ${reader.chapterIndex + 1}' : ch.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Indietro 30 secondi',
                      onPressed: () => reader.skipBy(const Duration(seconds: -30)),
                      icon: const Icon(Icons.replay_30_rounded),
                    ),
                    IconButton(
                      iconSize: 36,
                      onPressed: reader.togglePlay,
                      icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                      color: Brand.orange,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Salva'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return ok == true;
}

Future<String?> pickLanguage(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'In che lingua è scritto il libro? Le voci naturali lo leggeranno '
                'con la pronuncia giusta.',
              ),
            ),
            for (final l in kLanguages)
              ListTile(
                title: Text(l.name),
                trailing: l.code == current ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(ctx, l.code),
              ),
          ],
        ),
      ),
    ),
  );
}
