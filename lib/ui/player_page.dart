import 'package:flutter/material.dart';

import '../core/voice_catalog.dart';
import '../services/library.dart';
import '../services/reader.dart';
import '../services/voice_store.dart';
import 'voices_page.dart';
import 'widgets.dart';

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
        child: Wrap(
          children: [
            const ListTile(title: Text('Velocità di lettura')),
            for (final s in speeds)
              ListTile(
                title: Text('${fmtSpeed(s)}${s == 1.0 ? '  (normale)' : ''}'),
                trailing: (reader.speed - s).abs() < 0.01 ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
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
        child: Wrap(
          children: [
            const ListTile(title: Text('Spegni la lettura tra…')),
            for (final m in [5, 15, 30, 45, 60, 90])
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
                title: const Text('Togli il timer'),
                onTap: () => Navigator.pop(ctx, 0),
              ),
          ],
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
    final installed = widget.store.installed;
    if (installed.isEmpty) {
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
              for (final v in installed)
                ListTile(
                  leading: Icon(v.gender == VoiceGender.female ? Icons.face_3_outlined : Icons.face_outlined),
                  title: Text(v.name),
                  subtitle: Text(v.description),
                  trailing: reader.voice?.id == v.id ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(ctx, v.id),
                ),
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('Altre voci…'),
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
    final v = voiceById(picked);
    if (v != null) await reader.selectVoice(v);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([reader, widget.store]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final book = reader.book;
        if (book == null || reader.loadingBook || reader.chunks.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(book?.title ?? '')),
            body: Center(
              child: book == null
                  ? const Text('Nessun libro aperto')
                  : const CircularProgressIndicator(),
            ),
          );
        }
        final ch = reader.chapters[reader.chapterIndex];
        final chTitle = ch.title.isEmpty ? 'Capitolo ${reader.chapterIndex + 1}' : ch.title;
        final voice = reader.voice;
        final sleepLeft = reader.sleepRemaining;

        return Scaffold(
          appBar: AppBar(
            title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(fontSize: 18),
            actions: [
              IconButton(
                tooltip: 'Capitoli',
                onPressed: _chapters,
                icon: const Icon(Icons.format_list_bulleted_rounded),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _chapters,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Capitolo ${reader.chapterIndex + 1} di ${reader.chapters.length}',
                                  style: theme.textTheme.labelMedium,
                                ),
                                Text(
                                  chTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.expand_more_rounded),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _TextView(reader: reader)),
                  const SizedBox(height: 8),
                  _ChapterSlider(reader: reader),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Text(
                          'Frase ${reader.index + 1} di ${reader.chunks.length}',
                          style: theme.textTheme.labelSmall,
                        ),
                        const Spacer(),
                        Text(
                          'mancano ${formatDuration(reader.chapterRemaining)}',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Controls(reader: reader),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _Pill(
                          icon: Icons.speed_rounded,
                          label: fmtSpeed(reader.speed),
                          onTap: _speed,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: _Pill(
                          icon: Icons.record_voice_over_outlined,
                          label: voice?.name ?? 'Scegli voce',
                          onTap: _voice,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Pill(
                          icon: reader.sleepTimerOn ? Icons.timer_rounded : Icons.timer_outlined,
                          label: sleepLeft != null
                              ? formatClock(sleepLeft)
                              : reader.sleepAtChapterEnd
                                  ? 'Fine cap.'
                                  : 'Timer',
                          highlighted: reader.sleepTimerOn,
                          onTap: _sleep,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: reader.bookProgress,
                            minHeight: 4,
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'libro ${(reader.bookProgress * 100).round()}%',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
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
    final preparing = reader.state == ReaderState.preparing;

    return Card(
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (i > 0)
                  Text(
                    chunks[i - 1],
                    style: theme.textTheme.bodyLarge?.copyWith(color: dim, height: 1.5),
                  ),
                if (i > 0) const SizedBox(height: 10),
                Text(
                  chunks[i],
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
                if (i + 1 < chunks.length) ...[
                  const SizedBox(height: 10),
                  Text(
                    chunks[i + 1],
                    style: theme.textTheme.bodyLarge?.copyWith(color: dim, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
          if (preparing)
            Positioned(
              right: 12,
              bottom: 10,
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Preparo la voce…', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
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
    if (count < 2) return const SizedBox(height: 8);
    final max = (count - 1).toDouble();
    final double value = (_drag ?? widget.reader.index.toDouble()).clamp(0.0, max).toDouble();
    return Slider(
      value: value,
      min: 0,
      max: max,
      label: 'Frase ${value.round() + 1}',
      divisions: count - 1 > 1000 ? null : count - 1,
      onChanged: (v) => setState(() => _drag = v),
      onChangeEnd: (v) {
        setState(() => _drag = null);
        widget.reader.seek(v.round());
      },
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
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: 'Capitolo precedente',
          iconSize: 30,
          onPressed: reader.chapterIndex > 0 || reader.index > 2 ? reader.previousChapter : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        IconButton(
          tooltip: 'Frase precedente',
          iconSize: 32,
          onPressed: reader.index > 0 ? reader.previous : null,
          icon: const Icon(Icons.replay_rounded),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(18),
          ),
          onPressed: reader.togglePlay,
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 40,
          ),
        ),
        IconButton(
          tooltip: 'Frase successiva',
          iconSize: 32,
          onPressed: reader.index + 1 < reader.chunks.length ? reader.next : null,
          icon: Transform.flip(flipX: true, child: const Icon(Icons.replay_rounded)),
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

class _Pill extends StatelessWidget {
  const _Pill({
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
    return Material(
      color: highlighted
          ? theme.colorScheme.secondary.withValues(alpha: 0.22)
          : theme.cardTheme.color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
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
            final minutes = (chapters[c].text.length / 14 / 60).ceil();
            return ListTile(
              selected: current,
              leading: SizedBox(
                width: 32,
                child: Text(
                  '${c + 1}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              title: Text(
                chapters[c].title.isEmpty ? 'Capitolo ${c + 1}' : chapters[c].title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('circa $minutes min'),
              trailing: current ? const Icon(Icons.graphic_eq_rounded) : null,
              onTap: () => Navigator.pop(context, c),
            );
          },
        ),
      ),
    );
  }
}
