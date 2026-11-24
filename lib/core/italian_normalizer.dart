/// Prepara un testo italiano per la voce: scrive in lettere numeri,
/// percentuali, orari, prezzi, abbreviazioni comuni e numeri romani dei
/// capitoli. Le voci naturali leggono molto meglio "millenovecento" che
/// "1900".
library;

const _units = [
  'zero', 'uno', 'due', 'tre', 'quattro', 'cinque', 'sei', 'sette', 'otto',
  'nove', 'dieci', 'undici', 'dodici', 'tredici', 'quattordici', 'quindici',
  'sedici', 'diciassette', 'diciotto', 'diciannove',
];

const _tens = [
  '', '', 'venti', 'trenta', 'quaranta', 'cinquanta', 'sessanta', 'settanta',
  'ottanta', 'novanta',
];

String _under100(int n) {
  if (n < 20) return _units[n];
  final t = _tens[n ~/ 10];
  final u = n % 10;
  if (u == 0) return t;
  if (u == 1 || u == 8) return t.substring(0, t.length - 1) + _units[u];
  return t + _units[u];
}

String _under1000(int n) {
  final h = n ~/ 100;
  final r = n % 100;
  final hs = h == 0 ? '' : (h == 1 ? 'cento' : '${_units[h]}cento');
  if (r == 0) return h == 0 ? 'zero' : hs;
  final rs = _under100(r);
  if (h == 0) return rs;
  // cento + ottanta = centottanta, cento + otto = centotto
  if (rs.startsWith('o')) return hs.substring(0, hs.length - 1) + rs;
  return hs + rs;
}

String _raw(int n) {
  if (n < 1000) return _under1000(n);
  if (n < 1000000) {
    final th = n ~/ 1000;
    final r = n % 1000;
    final ths = th == 1 ? 'mille' : '${_under1000(th)}mila';
    return r == 0 ? ths : ths + _under1000(r);
  }
  if (n < 1000000000) {
    final m = n ~/ 1000000;
    final r = n % 1000000;
    final ms = m == 1 ? 'un milione' : '${_raw(m)} milioni';
    return r == 0 ? ms : '$ms ${_raw(r)}';
  }
  final b = n ~/ 1000000000;
  final r = n % 1000000000;
  final bs = b == 1 ? 'un miliardo' : '${_raw(b)} miliardi';
  return r == 0 ? bs : '$bs ${_raw(r)}';
}

/// Un numero intero scritto in lettere, es. 1984 → "millenovecentottantaquattro".
String numberToItalian(int n) {
  if (n < 0) return 'meno ${numberToItalian(-n)}';
  final s = _raw(n);
  // L'accento cade solo sul "tre" finale dei numeri composti: ventitré.
  final lastWord = s.substring(s.lastIndexOf(' ') + 1);
  if (n > 10 && n % 10 == 3 && n % 100 != 13 && lastWord != 'tre' && s.endsWith('tre')) {
    return '${s.substring(0, s.length - 3)}tré';
  }
  return s;
}

const _ordinals = [
  '', 'primo', 'secondo', 'terzo', 'quarto', 'quinto', 'sesto', 'settimo',
  'ottavo', 'nono', 'decimo',
];

