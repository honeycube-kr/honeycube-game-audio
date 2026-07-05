import 'package:honeycube_game_audio/src/audio_cue.dart';

abstract interface class HCAudioLoopHandle {
  Future<void> stop();
}

abstract interface class HCAudioBackend {
  Future<void> preload(HCAudioCue cue);

  Future<void> playBgm(
    HCAudioCue cue, {
    required double volume,
    required bool loop,
  });

  Future<void> stopBgm();

  Future<void> setBgmVolume(double volume);

  Future<void> playSfx(HCAudioCue cue, {required double volume});

  Future<HCAudioLoopHandle> playLoopingSfx(
    HCAudioCue cue, {
    required double volume,
  });

  Future<void> stopAllSfx();

  Future<void> pauseAll();

  Future<void> resumeAll();

  Future<void> dispose();
}
