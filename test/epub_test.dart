import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:d_voce/core/epub.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List buildEpub(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encodeBytes(archive);
}

String xhtml(String body) =>
    '<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml">'
    '<head><title>x</title><style>p{color:red}</style></head><body>$body</body></html>';

void main() {
  test('da HTML a testo', () {
    final t = htmlToText(xhtml('<h1>Titolo</h1><p>Prima&nbsp;riga &egrave; qui<sup>1</sup>.</p>'
        '<p>Seconda<br/>riga &#8220;citata&#8221;.</p>'));
    expect(t.split('\n'), ['Titolo', 'Prima riga è qui.', 'Seconda', 'riga “citata”.']);
  });

  test('legge un EPUB 2 con indice toc.ncx', () {
    final long = List.generate(80, (i) => 'parola$i').join(' ');
    final epub = buildEpub({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
      'OEBPS/content.opf': '''<package><metadata>
          <dc:title>Il libro di prova</dc:title><dc:creator>Mario Rossi</dc:creator></metadata>
          <manifest>
            <item id="cover" href="Text/cover.xhtml" media-type="application/xhtml+xml"/>
            <item id="c1" href="Text/cap1.xhtml" media-type="application/xhtml+xml"/>
            <item id="c2" href="Text/cap%202.xhtml" media-type="application/xhtml+xml"/>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
          </manifest>
          <spine toc="ncx"><itemref idref="cover"/><itemref idref="c1"/><itemref idref="c2"/></spine>
        </package>''',
      'OEBPS/toc.ncx': '''<ncx><navMap>
          <navPoint id="n1"><navLabel><text>Uno: l'inizio</text></navLabel><content src="Text/cap1.xhtml#start"/></navPoint>
          <navPoint id="n2"><navLabel><text>Due</text></navLabel><content src="Text/cap 2.xhtml"/></navPoint>
        </navMap></ncx>''',
      'OEBPS/Text/cover.xhtml': xhtml('<p>Copertina</p>'),
      'OEBPS/Text/cap1.xhtml': xhtml('<h2>Capitolo primo</h2><p>Era una notte buia. $long</p>'),
      'OEBPS/Text/cap 2.xhtml': xhtml('<p>Secondo capitolo. $long</p>'),
    });
    final book = parseEpub(epub);
    expect(book.title, 'Il libro di prova');
    expect(book.author, 'Mario Rossi');
    expect(book.chapters.map((c) => c.title).toList(), ['Uno: l\'inizio', 'Due']);
    // La copertina, troppo corta, si unisce al primo capitolo.
    expect(book.chapters.first.text, startsWith('Copertina\nCapitolo primo\nEra una notte buia.'));
    expect(book.chapters.last.text, startsWith('Secondo capitolo.'));
  });

  test('legge un EPUB 3 con indice nav', () {
    final long = List.generate(80, (i) => 'w$i').join(' ');
    final epub = buildEpub({
      'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf': '''<package><metadata><dc:title>Nav</dc:title></metadata><manifest>
          <item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/>
          <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
          <item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>
        </manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>''',
      'nav.xhtml': xhtml('<nav><ol><li><a href="a.xhtml">Alfa</a></li><li><a href="b.xhtml#x">Beta</a></li></ol></nav>'),
      'a.xhtml': xhtml('<p>Testo A. $long</p>'),
      'b.xhtml': xhtml('<p>Testo B. $long</p>'),
    });
    final book = parseEpub(epub);
    expect(book.chapters.map((c) => c.title).toList(), ['Alfa', 'Beta']);
  });

  test('un file che non è un EPUB dà un errore chiaro', () {
    expect(() => parseEpub(Uint8List.fromList([1, 2, 3])), throwsA(isA<EpubException>()));
  });
}
