/// Le voci italiane disponibili. I file vengono scaricati dalla pagina
/// pubblica dei modelli di sherpa-onnx (voci Piper già convertite).
class VoiceInfo {
  const VoiceInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.sizeMb,
    required this.sampleRate,
  });

  /// Identificativo Piper, es. `it_IT-paola-medium`.
  final String id;
  final String name;
  final String description;

  /// Dimensione approssimativa del download in MB.
  final int sizeMb;
  final int sampleRate;

  String get folderName => 'vits-piper-$id';
  String get archiveName => '$folderName.tar.bz2';
  String get modelFile => '$id.onnx';
  String get tokensFile => 'tokens.txt';

  String get url =>
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$archiveName';

  /// Frase usata per il pulsante "Prova".
  String get sample =>
      'Ciao, sono $name. Posso leggerti i tuoi testi ad alta voce, anche senza internet.';
}

const List<VoiceInfo> kVoices = [
  VoiceInfo(
    id: 'it_IT-paola-medium',
    name: 'Paola',
    description: 'Voce femminile, qualità media: la più naturale.',
    sizeMb: 67,
    sampleRate: 22050,
  ),
  VoiceInfo(
    id: 'it_IT-riccardo-x_low',
    name: 'Riccardo',
    description: 'Voce maschile, qualità base: più leggera e veloce.',
    sizeMb: 26,
    sampleRate: 16000,
  ),
];

VoiceInfo? voiceById(String? id) {
  for (final v in kVoices) {
    if (v.id == id) return v;
  }
  return null;
}

/// Codice della lingua per il fonetizzatore espeak-ng.
const String kEspeakVoice = 'it';
