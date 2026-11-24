import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/library.dart';
import '../services/reader.dart';
import '../services/voice_store.dart';
import 'cover_page.dart';
import 'theme.dart';
import 'voices_page.dart';
import 'widgets.dart';

/// Il lettore, in stile app di audiolibri: copertina grande, capitolo,
/// barra di avanzamento e comandi ±30 secondi.
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.store,
    required this.reader,
    required this.library,
  });

  final VoiceStore store;
  final Reader reader;
  final Library library;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  Reader get reader => widget.reader;

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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _openVoices() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VoicesPage(store: widget.store, reader: reader),
      ),
    );
  }

  Future<void> _chapters() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _ChaptersSheet(reader: reader),
    );
    if (picked != null) await reader.goToChapter(picked);
  }

  Future<void> _speed() async {
    const speeds = [0.75, 0.85, 1.0, 1.1, 1.2, 1.35, 1.5, 1.75, 2.0];
    final picked = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Velocità di lettura')),
              for (final s in speeds)
                ListTile(
                  title: Text('${fmtSpeed(s)}${s == 1.0 ? '  (normale)' : ''}'),
                  trailing: (reader.speed - s).abs() < 0.01
                      ? const Icon(Icons.check_rounded, color: Brand.orange)
                      : null,
                  onTap: () => Navigator.pop(ctx, s),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) reader.setSpeed(picked);
  }

  Future<void> _sleep() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Timer di spegnimento')),
              for (final m in [5, 10, 15, 30, 45, 60])
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text('$m minuti'),
                  onTap: () => Navigator.pop(ctx, m),
                ),
              ListTile(
                leading: const Icon(Icons.bookmark_outline_rounded),
                title: const Text('Alla fine del capitolo'),
                onTap: () => Navigator.pop(ctx, -1),
              ),
              if (reader.sleepTimerOn)
                ListTile(
                  leading: const Icon(Icons.timer_off_outlined),
                  title: const Text('Disattiva il timer'),
                  onTap: () => Navigator.pop(ctx, 0),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    if (picked == 0) {
      reader.cancelSleepTimer();
    } else if (picked == -1) {
      reader.setSleepAtChapterEnd();
    } else {
      reader.setSleepTimer(Duration(minutes: picked));
    }
  }

  Future<void> _voice() async {
    await reader.refreshSystemVoices();
    if (!mounted) return;
    final voices = reader.availableVoices;
    if (voices.isEmpty) {
      _openVoices();
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Chi legge questo libro?')),
              for (final v in voices)
                ListTile(
                  leading: Icon(
                    v.isSystem
                        ? (v.system!.network ? Icons.cloud_outlined : Icons.phone_android_rounded)
                        : Icons.download_done_rounded,
                  ),
                  title: Text(v.name),
                  subtitle: Text(v.description),
                  trailing: reader.voice?.id == v.id
                      ? const Icon(Icons.check_rounded, color: Brand.orange)
                      : null,
                  onTap: () => Navigator.pop(ctx, v.id),
                ),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Prova e gestisci le voci…'),
                onTap: () => Navigator.pop(ctx, '_more'),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    if (picked == '_more') {
      _openVoices();
      return;
    }
    for (final v in voices) {
      if (v.id == picked) {
        await reader.selectVoice(v);
        break;
      }
    }
  }

  void _text() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.6,
        child: ListenableBuilder(
          listenable: reader,
          builder: (context, _) => reader.chunks.isEmpty
              ? const SizedBox.shrink()
              : _TextView(reader: reader),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([reader, widget.store, widget.library]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final book = reader.book;
        if (book == null || reader.loadingBook || reader.chunks.isEmpty) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: book == null
                  ? const Text('Nessun libro aperto')
                  : const CircularProgressIndicator(),
            ),
          );
        }
        final ch = reader.chapters[reader.chapterIndex];
        final chTitle = ch.title.isEmpty ? 'Capitolo ${reader.chapterIndex + 1}' : ch.title;
        final sleepLeft = reader.sleepRemaining;
        final size = MediaQuery.sizeOf(context);
        final coverSize = math.min(size.width - 72, size.height * 0.36).clamp(140.0, 380.0).toDouble();

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Chiudi',
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            centerTitle: true,
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'cover') {
                    Navigator.of(context).push(MaterialPageRoute<bool>(
                      builder: (_) => CoverPage(book: book, library: widget.library),
                    ));
                  } else if (v == 'voices') {
                    _openVoices();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'cover', child: Text('Cambia copertina')),
                  PopupMenuItem(value: 'voices', child: Text('Voci')),
                ],
              ),
            ],
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1A2340), Color(0xFF0D1018)],
                stops: [0, 0.6],
              ),
            ),
            child: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 12)),
                                  ],
                                ),
                                child: CoverArt(
                                  book: book,
                                  library: widget.library,
                                  size: coverSize,
                                  radius: 14,
                                ),
                              ),
                              const SizedBox(height: 22),
                              Text(
                                book.title,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              if (book.author.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  book.author,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _chapters,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          chTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelLarge?.copyWith(color: Brand.orange),
                                        ),
                                      ),
                                      const Icon(Icons.expand_more_rounded, color: Brand.orange, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Column(
                            children: [
                              _ChapterSlider(reader: reader),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(formatClock(reader.chapterElapsed), style: theme.textTheme.labelSmall),
                                  const Spacer(),
                                  Text(
                                    reader.state == ReaderState.preparing ? 'Preparo la voce…' : '',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                  const Spacer(),
                                  Text('-${formatClock(reader.chapterRemaining)}', style: theme.textTheme.labelSmall),
                                ],
                              ),
                              const SizedBox(height: 14),
                              _Controls(reader: reader),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _BottomAction(
                                    icon: Icons.speed_rounded,
                                    label: fmtSpeed(reader.speed),
                                    onTap: _speed,
                                  ),
                                  _BottomAction(
                                    icon: reader.sleepTimerOn ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                                    label: sleepLeft != null
                                        ? formatClock(sleepLeft)
                                        : reader.sleepAtChapterEnd
                                            ? 'Fine cap.'
                                            : 'Timer',
                                    highlighted: reader.sleepTimerOn,
                                    onTap: _sleep,
                                  ),
                                  _BottomAction(
                                    icon: Icons.format_list_bulleted_rounded,
                                    label: 'Capitoli',
                                    onTap: _chapters,
                                  ),
                                  _BottomAction(
                                    icon: Icons.record_voice_over_outlined,
                                    label: reader.voice?.name ?? 'Voce',
                                    onTap: _voice,
                                  ),
                                  _BottomAction(
                                    icon: Icons.notes_rounded,
                                    label: 'Testo',
                                    onTap: _text,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        value: reader.bookProgress,
                                        minHeight: 2,
                                        backgroundColor: Colors.white12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Libro ${(reader.bookProgress * 100).round()}% · '
                                    'cap. ${reader.chapterIndex + 1}/${reader.chapters.length}',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _TextView extends StatelessWidget {
  const _TextView({required this.reader});
  final Reader reader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i = reader.index;
    final chunks = reader.chunks;
    final dim = theme.colorScheme.onSurface.withValues(alpha: 0.45);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (i > 0)
            Text(chunks[i - 1], style: theme.textTheme.bodyLarge?.copyWith(color: dim, height: 1.5)),
          if (i > 0) const SizedBox(height: 12),
          Text(
            chunks[i],
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.45),
          ),
          if (i + 1 < chunks.length) ...[
            const SizedBox(height: 12),
            Text(chunks[i + 1], style: theme.textTheme.bodyLarge?.copyWith(color: dim, height: 1.5)),
          ],
        ],
      ),
    );
  }
}

