import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/book.dart';
import '../services/covers.dart';
import '../services/library.dart';
import 'theme.dart';

/// Per scegliere o cambiare la copertina di un libro.
class CoverPage extends StatefulWidget {
  const CoverPage({super.key, required this.book, required this.library});

  final BookMeta book;
  final Library library;

  @override
  State<CoverPage> createState() => _CoverPageState();
}

class _CoverPageState extends State<CoverPage> {
  final CoverSearch _search = CoverSearch();
  late final TextEditingController _query = TextEditingController(
    text: [cleanTitleForSearch(widget.book.title), widget.book.author]
        .where((s) => s.trim().isNotEmpty)
        .join(' – '),
  );
  List<CoverCandidate>? _results;
  bool _searching = false;
  String? _saving;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _search.close();
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final parts = _query.text.split(' – ');
    final title = parts.first.trim();
    final author = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';
    setState(() {
      _searching = true;
      _results = null;
    });
    List<CoverCandidate> list;
    try {
      list = await _search.search(title, author: author);
    } catch (_) {
      list = const [];
    }
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = list;
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pick(CoverCandidate c) async {
    setState(() => _saving = c.url);
    final bytes = await _search.download(c.url);
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _saving = null);
      _snack('Non riesco a scaricare questa copertina, provane un\'altra.');
      return;
    }
    await widget.library.setCover(widget.book, bytes);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _fromGallery() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final bytes = await file.xFile.readAsBytes();
    await widget.library.setCover(widget.book, bytes);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _firstPage() async {
    final f = File(widget.library.firstPagePath(widget.book.id));
    if (!f.existsSync()) return;
    await widget.library.setCover(widget.book, await f.readAsBytes());
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _remove() async {
    await widget.library.removeCover(widget.book);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFirstPage = File(widget.library.firstPagePath(widget.book.id)).existsSync();
    final results = _results;

    return Scaffold(
      appBar: AppBar(title: const Text('Copertina')),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _run(),
                  decoration: InputDecoration(
                    hintText: 'Titolo – autore',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      onPressed: _run,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: _fromGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Dal telefono'),
                    ),
                    if (hasFirstPage)
                      TextButton.icon(
                        onPressed: _firstPage,
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Prima pagina del PDF'),
                      ),
                    if (widget.book.coverVersion > 0)
                      TextButton.icon(
                        onPressed: _remove,
                        icon: const Icon(Icons.hide_image_outlined),
                        label: const Text('Togli copertina'),
                      ),
                  ],
                ),
              ),
            ),
            if (_searching)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (results != null && results.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Nessuna copertina trovata. Prova a scrivere il titolo esatto '
                      'e l\'autore, oppure scegli un\'immagine dal telefono.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              )
            else if (results != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.66,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    childCount: results.length,
                    (context, i) {
                      final c = results[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _saving == null ? () => _pick(c) : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(
                                      c.url,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: Colors.white10,
                                        child: const Icon(Icons.broken_image_outlined),
                                      ),
                                      loadingBuilder: (context, child, progress) => progress == null
                                          ? child
                                          : Container(color: Colors.white10),
                                    ),
                                    if (_saving == c.url)
                                      Container(
                                        color: Colors.black45,
                                        child: const Center(child: CircularProgressIndicator()),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              c.source,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(color: Brand.orange),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
