import 'dart:async';

import 'package:honeycube_game_audio/src/audio_backend.dart';
import 'package:honeycube_game_audio/src/audio_bus.dart';
import 'package:honeycube_game_audio/src/audio_catalog.dart';
import 'package:honeycube_game_audio/src/audio_cue.dart';

final class HCAudioService {
  HCAudioService({
    required this.backend,
    required this.catalog,
    this.maxConcurrentSfx,
    double masterVolume = 1,
    double bgmVolume = 1,
    double sfxVolume = 1,
  }) : assert(maxConcurrentSfx == null || maxConcurrentSfx > 0) {
    _checkVolume(masterVolume);
    _checkVolume(bgmVolume);
    _checkVolume(sfxVolume);
    _masterVolume = masterVolume;
    _bgmVolume = bgmVolume;
    _sfxVolume = sfxVolume;
  }

  final HCAudioBackend backend;
  final HCAudioCatalog catalog;
  final int? maxConcurrentSfx;

  double _masterVolume = 1;
  double _bgmVolume = 1;
  double _sfxVolume = 1;
  bool _masterMuted = false;
  bool _bgmMuted = false;
  bool _sfxMuted = false;
  bool _hasActiveBgm = false;
  bool _disposed = false;
  double _activeBgmVolume = 0;
  HCAudioCue? _activeBgmCue;
  double _bgmFadeProgress = 1;
  bool _isBgmFadeInActive = false;
  int _fadeGeneration = 0;
  int _bgmVolumeSyncGeneration = 0;
  int _pendingBgmStarts = 0;
  Future<void> _bgmOperation = Future<void>.value();
  final _lastSfxPlayAt = <String, DateTime>{};
  final _lastSfxAssetPath = <String, String>{};
  final _activeSfxInstances = <String, int>{};
  int _activeSfxCount = 0;

  Future<void> preloadAll() async {
    if (_disposed) {
      return;
    }

    for (final cue in [...catalog.bgm.values, ...catalog.sfx.values]) {
      for (final assetPath in cue.assetPaths) {
        try {
          await backend.preload(cue.selectedAsset(assetPath));
        } catch (_) {}
      }
    }
  }

  Future<bool> playBgm(
    String id, {
    bool loop = true,
    Duration fadeIn = Duration.zero,
  }) async {
    if (_disposed) {
      return false;
    }

    final cue = catalog.bgmCue(id);
    if (cue == null) {
      return false;
    }

    final generation = ++_fadeGeneration;
    _isBgmFadeInActive = false;
    _bgmFadeProgress = 1;
    _pendingBgmStarts++;
    try {
      if (_hasActiveBgm) {
        _clearActiveBgm();
        await _queueBgmOperation(() async {
          if (!_disposed) {
            await backend.stopBgm();
          }
        });
        if (!_isCurrentFade(generation)) {
          return false;
        }
      }

      var startedVolume = 0.0;
      await _queueBgmOperation(() async {
        if (!_isCurrentFade(generation)) {
          return;
        }

        startedVolume = fadeIn == Duration.zero
            ? _effectiveVolume(HCAudioBus.bgm, cue)
            : 0;
        await backend.playBgm(cue, volume: startedVolume, loop: loop);
      });
      if (!_isCurrentFade(generation)) {
        return false;
      }

      _hasActiveBgm = true;
      _activeBgmCue = cue;
      _activeBgmVolume = startedVolume;
      if (fadeIn == Duration.zero) {
        final latestVolume = _effectiveActiveBgmVolume();
        if (latestVolume != startedVolume) {
          await _setCurrentBgmVolume(latestVolume, generation);
        }
      } else {
        _isBgmFadeInActive = true;
        _bgmFadeProgress = 0;
        await _fadeBgmVolume(
          0,
          _effectiveActiveBgmVolume,
          fadeIn,
          generation,
          isFadeIn: true,
        );
      }
      return true;
    } catch (_) {
      if (generation == _fadeGeneration) {
        _clearActiveBgm();
        _isBgmFadeInActive = false;
        _bgmFadeProgress = 1;
      }
      return false;
    } finally {
      _pendingBgmStarts--;
    }
  }

