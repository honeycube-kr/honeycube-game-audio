import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:honeycube_game_audio/src/audio_backend.dart';
import 'package:honeycube_game_audio/src/audio_cue.dart';

final class AudioplayersAudioBackend implements AudioBackend {
  AudioplayersAudioBackend({
    AudioCache? cache,
    AudioplayersAudioPlayerFactory? playerFactory,
  }) : _cache = cache ?? AudioCache(prefix: 'assets/'),
       _playerFactory =
           playerFactory ??
           (() => DefaultAudioplayersAudioPlayer(AudioPlayer()));

  final AudioCache _cache;
  final AudioplayersAudioPlayerFactory _playerFactory;
  AudioplayersAudioPlayer? _bgmPlayer;
  final Set<AudioplayersAudioPlayer> _sfxPlayers = {};
  final Set<_LoopingSfxHandle> _loopingSfxHandles = {};
  final Completer<void> _disposed = Completer<void>();
  Completer<void> _sfxStopped = Completer<void>();

  @override
  Future<void> preload(AudioCue cue) async {
    await _cache.load(_assetPath(cue));
  }

  @override
  Future<void> playBgm(
    AudioCue cue, {
    required double volume,
    required bool loop,
  }) async {
    final bgmPlayer = _bgmPlayerOrCreate();
    await bgmPlayer.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
    await bgmPlayer.play(_assetSource(cue), volume: volume);
  }

  @override
  Future<void> stopBgm() async {
    await _bgmPlayer?.stop();
  }

  @override
  Future<void> setBgmVolume(double volume) async {
    await _bgmPlayer?.setVolume(volume);
  }

  @override
  Future<void> playSfx(AudioCue cue, {required double volume}) async {
    final player = _createPlayer();
    _sfxPlayers.add(player);
    final sfxStopped = _sfxStopped.future;

    try {
      await player.setReleaseMode(ReleaseMode.release);
      await player.play(_assetSource(cue), volume: volume);
      await Future.any([
        player.onPlayerComplete.first,
        _disposed.future,
        sfxStopped,
      ]);
    } finally {
      if (_sfxPlayers.remove(player)) {
        await player.dispose();
      }
    }
  }

  @override
  Future<AudioLoopHandle> playLoopingSfx(
    AudioCue cue, {
    required double volume,
  }) async {
    final player = _createPlayer();
    late final _LoopingSfxHandle handle;
    late final StreamSubscription<void> completeSubscription;
    handle = _LoopingSfxHandle(
      player,
      onStop: () {
        _loopingSfxHandles.remove(handle);
        return completeSubscription.cancel();
      },
    );
    completeSubscription = player.onPlayerComplete.listen((_) {
      unawaited(handle.replay());
    });
    _loopingSfxHandles.add(handle);

    try {
      await player.setReleaseMode(ReleaseMode.stop);
      await player.play(_assetSource(cue), volume: volume);
      return handle;
    } catch (_) {
      _loopingSfxHandles.remove(handle);
      await completeSubscription.cancel();
      await player.dispose();
      rethrow;
    }
  }

  @override
  Future<void> stopAllSfx() async {
    _sfxStopped.complete();
    _sfxStopped = Completer<void>();

    final players = _sfxPlayers.toList();
    final loopingSfxHandles = _loopingSfxHandles.toList();
    _sfxPlayers.clear();
    _loopingSfxHandles.clear();

    await Future.wait([
      ...players.map((player) async {
        await player.stop();
        await player.dispose();
      }),
      ...loopingSfxHandles.map((handle) => handle.stop()),
    ]);
  }

  @override
  Future<void> pauseAll() async {
    await _bgmPlayer?.pause();
    await Future.wait([
      ..._sfxPlayers.toList().map((player) => player.pause()),
      ..._loopingSfxHandles.toList().map((handle) => handle._player.pause()),
    ]);
  }

  @override
  Future<void> resumeAll() async {
    await _bgmPlayer?.resume();
    await Future.wait([
      ..._sfxPlayers.toList().map((player) => player.resume()),
      ..._loopingSfxHandles.toList().map((handle) => handle._player.resume()),
    ]);
  }

  @override
  Future<void> dispose() async {
    if (!_disposed.isCompleted) {
      _disposed.complete();
    }

    final bgmPlayer = _bgmPlayer;
    _bgmPlayer = null;

    await Future.wait([
      if (bgmPlayer != null) bgmPlayer.dispose(),
      stopAllSfx(),
    ]);
  }

  AudioplayersAudioPlayer _bgmPlayerOrCreate() {
    return _bgmPlayer ??= _createPlayer();
  }

  AudioplayersAudioPlayer _createPlayer() {
    return _playerFactory()..audioCache = _cache;
  }

  AssetSource _assetSource(AudioCue cue) => AssetSource(_assetPath(cue));

  String _assetPath(AudioCue cue) {
    const prefix = 'assets/';
    final path = cue.assetPath;
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }
}

typedef AudioplayersAudioPlayerFactory = AudioplayersAudioPlayer Function();

abstract interface class AudioplayersAudioPlayer {
  AudioCache get audioCache;
  set audioCache(AudioCache cache);
  Stream<void> get onPlayerComplete;

  Future<void> setReleaseMode(ReleaseMode releaseMode);
  Future<void> play(Source source, {double? volume});
  Future<void> stop();
  Future<void> dispose();
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
}

final class DefaultAudioplayersAudioPlayer implements AudioplayersAudioPlayer {
  DefaultAudioplayersAudioPlayer(this._player);

  final AudioPlayer _player;

  @override
  AudioCache get audioCache => _player.audioCache;

  @override
  set audioCache(AudioCache cache) {
    _player.audioCache = cache;
  }

  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) {
    return _player.setReleaseMode(releaseMode);
  }

  @override
  Future<void> play(Source source, {double? volume}) {
    return _player.play(source, volume: volume);
  }

  @override
  Future<void> stop() {
    return _player.stop();
  }

  @override
  Future<void> dispose() {
    return _player.dispose();
  }

  @override
  Future<void> pause() {
    return _player.pause();
  }

  @override
  Future<void> resume() {
    return _player.resume();
  }

  @override
  Future<void> seek(Duration position) {
    return _player.seek(position);
  }

  @override
  Future<void> setVolume(double volume) {
    return _player.setVolume(volume);
  }
}

final class _LoopingSfxHandle implements AudioLoopHandle {
  _LoopingSfxHandle(this._player, {required this.onStop});

  final AudioplayersAudioPlayer _player;
  final FutureOr<void> Function() onStop;
  Future<void>? _stop;
  bool _stopped = false;

  @override
  Future<void> stop() {
    return _stop ??= _stopPlayer();
  }

  Future<void> replay() async {
    if (_stopped) {
      return;
    }

    try {
      await _player.seek(Duration.zero);
      if (!_stopped) {
        await _player.resume();
      }
    } catch (_) {
      if (!_stopped) {
        await stop();
      }
    }
  }

  Future<void> _stopPlayer() async {
    _stopped = true;
    await onStop();
    await _player.stop();
    await _player.dispose();
  }
}
