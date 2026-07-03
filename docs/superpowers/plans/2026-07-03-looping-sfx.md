# Looping SFX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an easy package API for looped SFX such as footsteps without changing one-shot `playSfx` behavior.

**Architecture:** Keep BGM and SFX policies separate. Add `playLoopingSfx()` to `AudioService`, backed by a small stop handle so callers can start footsteps and stop them explicitly. Reuse existing SFX volume, mute, cooldown, and max-instance policy.

**Tech Stack:** Dart, Flutter test, audioplayers.

---

## File Structure

- Modify `lib/src/audio_backend.dart`: add the public `AudioLoopHandle` contract and `playLoopingSfx` backend method.
- Modify `lib/src/audio_service.dart`: add `playLoopingSfx`, wrap the backend handle to release active-instance tracking on stop.
- Modify `lib/src/audioplayers_audio_backend.dart`: create looped SFX players with `ReleaseMode.loop`, pause/resume/dispose them with existing players.
- Modify `test/audio_service_test.dart`: add service tests and update fake backend.
- Modify `test/flame_audio_adapter_test.dart`: update fake backend for the new interface method.
- Modify `README.md`: add the minimal usage example.

### Task 1: Add AudioService looping SFX behavior

**Files:**
- Modify: `lib/src/audio_backend.dart`
- Modify: `lib/src/audio_service.dart`
- Test: `test/audio_service_test.dart`

- [ ] **Step 1: Write the failing service test**

Add this test before `AudioService forwards preload pause resume and dispose to backend` in `test/audio_service_test.dart`:

```dart
  test('AudioService plays looping SFX until the returned handle stops', () async {
    final catalog = AudioCatalog(
      sfx: {
        'footstep': AudioCue.asset(
          'assets/sounds/oncha_footstep.wav',
          volume: 0.8,
          maxInstances: 1,
        ),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = AudioService(backend: backend, catalog: catalog);

    audio.setBusVolume(AudioBus.master, 0.5);
    audio.setBusVolume(AudioBus.sfx, 0.5);

    final handle = await audio.playLoopingSfx('footstep', volume: 0.5);

    expect(handle, isNotNull);
    expect(await audio.playLoopingSfx('footstep'), isNull);

    await handle!.stop();
    final secondHandle = await audio.playLoopingSfx('footstep');
    await secondHandle!.stop();

    expect(backend.calls, [
      'playLoopingSfx:assets/sounds/oncha_footstep.wav:0.1',
      'stopLoopingSfx:assets/sounds/oncha_footstep.wav',
      'playLoopingSfx:assets/sounds/oncha_footstep.wav:0.2',
      'stopLoopingSfx:assets/sounds/oncha_footstep.wav',
    ]);
  });
```

Update `_FakeAudioBackend` in `test/audio_service_test.dart` with this method and helper class:

```dart
  @override
  Future<AudioLoopHandle> playLoopingSfx(
    AudioCue cue, {
    required double volume,
  }) async {
    calls.add('playLoopingSfx:${cue.assetPath}:$volume');
    return _FakeAudioLoopHandle(calls, cue.assetPath);
  }
```

```dart
final class _FakeAudioLoopHandle implements AudioLoopHandle {
  _FakeAudioLoopHandle(this.calls, this.assetPath);

  final List<String> calls;
  final String assetPath;
  bool _stopped = false;

  @override
  Future<void> stop() async {
    if (_stopped) {
      return;
    }

    _stopped = true;
    calls.add('stopLoopingSfx:$assetPath');
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
flutter test test/audio_service_test.dart --plain-name "AudioService plays looping SFX until the returned handle stops"
```

Expected: FAIL because `AudioLoopHandle` and `AudioService.playLoopingSfx` do not exist.

- [ ] **Step 3: Add the minimal backend contract**

Change `lib/src/audio_backend.dart` to:

```dart
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

  Future<void> playSfx(AudioCue cue, {required double volume});

  Future<AudioLoopHandle> playLoopingSfx(
    AudioCue cue, {
    required double volume,
  });

  Future<void> pauseAll();

  Future<void> resumeAll();

  Future<void> dispose();
}
```

- [ ] **Step 4: Add the minimal service API**

