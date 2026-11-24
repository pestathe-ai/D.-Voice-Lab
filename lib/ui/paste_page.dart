import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/book_import.dart';

/// Per incollare un testo e aggiungerlo alla libreria.
class PastePage extends StatefulWidget {
  const PastePage({super.key});

  @override
  State<PastePage> createState() => _PastePageState();
}

class _PastePageState extends State<PastePage> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (!mounted) return;
    if (t == null || t.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Negli appunti non c\'è testo.')),
      );
      return;
    }
    _text.text = _text.text.trim().isEmpty ? t : '${_text.text}\n\n$t';
  }

  Future<void> _done() async {
    setState(() => _busy = true);
    try {
      final book = await importPastedText(_title.text, _text.text);
      if (mounted) Navigator.pop(context, book);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = RegExp(r'\S+').allMatches(_text.text).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Incolla un testo')),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Titolo (facoltativo)'),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                  decoration: const InputDecoration(
                    hintText: 'Scrivi o incolla qui il testo da ascoltare…',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _paste,
                    icon: const Icon(Icons.content_paste_rounded, size: 20),
                    label: const Text('Incolla'),
                  ),
                  const Spacer(),
                  if (words > 0)
                    Text('$words parole', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: words == 0 || _busy ? null : _done,
                icon: const Icon(Icons.library_add_rounded),
                label: const Text('Aggiungi alla libreria'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
