import 'package:honeycube_game_audio/src/audio_cue.dart';

final class AudioCatalog {
  AudioCatalog({
    Map<String, AudioCue> bgm = const {},
    Map<String, AudioCue> sfx = const {},
  }) : bgm = Map.unmodifiable(bgm),
       sfx = Map.unmodifiable(sfx);

  final Map<String, AudioCue> bgm;
  final Map<String, AudioCue> sfx;

  AudioCue? bgmCue(String id) => bgm[id];

  AudioCue? sfxCue(String id) => sfx[id];
}
