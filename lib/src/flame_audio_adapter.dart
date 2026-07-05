import 'package:honeycube_game_audio/src/audio_service.dart';

final class HCFlameAudioAdapter {
  const HCFlameAudioAdapter(this.audio);

  final HCAudioService audio;

  Future<void> onLoad() => audio.preloadAll();

  Future<void> onPause() => audio.pauseAll();

  Future<void> onResume() => audio.resumeAll();
}
