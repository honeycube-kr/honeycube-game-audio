import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honeycube_game_audio/honeycube_game_audio.dart';

void main() {
  test('play 반환 전에 끝난 효과음도 완료되고 플레이어를 해제한다', () async {
    final player = _ImmediatePlayer();
    final backend = HCAudioplayersAudioBackend(playerFactory: () => player);
    addTearDown(backend.dispose);
    final playback = await backend.startSfx(
      const HCAudioCue.asset('audio/short.wav'),
      volume: 1,
    );
    var completed = false;
    unawaited(playback.completed.then((_) => completed = true));
    await pumpEventQueue();
    expect(completed, isTrue);
    expect(player.disposeCalls, 1);
  });

  test('짧은 효과음을 동시재생 한도보다 많이 순차 재생해도 슬롯을 누수하지 않는다', () async {
    final players = <_ImmediatePlayer>[];
    final backend = HCAudioplayersAudioBackend(
      playerFactory: () {
        final player = _ImmediatePlayer();
        players.add(player);
        return player;
      },
    );
    final service = HCAudioService(
      backend: backend,
      catalog: HCAudioCatalog(
        bgm: const {},
        sfx: const {'line': HCAudioCue.asset('audio/short.wav')},
      ),
      maxConcurrentSfx: 6,
    );
    addTearDown(service.dispose);
    for (var index = 0; index < 8; index += 1) {
      expect(await service.startSfx('line'), isTrue, reason: '재생 ${index + 1}');
      await pumpEventQueue();
    }
    expect(players, hasLength(8));
    expect(players.every((player) => player.disposeCalls == 1), isTrue);
  });

  test('재생 시작이 실패해도 완료 구독 오류 없이 플레이어를 해제한다', () async {
    final player = _ImmediatePlayer(failToPlay: true, emitStreamError: true);
    final backend = HCAudioplayersAudioBackend(playerFactory: () => player);
    addTearDown(backend.dispose);
    await expectLater(
      backend.startSfx(const HCAudioCue.asset('audio/short.wav'), volume: 1),
      throwsStateError,
    );
    await pumpEventQueue();
    expect(player.disposeCalls, 1);
  });

  test('재생 시작 대기 중 전체 중단을 해도 완료되고 플레이어를 중복 해제하지 않는다', () async {
    final gate = Completer<void>();
    final player = _ImmediatePlayer(
      playGate: gate.future,
      emitCompletion: false,
    );
    final backend = HCAudioplayersAudioBackend(playerFactory: () => player);
    addTearDown(backend.dispose);
    final starting = backend.startSfx(
      const HCAudioCue.asset('audio/short.wav'),
      volume: 1,
    );
    await pumpEventQueue();
    await backend.stopAllSfx();
    gate.complete();
    final playback = await starting;
    await playback.completed;
    expect(player.disposeCalls, 1);
  });
}

class _ImmediatePlayer implements HCAudioplayersAudioPlayer {
  _ImmediatePlayer({
    this.failToPlay = false,
    this.playGate,
    this.emitCompletion = true,
    this.emitStreamError = false,
  });

  final bool failToPlay;
  final Future<void>? playGate;
  final bool emitCompletion;
  final bool emitStreamError;
  final _complete = StreamController<void>.broadcast(sync: true);
  int disposeCalls = 0;

  @override
  late AudioCache audioCache;
  @override
  Stream<void> get onPlayerComplete => _complete.stream;
  @override
  Future<void> play(Source source, {double? volume}) async {
    if (playGate != null) await playGate;
    if (emitStreamError) _complete.addError(StateError('완료 스트림 실패'));
    if (failToPlay) throw StateError('재생 시작 실패');
    if (emitCompletion) _complete.add(null);
  }

  @override
  Future<void> setAudioContext(AudioContext context) async {}
  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _complete.close();
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
}
