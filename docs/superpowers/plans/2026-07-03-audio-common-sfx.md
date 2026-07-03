# Audio Common SFX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add package-level common SFX playback engine features needed by games without adding Brick-specific cue mapping.

**Architecture:** Keep the package boundary at reusable audio engine behavior: fire-and-forget SFX, safe failure handling, cue variation, SFX stop, and a global SFX cap. Reuse the existing `AudioService` policy layer and `AudioBackend` playback layer; do not add managers, service locators, sound IDs, pitch, or Brick event mapping.

**Tech Stack:** Dart 3.12, Flutter test, audioplayers.

---

## File Structure

- Modify `lib/src/audio_service.dart`: add `startSfx()`, safe playback wrappers, variation selection, `stopAllSfx()`, and optional global SFX limit.
- Modify `lib/src/audio_backend.dart`: add `stopAllSfx()` to the backend contract.
- Modify `lib/src/audioplayers_audio_backend.dart`: stop and release transient and looping SFX players safely.
- Modify `lib/src/audio_cue.dart`: add `AudioCue.assets([...])` while preserving `AudioCue.asset(...)`.
- Modify `test/audio_service_test.dart`: cover service policy and fake backend behavior.
- Modify `test/flame_audio_adapter_test.dart`: update the fake backend contract.
- Modify `README.md`: document the smallest public examples.

## Out Of Scope

- Brick `SoundId`, combo, line-clear, dialog, or toast mapping.
- Brick `SoundCueManager`.
- BGM composition, track transition policy, or playlist logic.
- Pitch support.
- Priority preemption for SFX overload. First version drops new SFX when the global cap is full.

---

### Task 1: Add fire-and-forget `startSfx()`

**Files:**
- Modify: `lib/src/audio_service.dart`
- Test: `test/audio_service_test.dart`

- [ ] **Step 1: Write the failing service test**

Add this test before `AudioService applies master and sfx mute to SFX volume` in `test/audio_service_test.dart`:

```dart
  test('AudioService starts SFX without waiting for completion', () async {
    final catalog = AudioCatalog(
      sfx: {
        'ui_button': AudioCue.asset(
          'assets/sounds/ui_button.wav',
          maxInstances: 1,
        ),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = AudioService(backend: backend, catalog: catalog);

    backend.holdSfx('assets/sounds/ui_button.wav');

    expect(await audio.startSfx('ui_button'), isTrue);
    expect(await audio.startSfx('ui_button'), isFalse);
    expect(backend.calls, ['playSfx:assets/sounds/ui_button.wav:1.0']);

    backend.releaseSfx();
    await backend.waitForHeldSfxComplete();

    expect(await audio.startSfx('ui_button'), isTrue);
    expect(backend.calls, [
      'playSfx:assets/sounds/ui_button.wav:1.0',
      'playSfx:assets/sounds/ui_button.wav:1.0',
    ]);
  });
```

Update `_FakeAudioBackend` in `test/audio_service_test.dart`:

```dart
  Completer<void>? _sfxBlocker;
  Completer<void>? _sfxComplete;
  String? _heldSfxAssetPath;

  void holdSfx(String assetPath) {
    _sfxBlocker = Completer<void>();
    _sfxComplete = Completer<void>();
    _heldSfxAssetPath = assetPath;
  }

  void releaseSfx() {
    _sfxBlocker?.complete();
    _sfxBlocker = null;
    _heldSfxAssetPath = null;
  }

  Future<void> waitForHeldSfxComplete() async {
    await _sfxComplete?.future;
  }
```

Replace the fake backend `playSfx` method with:

```dart
  @override
  Future<void> playSfx(AudioCue cue, {required double volume}) async {
    calls.add('playSfx:${cue.assetPath}:$volume');
    try {
      if (_heldSfxAssetPath == cue.assetPath) {
        await _sfxBlocker?.future;
      }
    } finally {
      _sfxComplete?.complete();
      _sfxComplete = null;
    }
  }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
flutter test test/audio_service_test.dart --plain-name "AudioService starts SFX without waiting for completion"
```

Expected: FAIL because `AudioService.startSfx` does not exist.

