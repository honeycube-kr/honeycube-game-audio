import 'package:flutter_test/flutter_test.dart';
import 'package:honeycube_game_audio/honeycube_game_audio.dart';

void main() {
  test(
    'HCFlameAudioAdapter forwards preload pause and resume to HCAudioService',
    () async {
      final catalog = HCAudioCatalog(
        bgm: {'gameplay': HCAudioCue.asset('assets/sounds/gameplay_bgm.mp3')},
        sfx: {'ui_button': HCAudioCue.asset('assets/sounds/ui_button.wav')},
      );
      final backend = _FakeAudioBackend();
      final audio = HCAudioService(backend: backend, catalog: catalog);
      final adapter = HCFlameAudioAdapter(audio);

      await adapter.onLoad();
      await adapter.onPause();
      await adapter.onResume();

      expect(backend.calls, [
        'preload:assets/sounds/gameplay_bgm.mp3',
        'preload:assets/sounds/ui_button.wav',
        'pauseAll',
        'resumeAll',
      ]);
    },
  );
}

final class _FakeAudioBackend implements HCAudioBackend {
  final calls = <String>[];

  @override
  Future<void> preload(HCAudioCue cue) async {
    calls.add('preload:${cue.assetPath}');
  }

  @override
  Future<void> playBgm(
    HCAudioCue cue, {
    required double volume,
    required bool loop,
  }) async {}

  @override
  Future<void> setBgmVolume(double volume) async {}

  @override
  Future<void> playSfx(HCAudioCue cue, {required double volume}) async {}

  @override
  Future<HCAudioLoopHandle> playLoopingSfx(
    HCAudioCue cue, {
    required double volume,
  }) async {
    return _FakeAudioLoopHandle();
  }

  @override
  Future<void> stopAllSfx() async {
    calls.add('stopAllSfx');
  }

  @override
  Future<void> pauseAll() async {
    calls.add('pauseAll');
  }

  @override
  Future<void> resumeAll() async {
    calls.add('resumeAll');
  }

  @override
  Future<void> stopBgm() async {}

  @override
  Future<void> dispose() async {}
}

final class _FakeAudioLoopHandle implements HCAudioLoopHandle {
  @override
  Future<void> stop() async {}
}
