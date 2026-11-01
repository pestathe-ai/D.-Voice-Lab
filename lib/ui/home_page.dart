import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/text_chunker.dart';
import '../core/voice_catalog.dart';
import '../services/reader.dart';
import '../services/voice_store.dart';
import 'theme.dart';
import 'voices_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store, required this.reader});

  final VoiceStore store;
  final Reader reader;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TextEditingController _text;
  Timer? _saveTimer;

  Reader get reader => widget.reader;
  VoiceStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: reader.draft);
    _text.addListener(_onTextChanged);
    reader.addListener(_onReaderChanged);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    reader.saveDraft(_text.text);
    reader.removeListener(_onReaderChanged);
    _text.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      reader.saveDraft(_text.text);
    });
    setState(() {});
  }

  void _onReaderChanged() {
    final err = reader.error;
    if (err != null && mounted) {
      reader.clearError();
      _snack(err);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t == null || t.trim().isEmpty) {
      _snack('Negli appunti non c\'è testo.');
      return;
    }
    final current = _text.text;
    _text.text = current.trim().isEmpty ? t : '$current\n\n$t';
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
  }

  Future<void> _openFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'md'],
      );
      if (file == null) return;
      final bytes = await file.xFile.readAsBytes();
      String content;
      try {
        content = utf8.decode(bytes);
      } on FormatException {
        content = latin1.decode(bytes);
      }
      _text.text = content.replaceFirst('﻿', '');
      _snack('Aperto: ${file.name}');
    } catch (e) {
      _snack('Non riesco ad aprire il file: $e');
    }
  }

  Future<void> _clear() async {
    if (_text.text.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Svuotare il testo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Svuota'),
          ),
        ],
      ),
    );
    if (ok == true) _text.clear();
  }

  void _openVoices() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VoicesPage(store: store, reader: reader),
      ),
    );
  }

  Future<void> _listen() async {
    FocusScope.of(context).unfocus();
    reader.saveDraft(_text.text);
    await reader.start(_text.text);
  }

  Future<void> _export() async {
    FocusScope.of(context).unfocus();
    final text = _text.text;
    if (splitIntoChunks(text).isEmpty) {
      _snack('Scrivi o incolla prima un testo.');
      return;
    }
    final navigator = Navigator.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ExportDialog(reader: reader),
      ),
    );
    String? path;
    Object? failure;
    try {
      path = await reader.exportAudio(text);
    } catch (e) {
      failure = e;
    }
    if (!mounted) return;
    navigator.pop();
    if (failure != null) {
      _snack('Salvataggio non riuscito: $failure');
      return;
    }
    if (path == null) return; // annullato
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'audio/wav')],
        title: 'Audio di D. Voce',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([reader, store]),
      builder: (context, _) {
        final hasVoice = store.installed.isNotEmpty;
        return Scaffold(
          appBar: AppBar(
            title: const Text('D. Voce'),
            actions: [
              IconButton(
                tooltip: 'Voci',
                icon: const Icon(Icons.record_voice_over_outlined),
                onPressed: _openVoices,
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                children: [
                  if (!hasVoice) ...[
                    _NoVoiceBanner(onTap: _openVoices),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: reader.active
                        ? _ReadingView(reader: reader)
                        : _EditorView(
                            controller: _text,
                            onPaste: _paste,
                            onOpen: _openFile,
                            onClear: _clear,
                          ),
                  ),
                  const SizedBox(height: 12),
                  _ControlsCard(
                    reader: reader,
                    store: store,
                    hasText: _text.text.trim().isNotEmpty,
                    onListen: _listen,
                    onExport: _export,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'un\'app Dom Studio',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.55),
                        ),
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
                  'Per iniziare scarica una voce italiana (una volta sola, poi funziona offline).',
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorView extends StatelessWidget {
  const _EditorView({
    required this.controller,
    required this.onPaste,
    required this.onOpen,
    required this.onClear,
  });

  final TextEditingController controller;
  final VoidCallback onPaste;
  final VoidCallback onOpen;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final words = RegExp(r'\S+').allMatches(controller.text).length;
    final minutes = words / 150;
    final estimate = words == 0
        ? ''
        : minutes < 1
            ? '$words parole · meno di 1 min'
            : '$words parole · circa ${minutes.round()} min';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 17, height: 1.5),
            decoration: const InputDecoration(
              hintText: 'Scrivi o incolla qui il testo da ascoltare…',
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 2,
                children: [
                  TextButton.icon(
                    onPressed: onPaste,
                    icon: const Icon(Icons.content_paste_rounded, size: 20),
                    label: const Text('Incolla'),
                  ),
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.description_outlined, size: 20),
                    label: const Text('Apri .txt'),
                  ),
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.backspace_outlined, size: 20),
                    label: const Text('Svuota'),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (estimate.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Text(
              estimate,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _ReadingView extends StatelessWidget {
  const _ReadingView({required this.reader});
  final Reader reader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = reader.chunks.length;
    final int i = n == 0 ? 0 : reader.index.clamp(0, n - 1).toInt();
    final current = n == 0 ? '' : reader.chunks[i];
    final next = i + 1 < n ? reader.chunks[i + 1] : null;
    final preparing = reader.state == ReaderState.preparing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                n == 0 ? '' : 'Frase ${i + 1} di $n',
                style: theme.textTheme.labelLarge,
              ),
            ),
            if (preparing)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Preparo la voce…', style: theme.textTheme.labelMedium),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Text(
                  current,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (next != null) ...[
          const SizedBox(height: 10),
          Text(
            'Poi: $next',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
        if (n > 1) _SeekSlider(reader: reader, index: i, count: n),
      ],
    );
  }
}

class _SeekSlider extends StatefulWidget {
  const _SeekSlider({
    required this.reader,
    required this.index,
    required this.count,
  });

  final Reader reader;
  final int index;
  final int count;

  @override
  State<_SeekSlider> createState() => _SeekSliderState();
}

class _SeekSliderState extends State<_SeekSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final max = (widget.count - 1).toDouble();
    final double value = (_drag ?? widget.index.toDouble()).clamp(0.0, max).toDouble();
    return Slider(
      value: value,
      min: 0,
      max: max,
      divisions: widget.count - 1,
      label: 'Frase ${value.round() + 1}',
      onChanged: (v) => setState(() => _drag = v),
      onChangeEnd: (v) {
        setState(() => _drag = null);
        widget.reader.seek(v.round());
      },
    );
  }
}

class _ControlsCard extends StatelessWidget {
  const _ControlsCard({
    required this.reader,
    required this.store,
    required this.hasText,
    required this.onListen,
    required this.onExport,
  });

  final Reader reader;
  final VoiceStore store;
  final bool hasText;
  final VoidCallback onListen;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installed = store.installed;
    final current = reader.voice;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.person_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: installed.isEmpty
                      ? const Text('Nessuna voce installata')
                      : DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: current?.id,
                            items: [
                              for (final v in installed)
                                DropdownMenuItem(
                                  value: v.id,
                                  child: Text(
                                    v.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (id) {
                              final v = voiceById(id);
                              if (v != null) reader.selectVoice(v);
                            },
                          ),
                        ),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.speed_rounded, size: 20),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${reader.speed.toStringAsFixed(1)}×',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: reader.speed,
                    min: 0.6,
                    max: 1.6,
                    divisions: 10,
                    onChanged: reader.setSpeed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (reader.active)
              _PlayerButtons(reader: reader)
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: (hasText && installed.isNotEmpty && !reader.exporting)
                          ? onListen
                          : null,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Ascolta'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                    onPressed: (hasText && installed.isNotEmpty && !reader.exporting)
                        ? onExport
                        : null,
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('Salva audio'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayerButtons extends StatelessWidget {
  const _PlayerButtons({required this.reader});
  final Reader reader;

  @override
  Widget build(BuildContext context) {
    final paused = reader.state == ReaderState.paused;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: 'Frase precedente',
          iconSize: 30,
          onPressed: reader.index > 0 ? reader.previous : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(16),
          ),
          onPressed: reader.togglePause,
          child: Icon(
            paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            size: 34,
          ),
        ),
        IconButton(
          tooltip: 'Frase successiva',
          iconSize: 30,
          onPressed: reader.index + 1 < reader.chunks.length ? reader.next : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          tooltip: 'Ferma',
          iconSize: 30,
          onPressed: reader.stop,
          icon: const Icon(Icons.stop_rounded),
        ),
      ],
    );
  }
}

class _ExportDialog extends StatelessWidget {
  const _ExportDialog({required this.reader});
  final Reader reader;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: ListenableBuilder(
        listenable: reader,
        builder: (context, _) {
          final pct = (reader.exportProgress * 100).round();
          return AlertDialog(
            title: const Text('Creo il file audio'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: reader.exportProgress > 0 ? reader.exportProgress : null,
                ),
                const SizedBox(height: 12),
                Text('$pct% · tieni l\'app aperta, per i testi lunghi serve qualche minuto.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: reader.cancelExport,
                child: const Text('Annulla'),
              ),
            ],
          );
        },
      ),
    );
  }
}