In `lib/src/audio_service.dart`, add this method after `playSfx`:

```dart
  Future<AudioLoopHandle?> playLoopingSfx(String id, {double volume = 1}) async {
    _checkVolume(volume);

    if (_disposed) {
      return null;
    }

    final cue = catalog.sfxCue(id);
    if (cue == null || !_canPlaySfx(id, cue)) {
      return null;
    }

    _lastSfxPlayAt[id] = DateTime.now();
    _activeSfxInstances[id] = (_activeSfxInstances[id] ?? 0) + 1;
    try {
      final handle = await backend.playLoopingSfx(
        cue,
        volume: _effectiveVolume(AudioBus.sfx, cue, volume),
      );
      return _TrackedAudioLoopHandle(handle, () => _releaseSfxInstance(id));
    } catch (_) {
      _releaseSfxInstance(id);
      rethrow;
    }
  }
```

Add this helper inside `AudioService` after `_canPlaySfx`:

```dart
  void _releaseSfxInstance(String id) {
    final active = (_activeSfxInstances[id] ?? 1) - 1;
    if (active <= 0) {
      _activeSfxInstances.remove(id);
    } else {
      _activeSfxInstances[id] = active;
    }
  }
```

Replace the `finally` body in `playSfx` with:

```dart
      _releaseSfxInstance(id);
```

Add this private class after `AudioService`:

```dart
final class _TrackedAudioLoopHandle implements AudioLoopHandle {
  _TrackedAudioLoopHandle(this._inner, this._onStop);

  final AudioLoopHandle _inner;
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
```

- [ ] **Step 5: Run the service test to verify it passes**

Run:

```powershell
flutter test test/audio_service_test.dart --plain-name "AudioService plays looping SFX until the returned handle stops"
```

Expected: PASS.

### Task 2: Implement audioplayers looping SFX backend

**Files:**
- Modify: `lib/src/audioplayers_audio_backend.dart`
- Test: `test/audio_service_test.dart`
- Test: `test/flame_audio_adapter_test.dart`

- [ ] **Step 1: Write the backend contract test update**

In `test/audio_service_test.dart`, update `core catalog and backend contract are usable without playback policy` by inserting this after `await backend.playSfx(...)`:

```dart
      final loopingSfx = await backend.playLoopingSfx(
        catalog.sfxCue('ui_button')!,
        volume: 0.5,
      );
      await loopingSfx.stop();
```

Update that test's expected calls to:

```dart
      expect(backend.calls, [
        'preload:assets/sounds/gameplay_bgm.mp3',
        'playBgm:assets/sounds/gameplay_bgm.mp3:0.7:true',
        'playSfx:assets/sounds/ui_button.wav:1.0',
        'playLoopingSfx:assets/sounds/ui_button.wav:0.5',
        'stopLoopingSfx:assets/sounds/ui_button.wav',
        'pauseAll',
        'resumeAll',
        'stopBgm',
        'dispose',
      ]);
```

Update `_FakeAudioBackend` in `test/flame_audio_adapter_test.dart` with:

```dart
  @override
  Future<AudioLoopHandle> playLoopingSfx(
    AudioCue cue, {
    required double volume,
  }) async {
    return _FakeAudioLoopHandle();
  }
```

Add this class to `test/flame_audio_adapter_test.dart`:

```dart
final class _FakeAudioLoopHandle implements AudioLoopHandle {
  @override
  Future<void> stop() async {}
}
```

- [ ] **Step 2: Run tests to verify compile failure**

Run:

```powershell
flutter test test/audio_service_test.dart test/flame_audio_adapter_test.dart
```

Expected: FAIL because `AudioplayersAudioBackend` does not implement `playLoopingSfx`.

- [ ] **Step 3: Implement looped SFX in audioplayers backend**

In `lib/src/audioplayers_audio_backend.dart`, add this field after `_sfxPlayers`:

```dart
  final Set<_LoopingSfxHandle> _loopingSfxHandles = {};
```

Add this method after `playSfx`:

