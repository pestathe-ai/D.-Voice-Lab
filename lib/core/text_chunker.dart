/// Divide un testo in frasi da leggere una alla volta.
///
/// Ogni pezzo è abbastanza corto da essere sintetizzato in fretta (così
/// l'audio parte subito) ma non così corto da spezzare il ritmo:
/// - si rispettano i paragrafi (un a capo non viene mai unito al successivo);
/// - si divide dopo . ! ? … ; :
/// - le frasi troppo lunghe vengono spezzate alle virgole, poi agli spazi;
/// - le frasi molto brevi vengono unite alla successiva.
library;

const int kMaxChunk = 260;
const int kMinChunk = 30;

final RegExp _sentenceEnd = RegExp(r'(?<=[.!?…;:])\s+');
final RegExp _commaEnd = RegExp(r'(?<=[,—–])\s+');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _hasWord = RegExp(r'[\p{L}\p{N}]', unicode: true);

List<String> splitIntoChunks(
  String text, {
  int maxLen = kMaxChunk,
  int minLen = kMinChunk,
}) {
  final result = <String>[];
  final paragraphs = text.replaceAll('\r\n', '\n').split('\n');

  for (final raw in paragraphs) {
    final para = raw.replaceAll(_spaces, ' ').trim();
    if (para.isEmpty) continue;

    final pieces = <String>[];
    for (final sentence in para.split(_sentenceEnd)) {
      final s = sentence.trim();
      if (s.isEmpty) continue;
      pieces.addAll(_splitLong(s, maxLen));
    }

    var buffer = '';
    for (final piece in pieces) {
      if (buffer.isEmpty) {
        buffer = piece;
      } else if (buffer.length < minLen &&
          buffer.length + 1 + piece.length <= maxLen) {
        buffer = '$buffer $piece';
      } else {
        result.add(buffer);
        buffer = piece;
      }
    }
    if (buffer.isNotEmpty) result.add(buffer);
  }

  return result.where((c) => _hasWord.hasMatch(c)).toList();
}

List<String> _splitLong(String s, int maxLen) {
  if (s.length <= maxLen) return [s];

  final out = <String>[];
  for (final part in _pack(s.split(_commaEnd), maxLen)) {
    if (part.length <= maxLen) {
      out.add(part);
      continue;
    }
    for (final words in _pack(part.split(' '), maxLen)) {
      if (words.length <= maxLen) {
        out.add(words);
      } else {
        // Una "parola" lunghissima (es. un link): taglio netto.
        for (var i = 0; i < words.length; i += maxLen) {
          final end = i + maxLen < words.length ? i + maxLen : words.length;
          out.add(words.substring(i, end));
        }
      }
    }
  }
  return out;
}

/// Unisce i pezzi con uno spazio finché non si supera [maxLen].
List<String> _pack(List<String> parts, int maxLen) {
  final out = <String>[];
  var current = '';
  for (final raw in parts) {
    final p = raw.trim();
    if (p.isEmpty) continue;
    if (current.isEmpty) {
      current = p;
    } else if (current.length + 1 + p.length <= maxLen) {
      current = '$current $p';
    } else {
      out.add(current);
      current = p;
    }
  }
  if (current.isNotEmpty) out.add(current);
  return out;
}