class _ChapterSlider extends StatefulWidget {
  const _ChapterSlider({required this.reader});
  final Reader reader;

  @override
  State<_ChapterSlider> createState() => _ChapterSliderState();
}

class _ChapterSliderState extends State<_ChapterSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final count = widget.reader.chunks.length;
    if (count < 2) return const SizedBox(height: 14);
    final max = (count - 1).toDouble();
    final double value = (_drag ?? widget.reader.index.toDouble()).clamp(0.0, max).toDouble();
    return SizedBox(
      height: 24,
      child: Slider(
        value: value,
        min: 0,
        max: max,
        onChanged: (v) => setState(() => _drag = v),
        onChangeEnd: (v) {
          setState(() => _drag = null);
          widget.reader.seek(v.round());
        },
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.reader});
  final Reader reader;

  @override
  Widget build(BuildContext context) {
    final playing = reader.playing;
    final hasNextChapter = reader.chapterIndex + 1 < reader.chapters.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: 'Capitolo precedente',
          iconSize: 30,
          onPressed: reader.chapterIndex > 0 || reader.index > 2 ? reader.previousChapter : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        IconButton(
          tooltip: 'Indietro 30 secondi',
          iconSize: 38,
          onPressed: () => reader.skipBy(const Duration(seconds: -30)),
          icon: const Icon(Icons.replay_30_rounded),
        ),
        SizedBox(
          width: 78,
          height: 78,
          child: IconButton.filled(
            onPressed: reader.togglePlay,
            style: IconButton.styleFrom(
              backgroundColor: Brand.orange,
              foregroundColor: Brand.ink,
            ),
            iconSize: 46,
            icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
        ),
        IconButton(
          tooltip: 'Avanti 30 secondi',
          iconSize: 38,
          onPressed: () => reader.skipBy(const Duration(seconds: 30)),
          icon: const Icon(Icons.forward_30_rounded),
        ),
        IconButton(
          tooltip: 'Capitolo successivo',
          iconSize: 30,
          onPressed: hasNextChapter ? reader.nextChapter : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlighted ? Brand.orange : theme.colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        width: 62,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChaptersSheet extends StatelessWidget {
  const _ChaptersSheet({required this.reader});
  final Reader reader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chapters = reader.chapters;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: chapters.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return const ListTile(title: Text('Capitoli'));
            }
            final c = i - 1;
            final current = c == reader.chapterIndex;
            final minutes = (chapters[c].text.length / 14 / 60 / reader.speed).ceil();
            return ListTile(
              selected: current,
              selectedColor: Brand.orange,
              leading: SizedBox(
                width: 32,
                child: Text('${c + 1}', textAlign: TextAlign.center, style: theme.textTheme.labelLarge),
              ),
              title: Text(
                chapters[c].title.isEmpty ? 'Capitolo ${c + 1}' : chapters[c].title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('$minutes min'),
              trailing: current ? const Icon(Icons.graphic_eq_rounded) : null,
              onTap: () => Navigator.pop(context, c),
            );
          },
        ),
      ),
    );
  }
}
