import 'package:flutter/material.dart';

import 'services/reader.dart';
import 'services/voice_store.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = VoiceStore();
  await store.init();
  final reader = Reader(store);
  await reader.init();
  runApp(DVoceApp(store: store, reader: reader));
}

class DVoceApp extends StatelessWidget {
  const DVoceApp({super.key, required this.store, required this.reader});

  final VoiceStore store;
  final Reader reader;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'D. Voce',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: HomePage(store: store, reader: reader),
    );
  }
}