/// Valore di un numero romano (I..MMMM), oppure null se non lo è.
int? romanToInt(String s) {
  final r = s.toUpperCase();
  if (r.isEmpty || !RegExp(r'^M{0,4}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$').hasMatch(r)) {
    return null;
  }
  const v = {'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100, 'D': 500, 'M': 1000};
  var total = 0;
  for (var i = 0; i < r.length; i++) {
    final cur = v[r[i]]!;
    final next = i + 1 < r.length ? v[r[i + 1]]! : 0;
    total += cur < next ? -cur : cur;
  }
  return total == 0 ? null : total;
}

// Abbreviazioni: l'ordine conta (le più lunghe prima).
final List<(RegExp, String)> _abbreviations = [
  (RegExp(r'\bDott\.ssa\b'), 'Dottoressa'),
  (RegExp(r'\bdott\.ssa\b'), 'dottoressa'),
  (RegExp(r'\bProf\.ssa\b'), 'Professoressa'),
  (RegExp(r'\bprof\.ssa\b'), 'professoressa'),
  (RegExp(r'\bSig\.ra\b'), 'Signora'),
  (RegExp(r'\bsig\.ra\b'), 'signora'),
  (RegExp(r'\bSig\.na\b'), 'Signorina'),
  (RegExp(r'\bsig\.na\b'), 'signorina'),
  (RegExp(r'\bSigg\.'), 'Signori'),
  (RegExp(r'\bDott\.'), 'Dottor'),
  (RegExp(r'\bdott\.'), 'dottor'),
  (RegExp(r'\bSig\.'), 'Signor'),
  (RegExp(r'\bsig\.'), 'signor'),
  (RegExp(r'\bProf\.'), 'Professor'),
  (RegExp(r'\bprof\.'), 'professor'),
  (RegExp(r'\bAvv\.'), 'Avvocato'),
  (RegExp(r'\bavv\.'), 'avvocato'),
  (RegExp(r'\bIng\.'), 'Ingegner'),
  (RegExp(r'\bing\.'), 'ingegner'),
  (RegExp(r'\bOn\.(?=\s+[A-Z])'), 'Onorevole'),
  (RegExp(r'\bS\.p\.A\.'), 'esse pi a'),
  (RegExp(r'\bp\.es\.'), 'per esempio'),
  (RegExp(r'\bes\.(?=\s)'), 'esempio'),
  (RegExp(r'\becc\.'), 'eccetera'),
  (RegExp(r'\betc\.'), 'eccetera'),
  (RegExp(r'\bpagg\.(?=\s*\d)'), 'pagine'),
  (RegExp(r'\bpag\.(?=\s*\d)'), 'pagina'),
  (RegExp(r'\bp\.(?=\s*\d)'), 'pagina'),
  (RegExp(r'\b[Cc]ap\.(?=\s*\d)'), 'capitolo'),
  (RegExp(r'\b[Nn]\.(?=\s*\d)'), 'numero'),
  (RegExp(r'\b[Aa]rt\.(?=\s*\d)'), 'articolo'),
  (RegExp(r'\b[Vv]ol\.(?=\s*\d)'), 'volume'),
  (RegExp(r'\ba\.\s?C\.'), 'avanti Cristo'),
  (RegExp(r'\bd\.\s?C\.'), 'dopo Cristo'),
  (RegExp(r'\bkm/h\b'), 'chilometri orari'),
  (RegExp(r'(?<=\d)\s?km\b'), ' chilometri'),
  (RegExp(r'(?<=\d)\s?kg\b'), ' chili'),
  (RegExp(r'(?<=\d)\s?cm\b'), ' centimetri'),
  (RegExp(r'(?<=\d)\s?mm\b'), ' millimetri'),
  (RegExp(r'(?<=\d)\s?ml\b'), ' millilitri'),
  (RegExp(r'(?<=\d)\s?m\b'), ' metri'),
  (RegExp(r'(?<=\d)\s?g\b'), ' grammi'),
  (RegExp(r'(?<=\d)\s?°C\b'), ' gradi'),
  (RegExp(r'&'), ' e '),
];

final RegExp _romanHeading = RegExp(
  r'\b(Capitolo|CAPITOLO|capitolo|Parte|PARTE|parte|Libro|LIBRO|Atto|ATTO|Scena|SCENA|Canto|CANTO|Volume|VOLUME|Sezione|SEZIONE|Cap\.)\s+([IVXLCDM]+)\b',
);
final RegExp _ordinal = RegExp(r'\b(\d{1,2})\s?[°ºª](?![CF])');
final RegExp _percent = RegExp(r'(\d+(?:,\d+)?)\s?%');
final RegExp _money = RegExp(r'(?:€\s?(\d+)(?:,(\d{2}))?|(\d+)(?:,(\d{2}))?\s?(?:€|euro\b))');
final RegExp _time = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');
final RegExp _thousands = RegExp(r'\b\d{1,3}(?:\.\d{3})+\b');
final RegExp _decimal = RegExp(r'\b(\d+),(\d+)\b');
final RegExp _integer = RegExp(r'\d+');

String _readInt(String digits) {
  if (digits.length > 12) return digits.split('').map((d) => _units[int.parse(d)]).join(' ');
  // Gli zeri davanti (es. "007") si leggono cifra per cifra.
  if (digits.length > 1 && digits.startsWith('0')) {
    return digits.split('').map((d) => _units[int.parse(d)]).join(' ');
  }
  return numberToItalian(int.parse(digits));
}

String _readDecimal(String intPart, String frac) =>
    '${_readInt(intPart)} virgola ${_readInt(frac)}';

/// Applica tutte le regole a una frase.
String normalizeItalian(String input) {
  var s = input;

  for (final (re, rep) in _abbreviations) {
    s = s.replaceAll(re, rep);
  }

  s = s.replaceAllMapped(_romanHeading, (m) {
    final n = romanToInt(m.group(2)!);
    final word = m.group(1)! == 'Cap.' ? 'Capitolo' : m.group(1)!;
    return n == null ? m.group(0)! : '$word ${numberToItalian(n)}';
  });

  s = s.replaceAllMapped(_ordinal, (m) {
    final n = int.parse(m.group(1)!);
    return n >= 1 && n <= 10 ? _ordinals[n] : '${_readInt(m.group(1)!)}esimo';
  });

  s = s.replaceAllMapped(_thousands, (m) => m.group(0)!.replaceAll('.', ''));

  s = s.replaceAllMapped(_money, (m) {
    final euros = m.group(1) ?? m.group(3)!;
    final cents = m.group(2) ?? m.group(4);
    final e = euros == '1' ? 'un euro' : '${_readInt(euros)} euro';
    if (cents == null || cents == '00') return e;
    return '$e e ${_readInt(cents.startsWith('0') ? cents.substring(1) : cents)}';
  });

  s = s.replaceAllMapped(_percent, (m) {
    final v = m.group(1)!;
    final parts = v.split(',');
    final words = parts.length == 2 ? _readDecimal(parts[0], parts[1]) : _readInt(v);
    return '$words per cento';
  });

  s = s.replaceAllMapped(_time, (m) {
    final h = _readInt(int.parse(m.group(1)!).toString());
    final min = int.parse(m.group(2)!);
    return min == 0 ? h : '$h e ${_readInt(min.toString())}';
  });

  s = s.replaceAllMapped(_decimal, (m) => _readDecimal(m.group(1)!, m.group(2)!));

  s = s.replaceAllMapped(_integer, (m) => _readInt(m.group(0)!));

  return s.replaceAll(RegExp(r' {2,}'), ' ').trim();
}

/// Abbreviazioni dopo le quali un punto NON chiude la frase.
final RegExp kNoSentenceEnd = RegExp(
  r'(?:\b(?:[Dd]ott|[Ss]ig|[Ss]igg|[Pp]rof|[Aa]vv|[Ii]ng|[Oo]n|[Pp]ag|[Pp]agg|[Cc]ap|[Nn]|[Aa]rt|[Vv]ol|[Ee]cc|[Ee]tc|[Ee]s|[Pp]|[Ss]t|[Mm]r|[Mm]rs|[Dd]r|[Ss]t|[Vv]s|[Cc]fr|[Ee]d)\.|\b[A-Z]\.|\bp\.es\.|\ba\.C\.|\bd\.C\.)$',
);
