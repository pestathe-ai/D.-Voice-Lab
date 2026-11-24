/// Il catalogo delle voci.
///
/// Le voci arrivano in "pacchetti" da scaricare una volta sola:
/// - il pacchetto **Supertonic** contiene 10 voci molto naturali
///   (5 femminili e 5 maschili) che parlano 31 lingue;
/// - i pacchetti **Piper** contengono una voce italiana ciascuno, più leggera.
///
/// I file vengono scaricati dalla pagina pubblica dei modelli di sherpa-onnx.
library;

enum VoiceEngine { supertonic, piper }

enum VoiceGender { female, male }

class VoicePack {
  const VoicePack({
    required this.id,
    required this.title,
    required this.description,
    required this.engine,
    required this.folderName,
    required this.sizeMb,
    required this.requiredFiles,
  });

  final String id;
  final String title;
  final String description;
  final VoiceEngine engine;

  /// Cartella contenuta nell'archivio (e usata sul telefono).
  final String folderName;
  final int sizeMb;

  /// File che devono esserci perché il pacchetto sia "installato".
  final List<String> requiredFiles;

  String get archiveName => '$folderName.tar.bz2';

  String get url =>
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$archiveName';
}

class VoiceInfo {
  const VoiceInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.pack,
    required this.gender,
    this.sid = 0,
  });

  final String id;
  final String name;
  final String description;
  final VoicePack pack;
  final VoiceGender gender;

  /// Numero della voce dentro il pacchetto (solo Supertonic).
  final int sid;

  VoiceEngine get engine => pack.engine;

  /// true se la voce sa leggere anche lingue diverse dall'italiano.
  bool get multilingual => engine == VoiceEngine.supertonic;

  bool get natural => engine == VoiceEngine.supertonic;

  /// Frase usata per il pulsante "Prova".
  String get sample =>
      'Ciao, sono $name. Posso leggerti i tuoi libri ad alta voce, '
      'capitolo dopo capitolo, anche senza internet.';
}

// ---------------------------------------------------------------------------
// Pacchetti

const VoicePack kSupertonicPack = VoicePack(
  id: 'supertonic3',
  title: 'Voci naturali',
  description: '10 voci molto naturali, 5 femminili e 5 maschili. '
      'Leggono in italiano e in altre 30 lingue.',
  engine: VoiceEngine.supertonic,
  folderName: 'sherpa-onnx-supertonic-3-tts-int8-2026-05-11',
  sizeMb: 129,
  requiredFiles: [
    'duration_predictor.int8.onnx',
    'text_encoder.int8.onnx',
    'vector_estimator.int8.onnx',
    'vocoder.int8.onnx',
    'tts.json',
    'unicode_indexer.bin',
    'voice.bin',
  ],
);

const VoicePack kPaolaPack = VoicePack(
  id: 'it_IT-paola-medium',
  title: 'Paola (leggera)',
  description: 'Voce femminile italiana più semplice e leggera.',
  engine: VoiceEngine.piper,
  folderName: 'vits-piper-it_IT-paola-medium',
  sizeMb: 67,
  requiredFiles: ['it_IT-paola-medium.onnx', 'tokens.txt'],
);

const VoicePack kRiccardoPack = VoicePack(
  id: 'it_IT-riccardo-x_low',
  title: 'Riccardo (leggera)',
  description: 'Voce maschile italiana di base, la più leggera.',
  engine: VoiceEngine.piper,
  folderName: 'vits-piper-it_IT-riccardo-x_low',
  sizeMb: 26,
  requiredFiles: ['it_IT-riccardo-x_low.onnx', 'tokens.txt'],
);

const List<VoicePack> kPacks = [kSupertonicPack, kPaolaPack, kRiccardoPack];

// ---------------------------------------------------------------------------
// Voci
//
// Nel file voice.bin di Supertonic le voci sono in ordine alfabetico:
// F1..F5 (numeri 0-4) e poi M1..M5 (numeri 5-9). Verificato misurando
// l'altezza della voce di ciascuna.

const List<VoiceInfo> kVoices = [
  VoiceInfo(
    id: 'st-f1',
    name: 'Giulia',
    description: 'Femminile, chiara e scorrevole.',
    pack: kSupertonicPack,
    gender: VoiceGender.female,
    sid: 0,
  ),
  VoiceInfo(
    id: 'st-f2',
    name: 'Chiara',
    description: 'Femminile, luminosa e vivace.',
    pack: kSupertonicPack,
    gender: VoiceGender.female,
    sid: 1,
  ),
  VoiceInfo(
    id: 'st-f3',
    name: 'Elena',
    description: 'Femminile, calda e profonda: ideale per i romanzi.',
    pack: kSupertonicPack,
    gender: VoiceGender.female,
    sid: 2,
  ),
  VoiceInfo(
    id: 'st-f4',
    name: 'Marta',
    description: 'Femminile, gentile e precisa.',
    pack: kSupertonicPack,
    gender: VoiceGender.female,
    sid: 3,
  ),
  VoiceInfo(
    id: 'st-f5',
    name: 'Sofia',
    description: 'Femminile, pacata e rilassante.',
    pack: kSupertonicPack,
    gender: VoiceGender.female,
    sid: 4,
  ),
  VoiceInfo(
    id: 'st-m1',
    name: 'Marco',
    description: 'Maschile, chiara e naturale.',
    pack: kSupertonicPack,
    gender: VoiceGender.male,
    sid: 5,
  ),
  VoiceInfo(
    id: 'st-m2',
    name: 'Andrea',
    description: 'Maschile, profonda e calma: voce da narratore.',
    pack: kSupertonicPack,
    gender: VoiceGender.male,
    sid: 6,
  ),
  VoiceInfo(
    id: 'st-m3',
    name: 'Davide',
    description: 'Maschile, grave e pacata.',
    pack: kSupertonicPack,
    gender: VoiceGender.male,
    sid: 7,
  ),
  VoiceInfo(
    id: 'st-m4',
    name: 'Paolo',
    description: 'Maschile, media e cordiale.',
    pack: kSupertonicPack,
    gender: VoiceGender.male,
    sid: 8,
  ),
  VoiceInfo(
    id: 'st-m5',
    name: 'Matteo',
    description: 'Maschile, bassa e avvolgente.',
    pack: kSupertonicPack,
    gender: VoiceGender.male,
    sid: 9,
  ),
  VoiceInfo(
    id: 'it_IT-paola-medium',
    name: 'Paola',
    description: 'Femminile, voce leggera (solo italiano).',
    pack: kPaolaPack,
    gender: VoiceGender.female,
  ),
  VoiceInfo(
    id: 'it_IT-riccardo-x_low',
    name: 'Riccardo',
    description: 'Maschile, voce di base (solo italiano).',
    pack: kRiccardoPack,
    gender: VoiceGender.male,
  ),
];

/// La voce proposta di default quando il pacchetto naturale è installato.
const String kDefaultVoiceId = 'st-f3';

VoiceInfo? voiceById(String? id) {
  for (final v in kVoices) {
    if (v.id == id) return v;
  }
  return null;
}

VoicePack? packById(String? id) {
  for (final p in kPacks) {
    if (p.id == id) return p;
  }
  return null;
}

List<VoiceInfo> voicesOfPack(VoicePack pack) =>
    kVoices.where((v) => v.pack.id == pack.id).toList();

/// Codice della lingua per il fonetizzatore espeak-ng (voci Piper).
const String kEspeakVoice = 'it';
