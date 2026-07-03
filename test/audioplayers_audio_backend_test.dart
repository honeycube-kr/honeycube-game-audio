import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honeycube_game_audio/honeycube_game_audio.dart';

void main() {
  test(
    'AudioplayersAudioBackend restarts looping SFX when playback completes',
    () async {
      final players = <_FakeAudioPlayer>[];
      final backend = AudioplayersAudioBackend(
        playerFactory: () {
          final player = _FakeAudioPlayer();
          players.add(player);
          return player;
        },
      );

      final handle = await backend.playLoopingSfx(
        AudioCue.asset('assets/sounds/oncha_footstep.wav'),
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

final class _FakeAudioPlayer implements AudioplayersAudioPlayer {
  final releaseModes = <ReleaseMode>[];
  final seekPositions = <Duration>[];
  final _completeController = StreamController<void>.broadcast();
  var playCalls = 0;
  var resumeCalls = 0;
  var stopCalls = 0;
  var disposeCalls = 0;

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
  Future<void> pause() async {}

  @override
  Future<void> setVolume(double volume) async {}
}