- [ ] **Step 3: Add the minimal implementation**

In `lib/src/audio_service.dart`, replace `playSfx` with:

```dart
  Future<bool> playSfx(String id, {double volume = 1}) async {
    _checkVolume(volume);

    if (_disposed) {
      return false;
    }

    final cue = catalog.sfxCue(id);
    if (cue == null || !_canPlaySfx(id, cue)) {
      return false;
    }

    _lastSfxPlayAt[id] = DateTime.now();
    _activeSfxInstances[id] = (_activeSfxInstances[id] ?? 0) + 1;
    try {
      await _playSfxAndRelease(
        id,
        cue,
        _effectiveVolume(AudioBus.sfx, cue, volume),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
```

Add this method after `playSfx`:

```dart
  Future<bool> startSfx(String id, {double volume = 1}) async {
    _checkVolume(volume);

    if (_disposed) {
      return false;
    }

    final cue = catalog.sfxCue(id);
    if (cue == null || !_canPlaySfx(id, cue)) {
      return false;
    }

    _lastSfxPlayAt[id] = DateTime.now();
    _activeSfxInstances[id] = (_activeSfxInstances[id] ?? 0) + 1;
    unawaited(
      _playSfxAndRelease(
        id,
        cue,
        _effectiveVolume(AudioBus.sfx, cue, volume),
      ).catchError((Object _) {}),
    );
    return true;
  }
```

Add this helper before `_releaseSfxInstance`:

```dart
  Future<void> _playSfxAndRelease(
    String id,
    AudioCue cue,
    double effectiveVolume,
  ) async {
    try {
      await backend.playSfx(cue, volume: effectiveVolume);
    } finally {
      _releaseSfxInstance(id);
    }
  }
```

- [ ] **Step 4: Run the focused test**

Run:

```powershell
flutter test test/audio_service_test.dart --plain-name "AudioService starts SFX without waiting for completion"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/audio_service.dart test/audio_service_test.dart
git commit -m "feat: add fire-and-forget sfx"
```

---

### Task 2: Make preload and playback failures safe

**Files:**
- Modify: `lib/src/audio_service.dart`
- Test: `test/audio_service_test.dart`

- [ ] **Step 1: Write failing tests**

Add these tests before `AudioService forwards preload pause resume and dispose to backend`:

```dart
  test('AudioService continues preload when one cue fails', () async {
    final catalog = AudioCatalog(
      bgm: {'gameplay': AudioCue.asset('assets/sounds/gameplay_bgm.mp3')},
      sfx: {
        'missing': AudioCue.asset('assets/sounds/missing.wav'),
        'ui_button': AudioCue.asset('assets/sounds/ui_button.wav'),
      },
    );
    final backend = _FakeAudioBackend()
      ..failPreload('assets/sounds/missing.wav');
    final audio = AudioService(backend: backend, catalog: catalog);

    await audio.preloadAll();

    expect(backend.calls, [
      'preload:assets/sounds/gameplay_bgm.mp3',
      'preload:assets/sounds/missing.wav',
      'preload:assets/sounds/ui_button.wav',
    ]);
  });

  test('AudioService returns false when SFX playback fails', () async {
    final catalog = AudioCatalog(
      sfx: {
        'ui_button': AudioCue.asset(
          'assets/sounds/ui_button.wav',
          maxInstances: 1,
        ),
      },
    );
    final backend = _FakeAudioBackend()
      ..failSfx('assets/sounds/ui_button.wav');
    final audio = AudioService(backend: backend, catalog: catalog);

    expect(await audio.playSfx('ui_button'), isFalse);

    backend.clearFailures();

    expect(await audio.playSfx('ui_button'), isTrue);
    expect(backend.calls, [
      'playSfx:assets/sounds/ui_button.wav:1.0',
      'playSfx:assets/sounds/ui_button.wav:1.0',
    ]);
  });

  test('AudioService returns null when looping SFX playback fails', () async {
    final catalog = AudioCatalog(
      sfx: {'footstep': AudioCue.asset('assets/sounds/footstep.wav')},
    );
    final backend = _FakeAudioBackend()
      ..failLoopingSfx('assets/sounds/footstep.wav');
    final audio = AudioService(backend: backend, catalog: catalog);

    expect(await audio.playLoopingSfx('footstep'), isNull);
  });

  test('AudioService returns false when BGM playback fails', () async {
    final catalog = AudioCatalog(
      bgm: {'gameplay': AudioCue.asset('assets/sounds/gameplay_bgm.mp3')},
    );
    final backend = _FakeAudioBackend()
      ..failBgm('assets/sounds/gameplay_bgm.mp3');
    final audio = AudioService(backend: backend, catalog: catalog);

    expect(await audio.playBgm('gameplay'), isFalse);

    backend.clearFailures();

    expect(await audio.playBgm('gameplay'), isTrue);
  });
```

