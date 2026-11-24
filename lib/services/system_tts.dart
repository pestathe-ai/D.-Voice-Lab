import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Una voce del motore di sintesi del telefono (Google, Samsung…).
class SystemVoice {
  const SystemVoice({
    required this.name,
    required this.locale,
    required this.network,
    required this.quality,
    required this.installed,
    required this.label,
  });

  /// Nome tecnico, es. "it-it-x-itd-network".
  final String name;

  /// Lingua, es. "it-IT".
  final String locale;

  /// true se per parlare usa internet (di solito sono le più naturali).
  final bool network;

  /// Qualità dichiarata dal motore (300 normale … 500 altissima).
  final int quality;

  /// false se la voce va ancora scaricata nelle impostazioni del telefono.
  final bool installed;

  /// Nome da mostrare, es. "Voce 2".
  final String label;

  String get id => 'sys:$name';

  String get description {
    final parts = <String>[
      network ? 'Più naturale · usa internet' : 'Funziona senza internet',
      if (quality >= 400) 'alta qualità',
      if (!installed) 'da scaricare nelle impostazioni del telefono',
    ];
    return parts.join(' · ');
  }
}

int _qualityValue(String? q) {
  switch (q) {
    case 'very high':
    case 'veryHigh':
    case 'VERY_HIGH':
      return 500;
    case 'high':
    case 'HIGH':
      return 400;
    case 'low':
    case 'LOW':
      return 200;
    case 'very low':
    case 'VERY_LOW':
      return 100;
    default:
      return 300;
  }
}

/// Trasforma l'elenco grezzo delle voci in voci della lingua [lang]
/// (es. "it"), ordinate con le migliori in cima e con nomi semplici.
@visibleForTesting
List<SystemVoice> parseSystemVoices(List<Object?> raw, String lang) {
  final list = <SystemVoice>[];
  final seen = <String>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final name = item['name']?.toString() ?? '';
    final locale = (item['locale']?.toString() ?? '').replaceAll('_', '-');
    if (name.isEmpty || !locale.toLowerCase().startsWith(lang.toLowerCase())) continue;
    if (!seen.add(name)) continue;
    final features = item['features']?.toString() ?? '';
    final network = item['network_required']?.toString() == '1' ||
        name.toLowerCase().contains('network');
    list.add(SystemVoice(
      name: name,
      locale: locale,
      network: network,
      quality: _qualityValue(item['quality']?.toString()),
      installed: !features.contains('notInstalled'),
      label: '',
    ));
  }
  // Prima le voci installate, poi quelle di rete (più naturali), poi per qualità.
  list.sort((a, b) {
    if (a.installed != b.installed) return a.installed ? -1 : 1;
    if (a.network != b.network) return a.network ? -1 : 1;
    if (a.quality != b.quality) return b.quality.compareTo(a.quality);
    return a.name.compareTo(b.name);
  });
  return [
    for (var i = 0; i < list.length; i++)
      SystemVoice(
        name: list[i].name,
        locale: list[i].locale,
        network: list[i].network,
        quality: list[i].quality,
        installed: list[i].installed,
        label: 'Voce ${i + 1}',
      ),
  ];
}

/// Il motore vocale del telefono: legge le frasi una dopo l'altra mettendone
/// sempre un paio in coda, così tra una frase e l'altra non ci sono pause.
class SystemTts {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  /// Chiamata ogni volta che il telefono finisce di leggere una frase.
  void Function()? onUtteranceDone;

  /// Chiamata quando il motore segnala un errore.
  void Function(String message)? onError;

  List<Map<String, String>> engines = const [];
  String? engine;

  Future<void> init() async {
    if (_ready) return;
    _tts.setCompletionHandler(() => onUtteranceDone?.call());
    _tts.setErrorHandler((msg) => onError?.call('$msg'));
    try {
      await _tts.awaitSpeakCompletion(false);
      await _tts.setQueueMode(1); // QUEUE_ADD: le frasi si accodano
    } catch (_) {}
    _ready = true;
    await loadEngines();
  }

  Future<void> loadEngines() async {
    try {
      final raw = await _tts.getEngines;
      final def = await _tts.getDefaultEngine;
      engines = [
        for (final e in (raw as List? ?? const []))
          {'name': e.toString(), 'label': engineLabel(e.toString())},
      ];
      engine ??= def?.toString();
    } catch (_) {
      engines = const [];
    }
  }

  static String engineLabel(String pkg) {
    if (pkg.contains('google')) return 'Google';
    if (pkg.contains('samsung')) return 'Samsung';
    if (pkg.contains('huawei')) return 'Huawei';
    if (pkg.contains('xiaomi') || pkg.contains('miui')) return 'Xiaomi';
    return pkg;
  }

  Future<void> setEngine(String name) async {
    engine = name;
    try {
      await _tts.setEngine(name);
      // Dopo il cambio di motore le impostazioni vanno ripetute.
      await _tts.setQueueMode(1);
    } catch (_) {}
  }

  Future<List<SystemVoice>> voices(String lang) async {
    await init();
    try {
      final raw = await _tts.getVoices;
      return parseSystemVoices((raw as List?) ?? const [], lang);
    } catch (_) {
      return const [];
    }
  }

  Future<void> configure(SystemVoice voice, double speed) async {
    await init();
    try {
      await _tts.setLanguage(voice.locale);
    } catch (_) {}
    await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
    // Per flutter_tts 0.5 è la velocità normale del telefono.
    await _tts.setSpeechRate(speed * 0.5);
    await _tts.setPitch(1.0);
  }

  /// Mette una frase in coda.
  Future<void> enqueue(String text) async {
    await _tts.speak(text, focus: true);
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