```dart
  @override
  Future<AudioLoopHandle> playLoopingSfx(
    AudioCue cue, {
    required double volume,
  }) async {
    final player = AudioPlayer()..audioCache = _cache;
    late final _LoopingSfxHandle handle;
    handle = _LoopingSfxHandle(
      player,
      () => _loopingSfxHandles.remove(handle),
    );
    _loopingSfxHandles.add(handle);

    try {
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(_assetSource(cue), volume: volume);
      return handle;
    } catch (_) {
      _loopingSfxHandles.remove(handle);
      await player.dispose();
      rethrow;
    }
  }
```

Update `pauseAll` to:

```dart
  @override
  Future<void> pauseAll() async {
    await _bgmPlayer?.pause();
    await Future.wait([
      ..._sfxPlayers.toList().map((player) => player.pause()),
      ..._loopingSfxHandles.toList().map((handle) => handle._player.pause()),
    ]);
  }
```

Update `resumeAll` to:

```dart
  @override
  Future<void> resumeAll() async {
    await _bgmPlayer?.resume();
    await Future.wait([
      ..._sfxPlayers.toList().map((player) => player.resume()),
      ..._loopingSfxHandles.toList().map((handle) => handle._player.resume()),
    ]);
  }
```

Update `dispose` to:

```dart
  @override
  Future<void> dispose() async {
    if (!_disposed.isCompleted) {
      _disposed.complete();
    }

    final players = _sfxPlayers.toList();
    final loopingSfxHandles = _loopingSfxHandles.toList();
    final bgmPlayer = _bgmPlayer;
    _bgmPlayer = null;
    _sfxPlayers.clear();
    _loopingSfxHandles.clear();
    await Future.wait([
      if (bgmPlayer != null) bgmPlayer.dispose(),
      ...players.map((player) => player.dispose()),
      ...loopingSfxHandles.map((handle) => handle.stop()),
    ]);
  }
```

Add this private class at the end of `lib/src/audioplayers_audio_backend.dart`:

```dart
final class _LoopingSfxHandle implements AudioLoopHandle {
  _LoopingSfxHandle(this._player, this._onStop);

  final AudioPlayer _player;
  final void Function() _onStop;
  Future<void>? _stop;

  @override
  Future<void> stop() {
    return _stop ??= _stopPlayer();
  }

  Future<void> _stopPlayer() async {
    _onStop();
    await _player.stop();
    await _player.dispose();
  }
}
```

- [ ] **Step 4: Run focused tests**

Run:

```powershell
flutter test test/audio_service_test.dart test/flame_audio_adapter_test.dart
```

Expected: PASS.

### Task 3: Document the package API

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add the usage example**

Change `README.md` to:

```markdown
# honeycube_game_audio

Shared audio service package for Studio Daily Flutter and Flame games.

This package starts as a local package used by `hide_n_seek_escape`.
It intentionally does not provide a singleton or service locator.

```dart
final footsteps = await audio.playLoopingSfx('footstep');
await footsteps?.stop();
```
```

- [ ] **Step 2: Format changed Dart files**

Run:

```powershell
dart format lib/src/audio_backend.dart lib/src/audio_service.dart lib/src/audioplayers_audio_backend.dart test/audio_service_test.dart test/flame_audio_adapter_test.dart
```

Expected: files are formatted.

- [ ] **Step 3: Analyze changed scope**

Run:

```powershell
dart analyze lib/src/audio_backend.dart lib/src/audio_service.dart lib/src/audioplayers_audio_backend.dart test/audio_service_test.dart test/flame_audio_adapter_test.dart
```

Expected: no issues.

- [ ] **Step 4: Run focused tests**

Run:

```powershell
flutter test test/audio_service_test.dart test/flame_audio_adapter_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```powershell
git add lib/src/audio_backend.dart lib/src/audio_service.dart lib/src/audioplayers_audio_backend.dart test/audio_service_test.dart test/flame_audio_adapter_test.dart README.md
git commit -m "feat: add looping sfx playback"
```

Expected: commit succeeds.

## Self-Review

- Spec coverage: covers easy footstep loop start/stop, preserves one-shot `playSfx`, keeps BGM policy separate.
- Placeholder scan: no placeholder steps remain.
- Type consistency: `AudioLoopHandle`, `playLoopingSfx`, and `stop` names are consistent across service, backend, tests, and README.

