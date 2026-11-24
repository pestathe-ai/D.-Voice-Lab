/// Lingue che le voci naturali sanno leggere (codici Supertonic 3).
library;

class BookLanguage {
  const BookLanguage(this.code, this.name);
  final String code;
  final String name;
}

const List<BookLanguage> kLanguages = [
  BookLanguage('it', 'Italiano'),
  BookLanguage('en', 'Inglese'),
  BookLanguage('es', 'Spagnolo'),
  BookLanguage('fr', 'Francese'),
  BookLanguage('de', 'Tedesco'),
  BookLanguage('pt', 'Portoghese'),
  BookLanguage('nl', 'Olandese'),
  BookLanguage('ro', 'Rumeno'),
  BookLanguage('pl', 'Polacco'),
  BookLanguage('cs', 'Ceco'),
  BookLanguage('sk', 'Slovacco'),
  BookLanguage('sl', 'Sloveno'),
  BookLanguage('hr', 'Croato'),
  BookLanguage('hu', 'Ungherese'),
  BookLanguage('bg', 'Bulgaro'),
  BookLanguage('ru', 'Russo'),
  BookLanguage('uk', 'Ucraino'),
  BookLanguage('el', 'Greco'),
  BookLanguage('tr', 'Turco'),
  BookLanguage('sv', 'Svedese'),
  BookLanguage('da', 'Danese'),
  BookLanguage('fi', 'Finlandese'),
  BookLanguage('et', 'Estone'),
  BookLanguage('lv', 'Lettone'),
  BookLanguage('lt', 'Lituano'),
  BookLanguage('ar', 'Arabo'),
  BookLanguage('hi', 'Hindi'),
  BookLanguage('id', 'Indonesiano'),
  BookLanguage('vi', 'Vietnamita'),
  BookLanguage('ja', 'Giapponese'),
  BookLanguage('ko', 'Coreano'),
];

String languageName(String code) {
  for (final l in kLanguages) {
    if (l.code == code) return l.name;
  }
  return code;
}

bool isSupportedLanguage(String code) => kLanguages.any((l) => l.code == code);

/// Indovina la lingua di un testo contando parole molto comuni.
/// Riconosce le lingue europee più diffuse; se non è sicuro dice 'it'.
String guessLanguage(String text) {
  final sample = text.length > 20000 ? text.substring(0, 20000) : text;
  final words = RegExp(r"[a-zàèéìíòóùúäöüßçñ']+", caseSensitive: false)
      .allMatches(sample.toLowerCase())
      .map((m) => m.group(0)!)
      .toList();
  if (words.length < 20) return 'it';
  const markers = <String, Set<String>>{
    'it': {'il', 'della', 'che', 'non', 'per', 'una', 'sono', 'gli', 'nel', 'anche', 'questo', 'è'},
    'en': {'the', 'and', 'of', 'to', 'is', 'that', 'was', 'with', 'for', 'his', 'her', 'you'},
    'es': {'el', 'los', 'las', 'que', 'del', 'por', 'una', 'con', 'para', 'pero', 'como', 'muy'},
    'fr': {'le', 'les', 'des', 'est', 'une', 'pas', 'que', 'dans', 'pour', 'avec', 'sur', 'qui'},
    'de': {'der', 'die', 'und', 'das', 'ist', 'nicht', 'ein', 'mit', 'sich', 'auf', 'für', 'auch'},
    'pt': {'os', 'não', 'uma', 'com', 'para', 'mais', 'como', 'mas', 'foi', 'ao', 'pelo', 'são'},
    'nl': {'de', 'het', 'een', 'van', 'en', 'niet', 'dat', 'zijn', 'voor', 'met', 'ook', 'maar'},
  };
  final counts = <String, int>{for (final k in markers.keys) k: 0};
  for (final w in words) {
    markers.forEach((lang, set) {
      if (set.contains(w)) counts[lang] = counts[lang]! + 1;
    });
  }
  var best = 'it';
  var bestCount = 0;
  counts.forEach((lang, c) {
    if (c > bestCount) {
      best = lang;
      bestCount = c;
    }
  });
  // Troppo pochi indizi: meglio l'italiano.
  if (bestCount < words.length * 0.03) return 'it';
  return best;
}