  Future<void> stopBgm({Duration fadeOut = Duration.zero}) async {
    if (_disposed) {
      return;
    }

    final generation = ++_fadeGeneration;
    _isBgmFadeInActive = false;
    _bgmFadeProgress = 1;
    if (!_hasActiveBgm && _pendingBgmStarts == 0) {
      return;
    }

    if (fadeOut != Duration.zero && _hasActiveBgm) {
      await _fadeBgmVolume(_activeBgmVolume, () => 0, fadeOut, generation);
      if (_disposed || generation != _fadeGeneration) {
        return;
      }
    }
    _clearActiveBgm();
    await _queueBgmOperation(() async {
      if (!_disposed) {
        await backend.stopBgm();
      }
    });
  }

  Future<bool> playSfx(String id) async {
    if (_disposed) {
      return false;
    }

    final cue = catalog.sfxCue(id);
    if (cue == null || !_canPlaySfx(id, cue)) {
      return false;
    }

    final selectedCue = _reserveSfx(id, cue);
    try {
      final effectiveVolume = _effectiveVolume(HCAudioBus.sfx, selectedCue);
      final startBackend = backend is HCAudioSfxStartBackend
          ? backend as HCAudioSfxStartBackend
          : null;
      if (startBackend != null) {
        final playback = await startBackend.startSfx(
          selectedCue,
          volume: effectiveVolume,
        );
        await playback.completed;
      } else {
        await backend.playSfx(selectedCue, volume: effectiveVolume);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      _releaseSfxInstance(id);
    }
  }

  Future<bool> startSfx(String id) async {
    if (_disposed) {
      return false;
    }

    final cue = catalog.sfxCue(id);
    if (cue == null || !_canPlaySfx(id, cue)) {
      return false;
    }

    final selectedCue = _reserveSfx(id, cue);
    final effectiveVolume = _effectiveVolume(HCAudioBus.sfx, selectedCue);
    final startBackend = backend is HCAudioSfxStartBackend
        ? backend as HCAudioSfxStartBackend
        : null;
    if (startBackend != null) {
      try {
        final playback = await startBackend.startSfx(
          selectedCue,
          volume: effectiveVolume,
        );
        unawaited(
          playback.completed.then<void>(
            (_) => _releaseSfxInstance(id),
            onError: (Object _, StackTrace _) => _releaseSfxInstance(id),
          ),
        );
        return true;
      } catch (_) {
        _releaseSfxInstance(id);
        return false;
      }
    }

    unawaited(
      _playSfxAndRelease(
        id,
        selectedCue,
        effectiveVolume,
      ).catchError((Object _) {}),
    );
    return true;
  }

  Future<HCAudioLoopHandle?> playLoopingSfx(String id) async {
    if (_disposed) {
      return null;
    }

    final cue = catalog.sfxCue(id);
    if (cue == null || !_canPlaySfx(id, cue)) {
      return null;
    }

    final selectedCue = _reserveSfx(id, cue);
    try {
      final handle = await backend.playLoopingSfx(
        selectedCue,
        volume: _effectiveVolume(HCAudioBus.sfx, selectedCue),
      );
      return _TrackedAudioLoopHandle(handle, () => _releaseSfxInstance(id));
    } catch (_) {
      _releaseSfxInstance(id);
      return null;
    }
  }

  Future<void> stopAllSfx() async {
    if (_disposed) {
      return;
    }

    _activeSfxInstances.clear();
    _activeSfxCount = 0;
    await backend.stopAllSfx();
  }

  Future<void> pauseAll() async {
    if (_disposed) {
      return;
    }

    await backend.pauseAll();
  }

  Future<void> resumeAll() async {
    if (_disposed) {
      return;
    }

    await backend.resumeAll();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _fadeGeneration++;
    _clearActiveBgm();
    _isBgmFadeInActive = false;
    _bgmFadeProgress = 1;
    _activeSfxInstances.clear();
    _activeSfxCount = 0;
    _lastSfxPlayAt.clear();
    _lastSfxAssetPath.clear();
    await _queueBgmOperation(backend.dispose);
  }

  void setBusVolume(HCAudioBus bus, double volume) {
    _checkVolume(volume);

    switch (bus) {
      case HCAudioBus.master:
        _masterVolume = volume;
      case HCAudioBus.bgm:
        _bgmVolume = volume;
      case HCAudioBus.sfx:
        _sfxVolume = volume;
    }
    if (bus == HCAudioBus.master || bus == HCAudioBus.bgm) {
      _requestActiveBgmVolumeSync();
    }
  }

  void setMuted(bool muted, {HCAudioBus bus = HCAudioBus.master}) {
    switch (bus) {
      case HCAudioBus.master:
        _masterMuted = muted;
      case HCAudioBus.bgm:
        _bgmMuted = muted;
      case HCAudioBus.sfx:
        _sfxMuted = muted;
    }
    if (bus == HCAudioBus.master || bus == HCAudioBus.bgm) {
      _requestActiveBgmVolumeSync();
    }
  }

  double _effectiveVolume(HCAudioBus bus, HCAudioCue cue) {
    final busVolume = switch (bus) {
      HCAudioBus.master => 1.0,
      HCAudioBus.bgm => _bgmVolume,
      HCAudioBus.sfx => _sfxVolume,
    };
    final busMuted = switch (bus) {
      HCAudioBus.master => false,
      HCAudioBus.bgm => _bgmMuted,
      HCAudioBus.sfx => _sfxMuted,
    };

    if (_masterMuted || busMuted) {
      return 0;
    }

    return _masterVolume * busVolume * cue.volume;
  }

  HCAudioCue _reserveSfx(String id, HCAudioCue cue) {
    final selectedCue = _selectSfxCue(id, cue);
    _lastSfxPlayAt[id] = DateTime.now();
    _activeSfxInstances[id] = (_activeSfxInstances[id] ?? 0) + 1;
    _activeSfxCount++;
    return selectedCue;
  }

  HCAudioCue _selectSfxCue(String id, HCAudioCue cue) {
    final assetPaths = cue.assetPaths;
    if (assetPaths.length == 1) {
      return cue;
    }

    var selectedPath =
        assetPaths[DateTime.now().microsecondsSinceEpoch % assetPaths.length];
    final lastPath = _lastSfxAssetPath[id];
    if (selectedPath == lastPath) {
      final selectedIndex = assetPaths.indexOf(selectedPath);
      selectedPath = assetPaths[(selectedIndex + 1) % assetPaths.length];
    }
    _lastSfxAssetPath[id] = selectedPath;
    return cue.selectedAsset(selectedPath);
  }

  bool _canPlaySfx(String id, HCAudioCue cue) {
    final maxConcurrentSfx = this.maxConcurrentSfx;
    if (maxConcurrentSfx != null && _activeSfxCount >= maxConcurrentSfx) {
      return false;
    }

    final maxInstances = cue.maxInstances;
    if (maxInstances != null &&
        (_activeSfxInstances[id] ?? 0) >= maxInstances) {
      return false;
    }

    final lastPlayAt = _lastSfxPlayAt[id];
    return lastPlayAt == null ||
        DateTime.now().difference(lastPlayAt) >= cue.cooldown;
  }

  Future<void> _playSfxAndRelease(
    String id,
    HCAudioCue cue,
    double effectiveVolume,
  ) async {
    try {
      await backend.playSfx(cue, volume: effectiveVolume);
    } finally {
      _releaseSfxInstance(id);
    }
  }

  void _releaseSfxInstance(String id) {
    if (_activeSfxCount > 0) {
      _activeSfxCount--;
    }

    final active = (_activeSfxInstances[id] ?? 1) - 1;
    if (active <= 0) {
      _activeSfxInstances.remove(id);
    } else {
      _activeSfxInstances[id] = active;
    }
  }

  Future<void> _fadeBgmVolume(
    double startVolume,
    double Function() targetVolume,
    Duration duration,
    int generation, {
    bool isFadeIn = false,
  }) async {
    const steps = 10;
    final stepDelay = duration ~/ steps;

    for (var step = 1; step <= steps; step++) {
      if (_disposed || generation != _fadeGeneration) {
        return;
      }

      if (stepDelay > Duration.zero) {
        await Future<void>.delayed(stepDelay);
      } else {
        await Future<void>.delayed(Duration.zero);
      }

      if (_disposed || generation != _fadeGeneration) {
        return;
      }

      final progress = step / steps;
      if (isFadeIn) {
        _bgmFadeProgress = progress;
      }
      final volume = isFadeIn
          ? targetVolume() * progress
          : startVolume + ((targetVolume() - startVolume) * progress);
      await _setCurrentBgmVolume(volume, generation);
    }

    if (isFadeIn && !_disposed && generation == _fadeGeneration) {
      _isBgmFadeInActive = false;
      _bgmFadeProgress = 1;
    }
  }

  void _requestActiveBgmVolumeSync() {
    final generation = ++_bgmVolumeSyncGeneration;
    final fadeGeneration = _fadeGeneration;
    unawaited(
      _queueBgmOperation(
        () => _syncActiveBgmVolume(generation, fadeGeneration),
      ).catchError((Object _) {}),
    );
  }

  Future<void> _syncActiveBgmVolume(
    int syncGeneration,
    int fadeGeneration,
  ) async {
    if (_disposed || !_hasActiveBgm || _activeBgmCue == null) {
      return;
    }

    final targetVolume = _effectiveActiveBgmVolume();
    final volume = _isBgmFadeInActive
        ? targetVolume * _bgmFadeProgress
        : targetVolume;
    if (syncGeneration != _bgmVolumeSyncGeneration ||
        fadeGeneration != _fadeGeneration) {
      return;
    }
    await backend.setBgmVolume(volume);
    if (_disposed ||
        syncGeneration != _bgmVolumeSyncGeneration ||
        fadeGeneration != _fadeGeneration) {
      return;
    }
    _activeBgmVolume = volume;
  }

  Future<void> _setCurrentBgmVolume(double volume, int generation) async {
    await _queueBgmOperation(() async {
      if (!_isCurrentFade(generation)) {
        return;
      }

      await backend.setBgmVolume(volume);
      if (!_isCurrentFade(generation)) {
        return;
      }

      _activeBgmVolume = volume;
    });
  }

  double _effectiveActiveBgmVolume() {
    final cue = _activeBgmCue;
    if (cue == null) {
      return _activeBgmVolume;
    }

    return _effectiveVolume(HCAudioBus.bgm, cue);
  }

  bool _isCurrentFade(int generation) {
    return !_disposed && generation == _fadeGeneration;
  }

  Future<T> _queueBgmOperation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();

    Future<void> run() async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }

    _bgmOperation = _bgmOperation.then((_) => run(), onError: (_, __) => run());
    return completer.future;
  }

  void _clearActiveBgm() {
    _hasActiveBgm = false;
    _activeBgmVolume = 0;
    _activeBgmCue = null;
  }

  void _checkVolume(double volume) {
    if (volume < 0 || volume > 1) {
      throw RangeError.range(volume, 0, 1, 'volume');
    }
  }
}

final class _TrackedAudioLoopHandle implements HCAudioLoopHandle {
  _TrackedAudioLoopHandle(this._inner, this._onStop);

  final HCAudioLoopHandle _inner;
  final void Function() _onStop;
  bool _stopped = false;

  @override
  Future<void> stop() async {
    if (_stopped) {
      return;
    }

    _stopped = true;
    _onStop();
    await _inner.stop();
  }
}
