import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'services/audio_handler.dart';
import 'services/edge_bridge.dart';
import 'services/library.dart';
import 'services/reader.dart';
import 'services/voice_store.dart';
import 'ui/library_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = VoiceStore();
  final library = Library();
  await Future.wait([store.init(), library.init()]);
  final reader = Reader(store, library);
  await reader.init();
  if (Platform.isAndroid) {
    final edge = EdgeBridge(library);
    edge.onPosition = reader.syncPosition;
    reader.edge = edge;
    await edge.init();
  }

  // Notifica e comandi dalla schermata di blocco; tiene viva la lettura a
  // schermo spento. Se non parte, l'app funziona lo stesso.
  try {
    await AudioService.init(
      builder: () => DVoceAudioHandler(reader),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.dvoce.d_voce.lettura',
        androidNotificationChannelName: 'Lettura',
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e) {
    debugPrint('AudioService non disponibile: $e');
  }

  runApp(DVoceApp(store: store, reader: reader, library: library));
}

class DVoceApp extends StatelessWidget {
  const DVoceApp({
    super.key,
    required this.store,
    required this.reader,
    required this.library,
  });

  final VoiceStore store;
  final Reader reader;
  final Library library;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'D. Voce',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // Come nelle app di audiolibri: tema scuro, copertine in primo piano.
      themeMode: ThemeMode.dark,
      home: LibraryPage(store: store, reader: reader, library: library),
    );
  }
}
