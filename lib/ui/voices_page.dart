import 'package:flutter/material.dart';

import '../core/voice_catalog.dart';
import '../services/reader.dart';
import '../services/voice_store.dart';

class VoicesPage extends StatelessWidget {
  const VoicesPage({super.key, required this.store, required this.reader});

  final VoiceStore store;
  final Reader reader;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voci')),
      body: ListenableBuilder(
        listenable: Listenable.merge([store, reader]),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(
                'Le voci si scaricano una volta sola e poi funzionano senza internet. '
                'Conviene usare il Wi‑Fi.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              for (final v in kVoices) ...[
                _VoiceCard(voice: v, store: store, reader: reader),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({
    required this.voice,
    required this.store,
    required this.reader,
  });

  final VoiceInfo voice;
  final VoiceStore store;
  final Reader reader;

  Future<void> _download(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.download(voice);
      if (store.isInstalled(voice)) {
        if (reader.voice == null || store.installed.length == 1) {
          await reader.selectVoice(voice);
        }
        messenger.showSnackBar(
          SnackBar(content: Text('${voice.name} è pronta.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Download non riuscito: $e')),
      );
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminare ${voice.name}?'),
        content: const Text('Potrai riscaricarla quando vuoi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (reader.active) await reader.stop();
    await store.delete(voice);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = store.status(voice);
    final selected = reader.voice?.id == voice.id;

    Widget actions;
    switch (status) {
      case VoiceStatus.notInstalled:
        actions = FilledButton.icon(
          onPressed: () => _download(context),
          icon: const Icon(Icons.download_rounded),
          label: Text('Scarica · ${voice.sizeMb} MB'),
        );
      case VoiceStatus.downloading:
        final pr = store.progress(voice);
        actions = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: pr),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    pr == null ? 'Download…' : 'Download ${(pr * 100).round()}%',
                  ),
                ),
                TextButton(
                  onPressed: () => store.cancel(voice),
                  child: const Text('Annulla'),
                ),
              ],
            ),
          ],
        );
      case VoiceStatus.installing:
        actions = const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 6),
            Text('Installazione… può richiedere un minuto.'),
          ],
        );
      case VoiceStatus.installed:
        actions = Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (!selected)
              FilledButton(
                onPressed: () => reader.selectVoice(voice),
                child: const Text('Usa questa'),
              ),
            OutlinedButton.icon(
              onPressed: reader.active ? reader.stop : () => reader.preview(voice),
              icon: Icon(
                reader.active ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(reader.active ? 'Ferma' : 'Prova'),
            ),
            TextButton(
              onPressed: () => _delete(context),
              child: const Text('Elimina'),
            ),
          ],
        );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    voice.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (selected)
                  Chip(
                    label: const Text('In uso'),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(voice.description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            actions,
          ],
        ),
      ),
    );
  }
}