Replace the existing fake backend SFX hold fields and helpers with:

```dart
  final _failedPreloads = <String>{};
  final _failedSfx = <String>{};
  final _failedLoopingSfx = <String>{};
  final _failedBgm = <String>{};

  void failPreload(String assetPath) {
    _failedPreloads.add(assetPath);
  }

  void failSfx(String assetPath) {
    _failedSfx.add(assetPath);
  }

  void failLoopingSfx(String assetPath) {
    _failedLoopingSfx.add(assetPath);
  }

  void failBgm(String assetPath) {
    _failedBgm.add(assetPath);
  }

  void clearFailures() {
    _failedPreloads.clear();
    _failedSfx.clear();
    _failedLoopingSfx.clear();
    _failedBgm.clear();
  }
```

Update fake backend methods:

```dart
  @override
  Future<void> preload(AudioCue cue) async {
    calls.add('preload:${cue.assetPath}');
    if (_failedPreloads.contains(cue.assetPath)) {
      throw StateError('missing ${cue.assetPath}');
    }
  }
```

```dart
  @override
  Future<void> playBgm(
    AudioCue cue, {
    required double volume,
    required bool loop,
  }) async {
    calls.add('playBgm:${cue.assetPath}:$volume:$loop');
    if (_failedBgm.contains(cue.assetPath)) {
      throw StateError('missing ${cue.assetPath}');
    }
    await _playBgmBlocker?.future;
    if (!isDisposed) {
      currentBgmAssetPath = cue.assetPath;
    }
  }
```

```dart
  @override
  Future<void> playSfx(AudioCue cue, {required double volume}) async {
    calls.add('playSfx:${cue.assetPath}:$volume');
    if (_failedSfx.contains(cue.assetPath)) {
      throw StateError('missing ${cue.assetPath}');
    }
    try {
      if (_heldSfxAssetPath == cue.assetPath) {
        await _sfxBlocker?.future;
      }
    } finally {
      _sfxComplete?.complete();
      _sfxComplete = null;
    }
  }
```

```dart
  @override
  Future<AudioLoopHandle> playLoopingSfx(
    AudioCue cue, {
    required double volume,
  }) async {
    calls.add('playLoopingSfx:${cue.assetPath}:$volume');
    if (_failedLoopingSfx.contains(cue.assetPath)) {
      throw StateError('missing ${cue.assetPath}');
    }
    return _FakeAudioLoopHandle(calls, cue.assetPath);
  }
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
flutter test test/audio_service_test.dart --plain-name "AudioService continues preload when one cue fails"
flutter test test/audio_service_test.dart --plain-name "AudioService returns false when SFX playback fails"
flutter test test/audio_service_test.dart --plain-name "AudioService returns null when looping SFX playback fails"
flutter test test/audio_service_test.dart --plain-name "AudioService returns false when BGM playback fails"
```

Expected: at least preload, looping SFX, and BGM tests fail before implementation.

- [ ] **Step 3: Implement safe fallback**

In `lib/src/audio_service.dart`, replace `preloadAll` with:

```dart
  Future<void> preloadAll() async {
    if (_disposed) {
      return;
    }

    for (final cue in [...catalog.bgm.values, ...catalog.sfx.values]) {
      try {
        await backend.preload(cue);
      } catch (_) {}
    }
  }
```

In `playBgm`, wrap the existing body after cue lookup with a `try`/`catch` and return `false` on failure. The method shape should become:

