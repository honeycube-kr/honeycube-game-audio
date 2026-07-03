import 'package:honeycube_game_audio/src/audio_service.dart';

final class FlameAudioAdapter {
  const FlameAudioAdapter(this.audio);

  final AudioService audio;

  Future<void> onLoad() => audio.preloadAll();

  Future<void> onPause() => audio.pauseAll();

  Future<void> onResume() => audio.resumeAll();
}
