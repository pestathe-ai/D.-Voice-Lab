import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/book.dart';
import '../core/languages.dart';
import '../services/book_import.dart';
import '../services/covers.dart';
import '../services/library.dart';
import '../services/reader.dart';
import '../services/voice_store.dart';
import 'cover_page.dart';
import 'player_page.dart';
import 'paste_page.dart';
import 'theme.dart';
import 'voices_page.dart';
import 'widgets.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.store,
    required this.reader,
    required this.library,
  });

  final VoiceStore store;
  final Reader reader;
  final Library library;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  Reader get reader => widget.reader;
  Library get library => widget.library;
  VoiceStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    reader.addListener(_onReaderChanged);
  }

  @override
  void dispose() {
    reader.removeListener(_onReaderChanged);
    super.dispose();
  }

  void _onReaderChanged() {
    final err = reader.error;
    if (err != null && mounted && ModalRoute.of(context)?.isCurrent == true) {
      reader.clearError();
      _snack(err);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openVoices() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VoicesPage(store: store, reader: reader),
      ),
    );
  }

  Future<void> _openBook(BookMeta meta, {bool autoplay = false}) async {
    if (autoplay) {
      unawaited(reader.openBook(meta).then((_) => reader.play()));
    } else {
      unawaited(reader.openBook(meta));
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(store: store, reader: reader, library: library),
      ),
    );
  }

  Future<void> _addBook() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: const Text('Apri un libro dal telefono'),
              subtitle: const Text('PDF, EPUB o TXT'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_rounded),
              title: const Text('Incolla un testo'),
              subtitle: const Text('Un articolo, una pagina, un racconto'),
              onTap: () => Navigator.pop(ctx, 'paste'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'file') {
      await _importFile();
    } else {
      final imported = await Navigator.of(context).push<ImportedBook>(
        MaterialPageRoute(builder: (_) => const PastePage()),
      );
      if (imported != null && mounted) await _confirmAndAdd(imported);
    }
  }

  Future<void> _importFile() async {
    PlatformFile? file;
    try {
      file = await FilePicker.pickFile(type: FileType.any);
    } catch (e) {
      _snack('Non riesco ad aprire la scelta dei file: $e');
      return;
    }
    if (file == null || !mounted) return;
    final name = file.name;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (!kSupportedExtensions.contains(ext)) {
      _snack('Scegli un file PDF, EPUB o TXT.');
      return;
    }

    final progress = ValueNotifier<double?>(null);
    final navigator = Navigator.of(context);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Preparo il libro'),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (context, v, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: v),
                const SizedBox(height: 12),
                Text(v == null
                    ? 'Leggo il file…'
                    : 'Leggo le pagine… ${(v * 100).round()}%'),
              ],
            ),
          ),
        ),
      ),
    ));

    ImportedBook? imported;
    Object? failure;
    try {
      final bytes = await file.xFile.readAsBytes();
      imported = await importBook(name, bytes, onProgress: (v) => progress.value = v);
    } catch (e) {
      failure = e;
    }
    if (!mounted) return;
    navigator.pop();
    progress.dispose();
    if (failure != null || imported == null) {
      _snack('$failure');
      return;
    }
    await _confirmAndAdd(imported);
  }

  Future<void> _confirmAndAdd(ImportedBook imported) async {
    final sample = imported.chapters.take(3).map((c) => c.text).join('\n');
    final result = await showModalBottomSheet<(String, String, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ConfirmSheet(
        imported: imported,
        guessedLang: guessLanguage(sample),
      ),
    );
    if (result == null || !mounted) return;
    imported.title = result.$1;
    imported.author = result.$3;
    try {
      final meta = await library.add(imported, lang: result.$2);
      if (!mounted) return;
      // EPUB con copertina e PDF (la prima pagina è quasi sempre la
      // copertina) ce l'hanno già; per gli altri la si cerca online.
      if (meta.coverVersion == 0 && meta.format != 'testo') {
        unawaited(_autoCover(meta));
      }
      await _openBook(meta, autoplay: true);
    } catch (e) {
      _snack('Non riesco a salvare il libro: $e');
    }
  }

  Future<void> _autoCover(BookMeta meta) async {
    final search = CoverSearch();
    try {
      final bytes = await search.findFirst(meta.title, author: meta.author);
      if (bytes != null && meta.coverVersion == 0) {
        await library.setCover(meta, bytes);
      }
    } catch (_) {
      // Niente copertina: resta quella disegnata.
    } finally {
      search.close();
    }
  }

  Future<void> _changeCover(BookMeta b) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CoverPage(book: b, library: library)),
    );
  }

  /// "Continua ad ascoltare": riparte subito da dove eri rimasto.
  Future<void> _resume(BookMeta b) async {
    if (reader.book?.id != b.id) {
      await reader.openBook(b);
    }
    await reader.togglePlay();
  }

  Future<void> _bookMenu(BookMeta b) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                b.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Cambia copertina'),
              onTap: () => Navigator.pop(ctx, 'cover'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Cambia titolo'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Cambia autore'),
              onTap: () => Navigator.pop(ctx, 'author'),
            ),
            ListTile(
              leading: const Icon(Icons.translate_rounded),
              title: const Text('Lingua del libro'),
              subtitle: Text(languageName(b.lang)),
              onTap: () => Navigator.pop(ctx, 'lang'),
            ),
            ListTile(
              leading: const Icon(Icons.replay_rounded),
              title: const Text('Ricomincia dall\'inizio'),
              onTap: () => Navigator.pop(ctx, 'restart'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Elimina dalla libreria'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'cover':
        await _changeCover(b);
      case 'author':
        final t = await askText(context, title: 'Autore', initial: b.author);
        if (t != null) {
          b.author = t.trim();
          await library.update(b);
        }
      case 'rename':
        final t = await askText(context, title: 'Titolo del libro', initial: b.title);
        if (t != null && t.trim().isNotEmpty) {
          b.title = t.trim();
          await library.update(b);
        }
      case 'lang':
        final code = await pickLanguage(context, b.lang);
        if (code != null) {
          b.lang = code;
          await library.update(b);
        }
      case 'restart':
        if (reader.book?.id == b.id) {
          await reader.goToChapter(0);
        } else {
          b.chapter = 0;
          b.chunk = 0;
          b.progress = 0;
          await library.update(b);
        }
      case 'delete':
        final ok = await confirm(
          context,
          title: 'Eliminare "${b.title}"?',
          message: 'Il libro e il segnalibro verranno cancellati dal telefono.',
          action: 'Elimina',
        );
        if (ok) {
          if (reader.book?.id == b.id) await reader.closeBook();
          await library.remove(b.id);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([library, store, reader]),
      builder: (context, _) {
        final books = library.books;
        final theme = Theme.of(context);
        final current = reader.book ?? (books.isNotEmpty && books.first.lastOpened != null ? books.first : null);
        final others = [for (final b in books) if (b.id != current?.id) b];
        final noVoices = reader.availableVoices.isEmpty && reader.systemVoicesLoaded;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Libreria'),
            actions: [
              IconButton(
                tooltip: 'Voci',
                icon: const Icon(Icons.record_voice_over_outlined),
                onPressed: _openVoices,
              ),
              const SizedBox(width: 4),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _addBook,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Aggiungi libro'),
          ),
          bottomNavigationBar: reader.book != null && reader.active
              ? MiniPlayer(reader: reader, onOpen: () => _openBook(reader.book!))
              : null,
          body: SafeArea(
            top: false,
            child: CustomScrollView(
              slivers: [
                if (noVoices)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    sliver: SliverToBoxAdapter(child: _NoVoiceBanner(onTap: _openVoices)),
                  ),
                if (books.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: _EmptyLibrary())
                else ...[
                  if (current != null)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      sliver: SliverToBoxAdapter(
                        child: _ContinueCard(
                          book: current,
                          library: library,
                          reader: reader,
                          onOpen: () => _openBook(current),
                          onPlay: () => _resume(current),
                        ),
                      ),
                    ),
                  if (others.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          current == null ? 'I tuoi titoli' : 'Altri titoli',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.66,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        childCount: others.length,
                        (context, i) => _BookTile(
                          book: others[i],
                          library: library,
                          playing: reader.book?.id == others[i].id && reader.playing,
                          onTap: () => _openBook(others[i]),
                          onMenu: () => _bookMenu(others[i]),
                        ),
                      ),
                    ),
                  ),
                  if (current != null)
                    SliverToBoxAdapter(
                      child: Center(
                        child: TextButton.icon(
                          onPressed: () => _bookMenu(current),
                          icon: const Icon(Icons.more_horiz_rounded),
                          label: Text('Opzioni di "${current.title.length > 24 ? '${current.title.substring(0, 24)}…' : current.title}"'),
                        ),
                      ),
                    ),
                ],
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    child: Center(
                      child: Text(
                        'un\'app Dom Studio',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _NoVoiceBanner extends StatelessWidget {
  const _NoVoiceBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.orange.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.download_rounded, color: Brand.orange),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Non trovo voci italiane sul telefono. Tocca qui per scegliere o scaricare una voce.',
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
      child: Column(
        children: [
          Icon(Icons.headphones_rounded, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Trasforma i tuoi libri in audiolibri',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Aggiungi un PDF, un EPUB o un file di testo: te lo leggo io, '
            'capitolo dopo capitolo, e mi ricordo dove eri arrivato.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.book,
    required this.library,
    required this.reader,
    required this.onOpen,
    required this.onPlay,
  });

  final BookMeta book;
  final Library library;
  final Reader reader;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOpen = reader.book?.id == book.id && reader.chapters.isNotEmpty;
    final playing = isOpen && reader.playing;
    final progress = isOpen ? reader.bookProgress : book.progress;
    final left = Duration(
      seconds: ((1 - progress) * book.estimatedDuration.inSeconds / reader.speed).round(),
    );
    final chapterLine = isOpen
        ? (reader.chapters[reader.chapterIndex].title.isEmpty
            ? 'Capitolo ${reader.chapterIndex + 1}'
            : reader.chapters[reader.chapterIndex].title)
        : 'Capitolo ${book.chapter + 1} di ${book.chapterCount}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Continua ad ascoltare',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Material(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CoverArt(book: book, library: library, size: 112, radius: 10, playing: playing),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (book.author.isNotEmpty)
                          Text(
                            book.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        const SizedBox(height: 6),
                        Text(
                          chapterLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                progress >= 0.999 ? 'Finito' : 'Mancano ${formatDuration(left)}',
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                            IconButton.filled(
                              onPressed: onPlay,
                              iconSize: 30,
                              style: IconButton.styleFrom(
                                backgroundColor: Brand.orange,
                                foregroundColor: Brand.ink,
                              ),
                              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.library,
    required this.playing,
    required this.onTap,
    required this.onMenu,
  });

  final BookMeta book;
  final Library library;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onMenu,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) => Stack(
              children: [
                CoverArt(book: book, library: library, size: c.maxWidth, playing: playing),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Material(
                    color: Colors.black38,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onMenu,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.more_vert_rounded, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: book.progress,
              minHeight: 3,
              backgroundColor: Colors.white12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            book.progress >= 0.999
                ? 'Finito'
                : book.progress > 0
                    ? '${(book.progress * 100).round()}% · ${book.author}'
                    : (book.author.isEmpty ? languageName(book.lang) : book.author),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _ConfirmSheet extends StatefulWidget {
  const _ConfirmSheet({required this.imported, required this.guessedLang});

  final ImportedBook imported;
  final String guessedLang;

  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.imported.title);
  late final TextEditingController _author =
      TextEditingController(text: widget.imported.author);
  late String _lang = widget.guessedLang;

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chapters = widget.imported.chapters;
    final minutes = widget.imported.totalChars ~/ 14 ~/ 60;
    final duration = minutes >= 60
        ? 'circa ${(minutes / 60).toStringAsFixed(1).replaceAll('.', ',')} ore di ascolto'
        : 'circa $minutes minuti di ascolto';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Libro pronto', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              '${chapters.length} ${chapters.length == 1 ? 'capitolo' : 'capitoli'} · $duration',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Titolo'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _author,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Autore (facoltativo)',
                helperText: 'Serve a trovare la copertina giusta',
              ),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Lingua del libro'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isDense: true,
                  isExpanded: true,
                  value: _lang,
                  items: [
                    for (final l in kLanguages)
                      DropdownMenuItem(value: l.code, child: Text(l.name)),
                  ],
                  onChanged: (v) => setState(() => _lang = v ?? _lang),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Capitoli trovati', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < chapters.length && i < 50; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${i + 1}. ${chapters[i].title.isEmpty ? 'Capitolo ${i + 1}' : chapters[i].title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  if (chapters.length > 50)
                    Text('… e altri ${chapters.length - 50}', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => Navigator.pop(context, (
                _title.text.trim().isEmpty ? widget.imported.title : _title.text.trim(),
                _lang,
                _author.text.trim(),
              )),
              icon: const Icon(Icons.headphones_rounded),
              label: const Text('Aggiungi e ascolta'),
            ),
          ],
        ),
      ),
    );
  }
}
