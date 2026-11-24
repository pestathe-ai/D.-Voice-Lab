import 'package:flutter/material.dart';

import '../core/voice_catalog.dart';
import '../services/reader.dart';
import '../services/voice_store.dart';
import 'theme.dart';
import 'widgets.dart';

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
          final theme = Theme.of(context);
          final natural = store.isPackInstalled(kSupertonicPack);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Text(
                'Le voci si scaricano una volta sola e poi funzionano senza internet, '
                'gratis e senza limiti. Conviene usare il Wi‑Fi.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _PackCard(pack: kSupertonicPack, store: store, reader: reader, recommended: true),
              if (natural) ...[
                const SizedBox(height: 12),
                for (final v in voicesOfPack(kSupertonicPack)) ...[
                  _VoiceTile(voice: v, store: store, reader: reader),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                _QualityCard(reader: reader),
              ],
              const SizedBox(height: 24),
              Text('Voci leggere', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Meno naturali ma più piccole e veloci, utili sui telefoni meno potenti. '
                'Leggono solo in italiano.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final pack in [kPaolaPack, kRiccardoPack]) ...[
                _PackCard(pack: pack, store: store, reader: reader),
                if (store.isPackInstalled(pack))
                  for (final v in voicesOfPack(pack)) ...[
                    const SizedBox(height: 8),
                    _VoiceTile(voice: v, store: store, reader: reader),
                  ],
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.pack,
    required this.store,
    required this.reader,
    this.recommended = false,
  });

  final VoicePack pack;
  final VoiceStore store;
  final Reader reader;
  final bool recommended;

  Future<void> _download(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.download(pack);
      if (store.isPackInstalled(pack)) {
        final current = reader.defaultVoice;
        // La prima volta si sceglie in automatico una voce del pacchetto.
        if (current == null || (pack == kSupertonicPack && !current.natural)) {
          final v = voiceById(kDefaultVoiceId);
          await reader.selectDefaultVoice(
            pack == kSupertonicPack && v != null ? v : voicesOfPack(pack).first,
          );
        }
        messenger.showSnackBar(
          SnackBar(content: Text('${pack.title}: pronte!')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Download non riuscito: $e')),
      );
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirm(
      context,
      title: 'Eliminare "${pack.title}"?',
      message: 'Libererai ${pack.sizeMb} MB circa. Potrai riscaricarle quando vuoi.',
      action: 'Elimina',
    );
    if (!ok) return;
    if (reader.active) await reader.stop();
    await store.delete(pack);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = store.status(pack);

    Widget actions;
    switch (status) {
      case VoiceStatus.notInstalled:
        actions = FilledButton.icon(
          onPressed: () => _download(context),
          icon: const Icon(Icons.download_rounded),
          label: Text('Scarica · ${pack.sizeMb} MB'),
        );
      case VoiceStatus.downloading:
        final pr = store.progress(pack);
        actions = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: pr),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(pr == null ? 'Download…' : 'Download ${(pr * 100).round()}%'),
                ),
                TextButton(
                  onPressed: () => store.cancel(pack),
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
            Text('Installazione… può richiedere un paio di minuti.'),
          ],
        );
      case VoiceStatus.installed:
        actions = Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
            const SizedBox(width: 6),
            const Expanded(child: Text('Installate')),
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
                    pack.title,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (recommended)
                  Chip(
                    label: const Text('Consigliate'),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: Brand.orange.withValues(alpha: 0.22),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(pack.description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            actions,
          ],
        ),
      ),
    );
  }
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({required this.voice, required this.store, required this.reader});

  final VoiceInfo voice;
  final VoiceStore store;
  final Reader reader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = reader.voice?.id == voice.id;
    final previewing = reader.previewingVoiceId == voice.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(
                voice.gender == VoiceGender.female ? Icons.face_3_outlined : Icons.face_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          voice.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.check_circle_rounded, size: 18, color: Brand.orange),
                      ],
                    ],
                  ),
                  Text(voice.description, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              tooltip: previewing ? 'Ferma' : 'Ascolta',
              onPressed: previewing ? reader.stopPreview : () => reader.preview(voice),
              icon: Icon(previewing ? Icons.stop_circle_outlined : Icons.play_circle_outline_rounded),
            ),
            if (!selected)
              TextButton(
                onPressed: () => reader.selectVoice(voice),
                child: const Text('Usa'),
              ),
          ],
        ),
      ),
    );
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({required this.reader});
  final Reader reader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Qualità delle voci naturali', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '"Alta" rende la voce ancora più pulita, ma il telefono impiega più '
              'tempo a prepararla. Se la lettura fa delle pause, usa "Normale".',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            SegmentedButton<VoiceQuality>(
              segments: const [
                ButtonSegment(value: VoiceQuality.normal, label: Text('Normale')),
                ButtonSegment(value: VoiceQuality.high, label: Text('Alta')),
              ],
              selected: {reader.quality},
              onSelectionChanged: (s) => reader.setQuality(s.first),
            ),
          ],
        ),
      ),
    );
  }
}
