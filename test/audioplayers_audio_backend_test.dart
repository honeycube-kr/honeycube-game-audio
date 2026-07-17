import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honeycube_game_audio/honeycube_game_audio.dart';

void main() {
  test(
    'HCAudioplayersAudioBackend keeps BGM playing while SFX uses no audio focus',
    () async {
      final players = <_FakeAudioPlayer>[];
      final backend = HCAudioplayersAudioBackend(
        playerFactory: () {
          final player = _FakeAudioPlayer();
          players.add(player);
          return player;
        },
      );

      await backend.playBgm(
        HCAudioCue.asset('assets/audio/bgm.mp3'),
        volume: 0.5,
        loop: true,
      );
      final sfxPlayback = backend.playSfx(
        HCAudioCue.asset('assets/audio/sfx.wav'),
        volume: 0.8,
      );
      await Future<void>.delayed(Duration.zero);

      expect(players, hasLength(2));
      expect(
        players[0].audioContexts.single.android,
        const AudioContextAndroid(
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      );
      expect(
        players[1].audioContexts.single.android,
        const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
      );
      expect(players[0].releaseModes, [ReleaseMode.loop]);
      expect(players[0].pauseCalls, 0);
      expect(players[0].stopCalls, 0);
      expect(players[0].disposeCalls, 0);

      players[1].complete();
      await sfxPlayback;

      expect(players[0].pauseCalls, 0);
      expect(players[0].stopCalls, 0);
      expect(players[0].disposeCalls, 0);

      await backend.dispose();
    },
  );

  test(
    'HCAudioplayersAudioBackend restarts looping SFX when playback completes',
    () async {
      final players = <_FakeAudioPlayer>[];
      final backend = HCAudioplayersAudioBackend(
        playerFactory: () {
          final player = _FakeAudioPlayer();
          players.add(player);
          return player;
        },
      );

      final handle = await backend.playLoopingSfx(
        HCAudioCue.asset('assets/sounds/oncha_footstep.wav'),
        volume: 0.5,
      );

      expect(players, hasLength(1));
      expect(players.single.releaseModes, [ReleaseMode.stop]);
      expect(players.single.playCalls, 1);

      players.single.complete();
      await Future<void>.delayed(Duration.zero);

      expect(players.single.seekPositions, [Duration.zero]);
      expect(players.single.resumeCalls, 1);

      await handle.stop();
      players.single.complete();
      await Future<void>.delayed(Duration.zero);

      expect(players.single.resumeCalls, 1);
      expect(players.single.stopCalls, 1);
      expect(players.single.disposeCalls, 1);
    },
  );
}

final class _FakeAudioPlayer implements HCAudioplayersAudioPlayer {
  final audioContexts = <AudioContext>[];
  final releaseModes = <ReleaseMode>[];
  final seekPositions = <Duration>[];
  final _completeController = StreamController<void>.broadcast();
  var playCalls = 0;
  var resumeCalls = 0;
  var stopCalls = 0;
  var disposeCalls = 0;
  var pauseCalls = 0;

  @override
  late AudioCache audioCache;

  @override
  Stream<void> get onPlayerComplete => _completeController.stream;

  void complete() {
    if (_completeController.isClosed) {
      return;
    }

    _completeController.add(null);
  }

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async {
    releaseModes.add(releaseMode);
  }

  @override
  Future<void> setAudioContext(AudioContext audioContext) async {
    audioContexts.add(audioContext);
  }

  @override
  Future<void> play(Source source, {double? volume}) async {
    playCalls += 1;
  }

  @override
  Future<void> seek(Duration position) async {
    seekPositions.add(position);
  }

  @override
  Future<void> resume() async {
    resumeCalls += 1;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _completeController.close();
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
  }

  @override
  Future<void> setVolume(double volume) async {}
}