```dart
  Future<bool> playBgm(
    String id, {
    bool loop = true,
    double volume = 1,
    Duration fadeIn = Duration.zero,
  }) async {
    _checkVolume(volume);

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
            ? _effectiveVolume(AudioBus.bgm, cue, volume)
            : 0;
        await backend.playBgm(cue, volume: startedVolume, loop: loop);
      });
      if (!_isCurrentFade(generation)) {
        return false;
      }

      _hasActiveBgm = true;
      _activeBgmCue = cue;
      _activeBgmCallVolume = volume;
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
```

In `playLoopingSfx`, replace the catch block with:

```dart
    } catch (_) {
      _releaseSfxInstance(id);
      return null;
    }
```

- [ ] **Step 4: Run focused tests**

Run:

```powershell
flutter test test/audio_service_test.dart --plain-name "AudioService continues preload when one cue fails"
flutter test test/audio_service_test.dart --plain-name "AudioService returns false when SFX playback fails"
flutter test test/audio_service_test.dart --plain-name "AudioService returns null when looping SFX playback fails"
flutter test test/audio_service_test.dart --plain-name "AudioService returns false when BGM playback fails"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/audio_service.dart test/audio_service_test.dart
git commit -m "fix: ignore missing audio assets"
```

---

### Task 3: Add variation cues

**Files:**
- Modify: `lib/src/audio_cue.dart`
- Modify: `lib/src/audio_service.dart`
- Test: `test/audio_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Add this test near the catalog contract test:

```dart
  test('AudioCue supports variation assets', () {
    final cue = AudioCue.assets([
      'assets/sounds/ui_button_1.wav',
      'assets/sounds/ui_button_2.wav',
    ], volume: 0.7);

    expect(cue.assetPath, 'assets/sounds/ui_button_1.wav');
    expect(cue.assetPaths, [
      'assets/sounds/ui_button_1.wav',
      'assets/sounds/ui_button_2.wav',
    ]);
    expect(cue.volume, 0.7);
  });
