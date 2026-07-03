import 'package:honeycube_game_audio/src/audio_cue.dart';

abstract interface class AudioLoopHandle {
  Future<void> stop();
}

abstract interface class AudioBackend {
  Future<void> preload(AudioCue cue);

  Future<void> playBgm(
    AudioCue cue, {
    required double volume,
    required bool loop,
  });

  Future<void> stopBgm();

  Future<void> setBgmVolume(double volume);

  Future<void> playSfx(AudioCue cue, {required double volume});

  Future<AudioLoopHandle> playLoopingSfx(
    AudioCue cue, {
    required double volume,
  });

  Future<void> stopAllSfx();

  Future<void> pauseAll();

  Future<void> resumeAll();

  Future<void> dispose();
}
