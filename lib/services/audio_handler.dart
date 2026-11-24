import 'package:audio_service/audio_service.dart';

import 'reader.dart';

/// Collega il lettore ai comandi di sistema: notifica, schermata di blocco,
/// cuffie e auto. Tiene anche l'app attiva con lo schermo spento.
class DVoceAudioHandler extends BaseAudioHandler {
  DVoceAudioHandler(this.reader) {
    reader.addListener(_sync);
    _sync();
  }

  final Reader reader;
  String? _lastItemKey;

  void _sync() {
    final b = reader.book;
    if (b != null && reader.chapters.isNotEmpty) {
      final ch = reader.chapters[reader.chapterIndex];
      final chTitle = ch.title.isEmpty ? 'Capitolo ${reader.chapterIndex + 1}' : ch.title;
      final cover = reader.library.coverPath(b);
      final key = '${b.id}/${reader.chapterIndex}/${b.coverVersion}';
      if (key != _lastItemKey) {
        _lastItemKey = key;
        mediaItem.add(MediaItem(
          id: key,
          title: chTitle,
          album: b.title,
          artist: b.author.isEmpty ? 'D. Voce' : b.author,
          displaySubtitle: b.title,
          artUri: cover == null ? null : Uri.file(cover),
        ));
      }
    }

    final playing = reader.state == ReaderState.playing;
    final AudioProcessingState processing;
    switch (reader.state) {
      case ReaderState.idle:
        processing = b == null ? AudioProcessingState.idle : AudioProcessingState.ready;
      case ReaderState.preparing:
        processing = AudioProcessingState.buffering;
      case ReaderState.playing:
      case ReaderState.paused:
        processing = AudioProcessingState.ready;
    }

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.rewind,
        if (playing || reader.state == ReaderState.preparing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.rewind,
        MediaAction.fastForward,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processing,
      playing: playing || reader.state == ReaderState.preparing,
    ));
  }

  @override
  Future<void> play() => reader.play();

  @override
  Future<void> pause() => reader.pause();

  @override
  Future<void> stop() async {
    await reader.stop();
    await super.stop();
  }

  /// I tasti "avanti/indietro" delle cuffie saltano di una frase.
  @override
  Future<void> skipToNext() => reader.next();

  @override
  Future<void> skipToPrevious() => reader.previous();

  @override
  Future<void> fastForward() => reader.skipBy(const Duration(seconds: 30));

  @override
  Future<void> rewind() => reader.skipBy(const Duration(seconds: -30));
}