```

Add this service test before the cooldown test:

```dart
  test('AudioService avoids immediate variation repeats', () async {
    final catalog = AudioCatalog(
      sfx: {
        'ui_button': AudioCue.assets([
          'assets/sounds/ui_button_1.wav',
          'assets/sounds/ui_button_2.wav',
        ]),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = AudioService(backend: backend, catalog: catalog);

    expect(await audio.playSfx('ui_button'), isTrue);
    expect(await audio.playSfx('ui_button'), isTrue);

    expect(backend.calls.length, 2);
    expect(backend.calls[0], isNot(equals(backend.calls[1])));
  });
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
flutter test test/audio_service_test.dart --plain-name "AudioCue supports variation assets"
flutter test test/audio_service_test.dart --plain-name "AudioService avoids immediate variation repeats"
```

Expected: FAIL because `AudioCue.assets` and `assetPaths` do not exist.

- [ ] **Step 3: Implement cue variations**

Replace `lib/src/audio_cue.dart` with:

```dart
final class AudioCue {
  const AudioCue.asset(
    this.assetPath, {
    this.volume = 1,
    this.cooldown = Duration.zero,
    this.maxInstances,
  }) : _assetPaths = const [],
       assert(assetPath.length > 0),
       assert(volume >= 0 && volume <= 1),
       assert(maxInstances == null || maxInstances > 0);

  AudioCue.assets(
    List<String> assetPaths, {
    this.volume = 1,
    this.cooldown = Duration.zero,
    this.maxInstances,
  }) : assert(assetPaths.length > 0),
       assert(!assetPaths.contains('')),
       assetPath = assetPaths.first,
       _assetPaths = List.unmodifiable(assetPaths),
       assert(volume >= 0 && volume <= 1),
       assert(maxInstances == null || maxInstances > 0);

  const AudioCue._selected(
    this.assetPath, {
    required this.volume,
    required this.cooldown,
    required this.maxInstances,
  }) : _assetPaths = const [];

  final String assetPath;
  final double volume;
  final Duration cooldown;
  final int? maxInstances;
  final List<String> _assetPaths;

  List<String> get assetPaths =>
      _assetPaths.isEmpty ? <String>[assetPath] : _assetPaths;

  AudioCue selectedAsset(String assetPath) {
    return AudioCue._selected(
      assetPath,
      volume: volume,
      cooldown: cooldown,
      maxInstances: maxInstances,
    );
  }
}
```

In `lib/src/audio_service.dart`, add this field next to `_lastSfxPlayAt`:

```dart
  final _lastSfxAssetPath = <String, String>{};
```

In `playSfx`, after `_canPlaySfx` passes and before `_lastSfxPlayAt[id] = DateTime.now();`, add:

```dart
    final selectedCue = _selectSfxCue(id, cue);
```

Then pass `selectedCue` to `_playSfxAndRelease` and `_effectiveVolume`:

```dart
      await _playSfxAndRelease(
        id,
        selectedCue,
        _effectiveVolume(AudioBus.sfx, selectedCue, volume),
      );
```

Do the same in `startSfx` and `playLoopingSfx`.

Add this helper before `_canPlaySfx`:

```dart
  AudioCue _selectSfxCue(String id, AudioCue cue) {
    final assetPaths = cue.assetPaths;
    if (assetPaths.length == 1) {
      return cue;
    }

    var selectedPath = assetPaths[DateTime.now().microsecondsSinceEpoch % assetPaths.length];
    final lastPath = _lastSfxAssetPath[id];
    if (selectedPath == lastPath) {
      final selectedIndex = assetPaths.indexOf(selectedPath);
      selectedPath = assetPaths[(selectedIndex + 1) % assetPaths.length];
    }
    _lastSfxAssetPath[id] = selectedPath;
    return cue.selectedAsset(selectedPath);
  }
```

In `dispose`, clear variation memory:

```dart
    _lastSfxAssetPath.clear();
```

- [ ] **Step 4: Preload all variation assets**

In `preloadAll`, replace the backend call with:

```dart
      for (final assetPath in cue.assetPaths) {
        try {
          await backend.preload(cue.selectedAsset(assetPath));
        } catch (_) {}
      }
```

- [ ] **Step 5: Run focused tests**

Run:

```powershell
flutter test test/audio_service_test.dart --plain-name "AudioCue supports variation assets"
flutter test test/audio_service_test.dart --plain-name "AudioService avoids immediate variation repeats"
flutter test test/audio_service_test.dart --plain-name "AudioService continues preload when one cue fails"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/audio_cue.dart lib/src/audio_service.dart test/audio_service_test.dart
git commit -m "feat: add variation audio cues"
```

---

### Task 4: Add `stopAllSfx()`

**Files:**
- Modify: `lib/src/audio_backend.dart`
- Modify: `lib/src/audio_service.dart`
- Modify: `lib/src/audioplayers_audio_backend.dart`
- Test: `test/audio_service_test.dart`
- Test: `test/flame_audio_adapter_test.dart`

- [ ] **Step 1: Write failing service and contract tests**

Add this service test before `AudioService forwards preload pause resume and dispose to backend`:

```dart
  test('AudioService stops all SFX and clears active instance tracking', () async {
    final catalog = AudioCatalog(
      sfx: {
        'ui_button': AudioCue.asset(
          'assets/sounds/ui_button.wav',
          maxInstances: 1,
        ),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = AudioService(backend: backend, catalog: catalog);

    backend.holdSfx('assets/sounds/ui_button.wav');
    expect(await audio.startSfx('ui_button'), isTrue);
    expect(await audio.startSfx('ui_button'), isFalse);

    await audio.stopAllSfx();

    expect(await audio.startSfx('ui_button'), isTrue);
    expect(backend.calls, [
      'playSfx:assets/sounds/ui_button.wav:1.0',
      'stopAllSfx',
      'playSfx:assets/sounds/ui_button.wav:1.0',
    ]);
  });
```

Update the backend contract test expected calls by inserting `stopAllSfx` before `pauseAll`:

```dart
      await backend.stopAllSfx();
```

```dart
      expect(backend.calls, [
        'preload:assets/sounds/gameplay_bgm.mp3',
        'playBgm:assets/sounds/gameplay_bgm.mp3:0.7:true',
        'playSfx:assets/sounds/ui_button.wav:1.0',
        'playLoopingSfx:assets/sounds/ui_button.wav:0.5',
        'stopLoopingSfx:assets/sounds/ui_button.wav',
        'stopAllSfx',
        'pauseAll',
        'resumeAll',
        'stopBgm',
        'dispose',
      ]);
```

Add this fake backend method in both test files:

```dart
  @override
  Future<void> stopAllSfx() async {
    calls.add('stopAllSfx');
  }
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
flutter test test/audio_service_test.dart --plain-name "AudioService stops all SFX and clears active instance tracking"
flutter test test/audio_service_test.dart test/flame_audio_adapter_test.dart
```

Expected: FAIL because `stopAllSfx` does not exist on the contract.

- [ ] **Step 3: Add backend contract and service method**

In `lib/src/audio_backend.dart`, add this after `playLoopingSfx`:

```dart
  Future<void> stopAllSfx();
```

In `lib/src/audio_service.dart`, add this method before `pauseAll`:

```dart
  Future<void> stopAllSfx() async {
    if (_disposed) {
      return;
    }

    _activeSfxInstances.clear();
    await backend.stopAllSfx();
  }
```

In `dispose`, keep `_activeSfxInstances.clear();` as-is.

- [ ] **Step 4: Implement audioplayers backend stop**

In `lib/src/audioplayers_audio_backend.dart`, add this field next to `_disposed`:

```dart
  Completer<void> _sfxStopped = Completer<void>();
```

In `playSfx`, replace the wait and finally block with:

```dart
    try {
      await player.setReleaseMode(ReleaseMode.release);
      await player.play(_assetSource(cue), volume: volume);
      await Future.any([
        player.onPlayerComplete.first,
        _disposed.future,
        _sfxStopped.future,
      ]);
    } finally {
      if (_sfxPlayers.remove(player)) {
        await player.dispose();
      }
    }
```

Add this method after `playLoopingSfx`:

```dart
  @override
  Future<void> stopAllSfx() async {
    if (!_sfxStopped.isCompleted) {
      _sfxStopped.complete();
    }
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
```

Replace the entire `dispose` method with:

```dart
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
```

- [ ] **Step 5: Run focused tests**

Run:

```powershell
flutter test test/audio_service_test.dart --plain-name "AudioService stops all SFX and clears active instance tracking"
flutter test test/audio_service_test.dart test/flame_audio_adapter_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/audio_backend.dart lib/src/audio_service.dart lib/src/audioplayers_audio_backend.dart test/audio_service_test.dart test/flame_audio_adapter_test.dart
git commit -m "feat: add stop all sfx"
```

---

### Task 5: Add optional global SFX limit

**Files:**
- Modify: `lib/src/audio_service.dart`
- Test: `test/audio_service_test.dart`

- [ ] **Step 1: Write the failing test**

Add this test before `AudioService limits SFX overlap per cue by max instances`:

```dart
  test('AudioService drops SFX above the global active limit', () async {
    final catalog = AudioCatalog(
      sfx: {
        'ui_button': AudioCue.asset('assets/sounds/ui_button.wav'),
        'footstep': AudioCue.asset('assets/sounds/oncha_footstep.wav'),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = AudioService(
      backend: backend,
      catalog: catalog,
      maxConcurrentSfx: 1,
    );

    backend.holdSfx('assets/sounds/ui_button.wav');

    expect(await audio.startSfx('ui_button'), isTrue);
    expect(await audio.startSfx('footstep'), isFalse);

    backend.releaseSfx();
    await backend.waitForHeldSfxComplete();

    expect(await audio.startSfx('footstep'), isTrue);
    expect(backend.calls, [
      'playSfx:assets/sounds/ui_button.wav:1.0',
      'playSfx:assets/sounds/oncha_footstep.wav:1.0',
    ]);
  });
```

- [ ] **Step 2: Run the test to verify failure**

Run:

```powershell
flutter test test/audio_service_test.dart --plain-name "AudioService drops SFX above the global active limit"
```

Expected: FAIL because `maxConcurrentSfx` does not exist.

- [ ] **Step 3: Implement the global cap**

In `lib/src/audio_service.dart`, replace the constructor with:

```dart
  AudioService({
    required this.backend,
    required this.catalog,
    this.maxConcurrentSfx,
  }) : assert(maxConcurrentSfx == null || maxConcurrentSfx > 0);
```

Add this field after `catalog`:

```dart
  final int? maxConcurrentSfx;
```

Add this field next to `_activeSfxInstances`:

```dart
  int _activeSfxCount = 0;
```

In `_canPlaySfx`, add this check first:

```dart
    final maxConcurrentSfx = this.maxConcurrentSfx;
    if (maxConcurrentSfx != null && _activeSfxCount >= maxConcurrentSfx) {
      return false;
    }
```

After each line that increments `_activeSfxInstances[id]`, add:

```dart
    _activeSfxCount++;
```

Replace `_releaseSfxInstance` with:

```dart
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
```

In `stopAllSfx` and `dispose`, after `_activeSfxInstances.clear();`, add:

```dart
    _activeSfxCount = 0;
```

- [ ] **Step 4: Run focused tests**

Run:

```powershell
flutter test test/audio_service_test.dart --plain-name "AudioService drops SFX above the global active limit"
flutter test test/audio_service_test.dart --plain-name "AudioService limits SFX overlap per cue by max instances"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/audio_service.dart test/audio_service_test.dart
git commit -m "feat: add global sfx limit"
```

---

### Task 6: Document and verify the package API

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README examples**

Replace `README.md` with:

````markdown
# honeycube_game_audio

Shared audio service package for Honeycube Flutter and Flame games.

This package intentionally does not provide a singleton or service locator.
Game code owns cue IDs and game-specific event mapping.

```dart
final audio = AudioService(
  backend: AudioplayersAudioBackend(),
  catalog: AudioCatalog(
    sfx: {
      'ui_button': AudioCue.assets([
        'sounds/ui_button_1.wav',
        'sounds/ui_button_2.wav',
      ]),
      'footstep': AudioCue.asset('sounds/footstep.wav', maxInstances: 1),
    },
  ),
  maxConcurrentSfx: 6,
);

await audio.startSfx('ui_button');

final footsteps = await audio.playLoopingSfx('footstep');
await footsteps?.stop();

await audio.stopAllSfx();
```
````

- [ ] **Step 2: Format changed Dart files**

Run:

```powershell
dart format lib/src/audio_backend.dart lib/src/audio_cue.dart lib/src/audio_service.dart lib/src/audioplayers_audio_backend.dart test/audio_service_test.dart test/flame_audio_adapter_test.dart
```

Expected: files are formatted.

- [ ] **Step 3: Analyze changed scope**

Run:

```powershell
dart analyze lib/src/audio_backend.dart lib/src/audio_bus.dart lib/src/audio_catalog.dart lib/src/audio_cue.dart lib/src/audio_service.dart lib/src/audioplayers_audio_backend.dart lib/src/flame_audio_adapter.dart test/audio_service_test.dart test/flame_audio_adapter_test.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Run focused tests**

Run:

```powershell
flutter test test/audio_service_test.dart test/flame_audio_adapter_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add README.md lib/src/audio_backend.dart lib/src/audio_cue.dart lib/src/audio_service.dart lib/src/audioplayers_audio_backend.dart test/audio_service_test.dart test/flame_audio_adapter_test.dart
git commit -m "docs: document common sfx APIs"
```

## Self-Review

- Spec coverage: `startSfx()` covers fire-and-forget SFX; safe `preloadAll` and playback catches cover missing asset fallback; `AudioCue.assets` covers variation with immediate repeat avoidance; `stopAllSfx()` covers lifecycle cleanup; `maxConcurrentSfx` covers Brick's default global limit without hardcoding Brick policy.
- Placeholder scan: no deferred placeholders or vague test instructions remain.
- Type consistency: public names are `startSfx`, `playSfx`, `playLoopingSfx`, `stopAllSfx`, `AudioCue.assets`, and `maxConcurrentSfx` across service, backend, tests, and README.
- Deferred: priority preemption is skipped; add it only when dropping newest SFX is measurably not good enough.
