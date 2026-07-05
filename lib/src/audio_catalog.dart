import 'package:honeycube_game_audio/src/audio_cue.dart';

final class HCAudioCatalog {
  HCAudioCatalog({
    Map<String, HCAudioCue> bgm = const {},
    Map<String, HCAudioCue> sfx = const {},
  }) : bgm = Map.unmodifiable(bgm),
       sfx = Map.unmodifiable(sfx);

  final Map<String, HCAudioCue> bgm;
  final Map<String, HCAudioCue> sfx;

  HCAudioCue? bgmCue(String id) => bgm[id];

  HCAudioCue? sfxCue(String id) => sfx[id];
}
