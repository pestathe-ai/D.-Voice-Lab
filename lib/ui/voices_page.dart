import 'package:flutter/material.dart';

import '../core/languages.dart';
import '../core/voice_catalog.dart';
import '../services/reader.dart';
import '../services/system_tts.dart';
import '../services/voice_store.dart';
import 'theme.dart';
import 'widgets.dart';

class VoicesPage extends StatefulWidget {
  const VoicesPage({super.key, required this.store, required this.reader});

  final VoiceStore store;
  final Reader reader;

  @override
  State<VoicesPage> createState() => _VoicesPageState();
}

class _VoicesPageState extends State<VoicesPage> {
  Reader get reader => widget.reader;
  VoiceStore get store => widget.store;
  bool _showOffline = false;

  @override
  void initState() {
    super.initState();
    reader.refreshSystemVoices(force: true);
  }

  @override
  void dispose() {
    final r = reader;
    // Fuori dal dispose: la prova si ferma appena si esce dalla pagina.
    Future.microtask(r.stopPreview);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voci')),
      body: ListenableBuilder(
        listenable: Listenable.merge([store, reader]),
        builder: (context, _) {
          final theme = Theme.of(context);
          final lang = reader.book?.lang ?? 'it';
          final sys = reader.systemVoices;
          final installedSys = sys.where((v) => v.installed).toList();
          final missingSys = sys.where((v) => !v.installed).toList();
          final engines = reader.engines;
          final offlineInstalled = kPacks.any(store.isPackInstalled);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              if (reader.edge != null) ...[
                Text(
                  'Consigliata',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                _VoiceTile(choice: VoiceChoice.edge(), reader: reader),
                const SizedBox(height: 24),
              ],
              Text(
                'Voci del telefono · ${languageName(lang)}',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Sono le voci di Google (o del produttore del telefono): accento '
                'italiano vero, gratis e senza limiti. Quelle con la nuvola sono le più '
                'naturali ma usano internet; le altre funzionano anche offline.',
                style: theme.textTheme.bodySmall,
              ),
              if (engines.length > 1) ...[
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Motore vocale'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isDense: true,
                      isExpanded: true,
                      value: engines.any((e) => e['name'] == reader.engine) ? reader.engine : null,
                      items: [
                        for (final e in engines)
                          DropdownMenuItem(value: e['name'], child: Text(e['label'] ?? e['name']!)),
                      ],
                      onChanged: (v) {
                        if (v != null) reader.setEngine(v);
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (!reader.systemVoicesLoaded)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (installedSys.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Non trovo voci in ${languageName(lang).toLowerCase()} sul telefono. '
                      'Apri Impostazioni › Accessibilità (o Sistema) › Sintesi vocale, '
                      'scegli "Servizi di riconoscimento vocale di Google" e installa i dati '
                      'vocali della lingua. Poi torna qui.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                )
              else
                for (final v in installedSys) ...[
                  _VoiceTile(choice: VoiceChoice.system(v), reader: reader, system: v),
                  const SizedBox(height: 8),
                ],
              if (missingSys.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    'Ci sono altre ${missingSys.length} voci da scaricare nelle impostazioni '
                    'del telefono (Sintesi vocale › Google › Installa dati vocali).',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => reader.refreshSystemVoices(force: true),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Aggiorna elenco'),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Voci scaricabili nell\'app', style: theme.textTheme.titleMedium),
                subtitle: const Text('Funzionano sempre offline, ma sono meno naturali in italiano.'),
                trailing: Icon(_showOffline ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                onTap: () => setState(() => _showOffline = !_showOffline),
              ),
              if (_showOffline || offlineInstalled)
                for (final pack in kPacks) ...[
                  _PackCard(pack: pack, store: store, reader: reader),
                  if (store.isPackInstalled(pack))
                    for (final v in voicesOfPack(pack)) ...[
                      const SizedBox(height: 8),
                      _VoiceTile(choice: VoiceChoice.offline(v), reader: reader),
                    ],
                  const SizedBox(height: 12),
                ],
              if (offlineInstalled) _QualityCard(reader: reader),
            ],
          );
        },
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({required this.pack, required this.store, required this.reader});

  final VoicePack pack;
  final VoiceStore store;
  final Reader reader;

  Future<void> _download(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.download(pack);
      if (store.isPackInstalled(pack)) {
        messenger.showSnackBar(SnackBar(content: Text('${pack.title}: pronte!')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Download non riuscito: $e')));
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
    if (reader.active && reader.voice?.offline?.pack.id == pack.id) await reader.stop();
    await store.delete(pack);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = store.status(pack);

    Widget actions;
    switch (status) {
      case VoiceStatus.notInstalled:
        actions = OutlinedButton.icon(
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
                Expanded(child: Text(pr == null ? 'Download…' : 'Download ${(pr * 100).round()}%')),
                TextButton(onPressed: () => store.cancel(pack), child: const Text('Annulla')),
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
            Text('Installazione…'),
          ],
        );
      case VoiceStatus.installed:
        actions = Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
            const SizedBox(width: 6),
            const Expanded(child: Text('Installate')),
            TextButton(onPressed: () => _delete(context), child: const Text('Elimina')),
          ],
        );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(pack.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(pack.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            actions,
          ],
        ),
      ),
    );
  }
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({required this.choice, required this.reader, this.system});

  final VoiceChoice choice;
  final Reader reader;
  final SystemVoice? system;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = reader.voice?.id == choice.id;
    final previewing = reader.previewingVoiceId == choice.id;
    final IconData icon;
    if (choice.isEdge) {
      icon = Icons.auto_awesome_rounded;
    } else if (system != null) {
      icon = system!.network ? Icons.cloud_outlined : Icons.phone_android_rounded;
    } else {
      icon = choice.offline?.gender == VoiceGender.female ? Icons.face_3_outlined : Icons.face_outlined;
    }
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selected ? const BorderSide(color: Brand.orange, width: 1.5) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Brand.orange.withValues(alpha: 0.15),
              child: Icon(icon, color: Brand.orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    choice.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(choice.description, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (!choice.isEdge)
              IconButton(
                tooltip: previewing ? 'Ferma' : 'Ascolta',
                onPressed: previewing ? reader.stopPreview : () => reader.preview(choice),
                icon: Icon(previewing ? Icons.stop_circle_outlined : Icons.play_circle_outline_rounded),
              ),
            if (selected)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.check_rounded, color: Brand.orange),
              )
            else
              TextButton(onPressed: () => reader.selectVoice(choice), child: const Text('Usa')),
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
            Text('Qualità delle voci scaricate', style: theme.textTheme.titleSmall),
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
