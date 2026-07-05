import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:honeycube_game_audio/honeycube_game_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'core catalog and backend contract are usable without playback policy',
    () async {
      final catalog = HCAudioCatalog(
        bgm: {'gameplay': HCAudioCue.asset('assets/sounds/gameplay_bgm.mp3')},
        sfx: {
          'ui_button': HCAudioCue.asset(
            'assets/sounds/ui_button.wav',
            cooldown: Duration(milliseconds: 120),
            maxInstances: 2,
          ),
        },
      );
      final backend = _FakeAudioBackend();

      expect(HCAudioBus.values, [
        HCAudioBus.master,
        HCAudioBus.bgm,
        HCAudioBus.sfx,
      ]);
      expect(
        catalog.bgmCue('gameplay')?.assetPath,
        'assets/sounds/gameplay_bgm.mp3',
      );
      expect(
        catalog.sfxCue('ui_button')?.cooldown,
        Duration(milliseconds: 120),
      );
      expect(catalog.sfxCue('ui_button')?.maxInstances, 2);

      await backend.preload(catalog.bgmCue('gameplay')!);
      await backend.playBgm(
        catalog.bgmCue('gameplay')!,
        volume: 0.7,
        loop: true,
      );
      await backend.playSfx(catalog.sfxCue('ui_button')!, volume: 1);
      final loopingSfx = await backend.playLoopingSfx(
        catalog.sfxCue('ui_button')!,
        volume: 0.5,
      );
      await loopingSfx.stop();
      await backend.stopAllSfx();
      await backend.pauseAll();
      await backend.resumeAll();
      await backend.stopBgm();
      await backend.dispose();

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
    },
  );

  test('HCAudioCue supports variation assets', () {
    final cue = HCAudioCue.assets([
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

  test(
    'HCAudioService plays one active BGM and stops it before replacing',
    () async {
      final catalog = HCAudioCatalog(
        bgm: {
          'gameplay': HCAudioCue.asset(
            'assets/sounds/gameplay_bgm.mp3',
            volume: 0.8,
          ),
          'menu': HCAudioCue.asset('assets/sounds/menu_bgm.mp3'),
        },
      );
      final backend = _FakeAudioBackend();
      final audio = HCAudioService(backend: backend, catalog: catalog);

      audio.setBusVolume(HCAudioBus.master, 0.5);
      audio.setBusVolume(HCAudioBus.bgm, 0.5);

      expect(await audio.playBgm('gameplay'), isTrue);
      expect(await audio.playBgm('menu', loop: false), isTrue);

      expect(backend.calls, [
        'playBgm:assets/sounds/gameplay_bgm.mp3:0.2:true',
        'stopBgm',
        'playBgm:assets/sounds/menu_bgm.mp3:0.25:false',
      ]);
    },
  );

  test('HCAudioService uses configured member volumes for playback', () async {
    final catalog = HCAudioCatalog(
      bgm: {
        'gameplay': HCAudioCue.asset(
          'assets/sounds/gameplay_bgm.mp3',
          volume: 0.8,
        ),
      },
      sfx: {
        'ui_button': HCAudioCue.asset(
          'assets/sounds/ui_button.wav',
          volume: 0.6,
        ),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(
      backend: backend,
      catalog: catalog,
      masterVolume: 0.5,
      bgmVolume: 0.25,
      sfxVolume: 0.75,
    );

    expect(await audio.playBgm('gameplay'), isTrue);
    expect(await audio.playSfx('ui_button'), isTrue);

    expect(backend.calls, [
      'playBgm:assets/sounds/gameplay_bgm.mp3:0.1:true',
      'playSfx:assets/sounds/ui_button.wav:0.22499999999999998',
    ]);
  });

  test('HCAudioService does not call backend for missing BGM cue', () async {
    final audio = HCAudioService(
      backend: _FakeAudioBackend(),
      catalog: HCAudioCatalog(),
    );

    expect(await audio.playBgm('missing'), isFalse);
  });

  test('HCAudioService applies master and bgm mute to BGM volume', () async {
    final catalog = HCAudioCatalog(
      bgm: {'gameplay': HCAudioCue.asset('assets/sounds/gameplay_bgm.mp3')},
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(backend: backend, catalog: catalog);

    audio.setMuted(true);
    expect(await audio.playBgm('gameplay'), isTrue);
    await audio.stopBgm();

    audio.setMuted(false);
    audio.setMuted(true, bus: HCAudioBus.bgm);
    expect(await audio.playBgm('gameplay'), isTrue);

    expect(backend.calls, [
      'playBgm:assets/sounds/gameplay_bgm.mp3:0.0:true',
      'stopBgm',
      'playBgm:assets/sounds/gameplay_bgm.mp3:0.0:true',
    ]);
  });

  test('HCAudioService fades BGM in from zero to target volume', () async {
    final catalog = HCAudioCatalog(
      bgm: {
        'gameplay': HCAudioCue.asset(
          'assets/sounds/gameplay_bgm.mp3',
          volume: 0.8,
        ),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(backend: backend, catalog: catalog);

    audio.setBusVolume(HCAudioBus.master, 0.5);

    expect(
      await audio.playBgm('gameplay', fadeIn: Duration(milliseconds: 1)),
      isTrue,
    );

    expect(
      backend.calls.first,
      'playBgm:assets/sounds/gameplay_bgm.mp3:0.0:true',
    );
    expect(backend.calls.last, 'setBgmVolume:0.4');
  });

  test('HCAudioService fades BGM out before stopping', () async {
    final catalog = HCAudioCatalog(
      bgm: {'gameplay': HCAudioCue.asset('assets/sounds/gameplay_bgm.mp3')},
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(backend: backend, catalog: catalog);

    expect(await audio.playBgm('gameplay'), isTrue);
    await audio.stopBgm(fadeOut: Duration(milliseconds: 1));

    expect(backend.calls.last, 'stopBgm');
    expect(backend.calls[backend.calls.length - 2], 'setBgmVolume:0.0');
  });

  test(
    'HCAudioService stops late BGM play when stop arrives while backend awaits',
    () async {
      final catalog = HCAudioCatalog(
        bgm: {'gameplay': HCAudioCue.asset('assets/sounds/gameplay_bgm.mp3')},
      );
      final backend = _FakeAudioBackend()..holdPlayBgm();
      final audio = HCAudioService(backend: backend, catalog: catalog);

      final play = audio.playBgm('gameplay', fadeIn: Duration(milliseconds: 1));
      await Future<void>.delayed(Duration.zero);

      final stop = audio.stopBgm();
      backend.releasePlayBgm();

      expect(await play, isFalse);
      await stop;

      expect(backend.calls, [
        'playBgm:assets/sounds/gameplay_bgm.mp3:0.0:true',
        'stopBgm',
      ]);
      expect(backend.currentBgmAssetPath, isNull);
    },
  );

  test(
    'HCAudioService disposes after late BGM play when dispose arrives while backend awaits',
    () async {
      final catalog = HCAudioCatalog(
        bgm: {'gameplay': HCAudioCue.asset('assets/sounds/gameplay_bgm.mp3')},
      );
      final backend = _FakeAudioBackend()..holdPlayBgm();
      final audio = HCAudioService(backend: backend, catalog: catalog);

      final play = audio.playBgm('gameplay');
      await Future<void>.delayed(Duration.zero);

      final dispose = audio.dispose();
      backend.releasePlayBgm();

      expect(await play, isFalse);
      await dispose;

      expect(backend.calls, [
        'playBgm:assets/sounds/gameplay_bgm.mp3:1.0:true',
        'dispose',
      ]);
      expect(backend.isDisposed, isTrue);
      expect(backend.currentBgmAssetPath, isNull);
    },
  );

  test('HCAudioService plays latest BGM after queued stop completes', () async {
    final catalog = HCAudioCatalog(
      bgm: {
        'gameplay': HCAudioCue.asset('assets/sounds/gameplay_bgm.mp3'),
        'menu': HCAudioCue.asset('assets/sounds/menu_bgm.mp3'),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(backend: backend, catalog: catalog);

    expect(await audio.playBgm('gameplay'), isTrue);

    backend.holdStopBgm();
    final stop = audio.stopBgm();
    await Future<void>.delayed(Duration.zero);
    final play = audio.playBgm('menu');

    backend.releaseStopBgm();

    await stop;
    expect(await play, isTrue);

    expect(backend.calls, [
      'playBgm:assets/sounds/gameplay_bgm.mp3:1.0:true',
      'stopBgm',
      'playBgm:assets/sounds/menu_bgm.mp3:1.0:true',
    ]);
    expect(backend.currentBgmAssetPath, 'assets/sounds/menu_bgm.mp3');
  });

  test('HCAudioService missing BGM cue does not cancel active fade', () async {
    final catalog = HCAudioCatalog(
      bgm: {
        'gameplay': HCAudioCue.asset(
          'assets/sounds/gameplay_bgm.mp3',
          volume: 0.8,
        ),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(backend: backend, catalog: catalog);

    final fade = audio.playBgm('gameplay', fadeIn: Duration(milliseconds: 20));
    await Future<void>.delayed(Duration.zero);

    expect(await audio.playBgm('missing'), isFalse);
    expect(await fade, isTrue);

    expect(backend.calls.last, 'setBgmVolume:0.8');
  });

  test(
    'HCAudioService updates active BGM volume from bus changes only',
    () async {
      final catalog = HCAudioCatalog(
        bgm: {
          'gameplay': HCAudioCue.asset(
            'assets/sounds/gameplay_bgm.mp3',
            volume: 0.8,
          ),
        },
      );
      final backend = _FakeAudioBackend();
      final audio = HCAudioService(backend: backend, catalog: catalog);

      expect(await audio.playBgm('gameplay'), isTrue);

      audio.setBusVolume(HCAudioBus.bgm, 0.5);
      audio.setBusVolume(HCAudioBus.sfx, 0.1);
      audio.setMuted(true, bus: HCAudioBus.bgm);
      await Future<void>.delayed(Duration.zero);

      expect(backend.calls, [
        'playBgm:assets/sounds/gameplay_bgm.mp3:0.8:true',
        'setBgmVolume:0.0',
      ]);
    },
  );

  test('HCAudioService applies latest queued BGM volume sync last', () async {
    final catalog = HCAudioCatalog(
      bgm: {
        'gameplay': HCAudioCue.asset(
          'assets/sounds/gameplay_bgm.mp3',
          volume: 0.8,
        ),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(backend: backend, catalog: catalog);

    expect(await audio.playBgm('gameplay'), isTrue);

    backend.holdBgmVolumeSets(2);
    audio.setBusVolume(HCAudioBus.bgm, 0.5);
    await backend.waitForBgmVolumeSetAttempt(1);
    audio.setMuted(true, bus: HCAudioBus.bgm);

    backend.releaseBgmVolumeSet(0);
    await backend.waitForBgmVolumeSetAttempt(2);
    backend.releaseBgmVolumeSet(1);
    await _waitForBgmVolumeCount(backend, 2);

    expect(backend.bgmVolumes.last, 0.0);
  });

  test(
    'HCAudioService fade-in ends at BGM volume changed during fade',
    () async {
      final catalog = HCAudioCatalog(
        bgm: {
          'gameplay': HCAudioCue.asset(
            'assets/sounds/gameplay_bgm.mp3',
            volume: 0.8,
          ),
        },
      );
      final backend = _FakeAudioBackend();
      final audio = HCAudioService(backend: backend, catalog: catalog);

      final fade = audio.playBgm(
        'gameplay',
        fadeIn: Duration(milliseconds: 20),
      );
      await _waitForSetBgmVolume(backend);

      audio.setBusVolume(HCAudioBus.bgm, 0.5);
      final changedAt = backend.bgmVolumes.length - 1;
      expect(await fade, isTrue);

      expect(backend.calls.last, 'setBgmVolume:0.4');
      expect(
        backend.bgmVolumes.skip(changedAt),
        everyElement(lessThanOrEqualTo(0.401)),
      );
    },
  );

  test('HCAudioService syncs fade-in BGM volume at current progress', () async {
    final catalog = HCAudioCatalog(
      bgm: {
        'gameplay': HCAudioCue.asset(
          'assets/sounds/gameplay_bgm.mp3',
          volume: 0.8,
        ),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(backend: backend, catalog: catalog);

    final fade = audio.playBgm('gameplay', fadeIn: Duration(milliseconds: 20));
    await _waitForSetBgmVolume(backend);

    audio.setBusVolume(HCAudioBus.bgm, 0.5);
    await Future<void>.delayed(Duration.zero);

    expect(backend.bgmVolumes.last, lessThanOrEqualTo(0.4));
    expect(await fade, isTrue);
    expect(backend.bgmVolumes.last, closeTo(0.4, 0.001));
  });

  test(
    'HCAudioService fade-in stays muted after BGM mute during fade',
    () async {
      final catalog = HCAudioCatalog(
        bgm: {
          'gameplay': HCAudioCue.asset(
            'assets/sounds/gameplay_bgm.mp3',
            volume: 0.8,
          ),
        },
      );
      final backend = _FakeAudioBackend();
      final audio = HCAudioService(backend: backend, catalog: catalog);

      final fade = audio.playBgm(
        'gameplay',
        fadeIn: Duration(milliseconds: 20),
      );
      await _waitForSetBgmVolume(backend);

      final mutedAt = backend.bgmVolumes.length;
      audio.setMuted(true, bus: HCAudioBus.bgm);
      expect(await fade, isTrue);

      expect(backend.calls.last, 'setBgmVolume:0.0');
      expect(backend.bgmVolumes.skip(mutedAt), everyElement(closeTo(0, 0.001)));
    },
  );

  test(
    'HCAudioService overlaps same SFX cue when no cooldown or max instances',
    () async {
      final catalog = HCAudioCatalog(
        sfx: {
          'ui_button': HCAudioCue.asset(
            'assets/sounds/ui_button.wav',
            volume: 0.8,
          ),
        },
      );
      final backend = _FakeAudioBackend();
      final audio = HCAudioService(backend: backend, catalog: catalog);

      audio.setBusVolume(HCAudioBus.master, 0.5);
      audio.setBusVolume(HCAudioBus.sfx, 0.5);

      backend.holdSfx('assets/sounds/ui_button.wav');
      final first = audio.playSfx('ui_button');
      await Future<void>.delayed(Duration.zero);
      final second = audio.playSfx('ui_button');
      await Future<void>.delayed(Duration.zero);

      expect(await audio.playSfx('missing'), isFalse);

      expect(backend.calls, [
        'playSfx:assets/sounds/ui_button.wav:0.2',
        'playSfx:assets/sounds/ui_button.wav:0.2',
      ]);

      backend.releaseSfx();
      expect(await first, isTrue);
      expect(await second, isTrue);
    },
  );

  test('HCAudioService applies master and sfx mute to SFX volume', () async {
    final catalog = HCAudioCatalog(
      sfx: {'ui_button': HCAudioCue.asset('assets/sounds/ui_button.wav')},
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(backend: backend, catalog: catalog);

    audio.setMuted(true);
    expect(await audio.playSfx('ui_button'), isTrue);

    audio.setMuted(false);
    audio.setMuted(true, bus: HCAudioBus.sfx);
    expect(await audio.playSfx('ui_button'), isTrue);

    expect(backend.calls, [
      'playSfx:assets/sounds/ui_button.wav:0.0',
      'playSfx:assets/sounds/ui_button.wav:0.0',
    ]);
  });

  test('HCAudioService starts SFX without waiting for completion', () async {
    final catalog = HCAudioCatalog(
      sfx: {
        'ui_button': HCAudioCue.asset(
          'assets/sounds/ui_button.wav',
          maxInstances: 1,
        ),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(backend: backend, catalog: catalog);

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

  test('HCAudioService avoids immediate variation repeats', () async {
    final catalog = HCAudioCatalog(
      sfx: {
        'ui_button': HCAudioCue.assets([
          'assets/sounds/ui_button_1.wav',
          'assets/sounds/ui_button_2.wav',
        ]),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(backend: backend, catalog: catalog);

    expect(await audio.playSfx('ui_button'), isTrue);
    expect(await audio.playSfx('ui_button'), isTrue);

    expect(backend.calls.length, 2);
    expect(backend.calls[0], isNot(equals(backend.calls[1])));
  });

  test('HCAudioService limits SFX replay per cue by cooldown', () async {
    final catalog = HCAudioCatalog(
      sfx: {
        'ui_button': HCAudioCue.asset(
          'assets/sounds/ui_button.wav',
          cooldown: Duration(minutes: 1),
        ),
        'footstep': HCAudioCue.asset(
          'assets/sounds/oncha_footstep.wav',
          cooldown: Duration(minutes: 1),
        ),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(backend: backend, catalog: catalog);

    expect(await audio.playSfx('ui_button'), isTrue);
    expect(await audio.playSfx('ui_button'), isFalse);
    expect(await audio.playSfx('footstep'), isTrue);

    expect(backend.calls, [
      'playSfx:assets/sounds/ui_button.wav:1.0',
      'playSfx:assets/sounds/oncha_footstep.wav:1.0',
    ]);
  });

  test('HCAudioService requires positive global SFX limit', () {
    final backend = _FakeAudioBackend();

    expect(
      () => HCAudioService(
        backend: backend,
        catalog: HCAudioCatalog(),
        maxConcurrentSfx: 0,
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(
      HCAudioService(
        backend: backend,
        catalog: HCAudioCatalog(),
        maxConcurrentSfx: 1,
      ),
      isA<HCAudioService>(),
    );
  });

  test('HCAudioService drops SFX above the global active limit', () async {
    final catalog = HCAudioCatalog(
      sfx: {
        'ui_button': HCAudioCue.asset('assets/sounds/ui_button.wav'),
        'footstep': HCAudioCue.asset('assets/sounds/oncha_footstep.wav'),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(
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
  test('HCAudioService limits SFX overlap per cue by max instances', () async {
    final catalog = HCAudioCatalog(
      sfx: {
        'ui_button': HCAudioCue.asset(
          'assets/sounds/ui_button.wav',
          maxInstances: 1,
        ),
        'footstep': HCAudioCue.asset(
          'assets/sounds/oncha_footstep.wav',
          maxInstances: 1,
        ),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(backend: backend, catalog: catalog);

    backend.holdSfx('assets/sounds/ui_button.wav');
    final first = audio.playSfx('ui_button');
    await Future<void>.delayed(Duration.zero);

    expect(await audio.playSfx('ui_button'), isFalse);
    expect(await audio.playSfx('footstep'), isTrue);

    backend.releaseSfx();
    expect(await first, isTrue);
    expect(await audio.playSfx('ui_button'), isTrue);

    expect(backend.calls, [
      'playSfx:assets/sounds/ui_button.wav:1.0',
      'playSfx:assets/sounds/oncha_footstep.wav:1.0',
      'playSfx:assets/sounds/ui_button.wav:1.0',
    ]);
  });

  test(
    'HCAudioService plays looping SFX until the returned handle stops',
    () async {
      final catalog = HCAudioCatalog(
        sfx: {
          'footstep': HCAudioCue.asset(
            'assets/sounds/oncha_footstep.wav',
            volume: 0.8,
            maxInstances: 1,
          ),
        },
      );
      final backend = _FakeAudioBackend();
      final audio = HCAudioService(backend: backend, catalog: catalog);

      audio.setBusVolume(HCAudioBus.master, 0.5);
      audio.setBusVolume(HCAudioBus.sfx, 0.5);

      final handle = await audio.playLoopingSfx('footstep');

      expect(handle, isNotNull);
      expect(await audio.playLoopingSfx('footstep'), isNull);

      await handle!.stop();
      final secondHandle = await audio.playLoopingSfx('footstep');
      await secondHandle!.stop();

      expect(backend.calls, [
        'playLoopingSfx:assets/sounds/oncha_footstep.wav:0.2',
        'stopLoopingSfx:assets/sounds/oncha_footstep.wav',
        'playLoopingSfx:assets/sounds/oncha_footstep.wav:0.2',
        'stopLoopingSfx:assets/sounds/oncha_footstep.wav',
      ]);
    },
  );

  test('HCAudioService continues preload when one cue fails', () async {
    final catalog = HCAudioCatalog(
      bgm: {'gameplay': HCAudioCue.asset('assets/sounds/gameplay_bgm.mp3')},
      sfx: {
        'missing': HCAudioCue.asset('assets/sounds/missing.wav'),
        'ui_button': HCAudioCue.asset('assets/sounds/ui_button.wav'),
      },
    );
    final backend = _FakeAudioBackend()
      ..failPreload('assets/sounds/missing.wav');
    final audio = HCAudioService(backend: backend, catalog: catalog);

    await audio.preloadAll();

    expect(backend.calls, [
      'preload:assets/sounds/gameplay_bgm.mp3',
      'preload:assets/sounds/missing.wav',
      'preload:assets/sounds/ui_button.wav',
    ]);
  });

  test('HCAudioService preloads all variation assets', () async {
    final catalog = HCAudioCatalog(
      sfx: {
        'ui_button': HCAudioCue.assets([
          'assets/sounds/ui_button_1.wav',
          'assets/sounds/ui_button_2.wav',
        ]),
      },
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(backend: backend, catalog: catalog);

    await audio.preloadAll();

    expect(backend.calls, [
      'preload:assets/sounds/ui_button_1.wav',
      'preload:assets/sounds/ui_button_2.wav',
    ]);
  });

  test('HCAudioService returns false when SFX playback fails', () async {
    final catalog = HCAudioCatalog(
      sfx: {
        'ui_button': HCAudioCue.asset(
          'assets/sounds/ui_button.wav',
          maxInstances: 1,
        ),
      },
    );
    final backend = _FakeAudioBackend()..failSfx('assets/sounds/ui_button.wav');
    final audio = HCAudioService(backend: backend, catalog: catalog);

    expect(await audio.playSfx('ui_button'), isFalse);

    backend.clearFailures();

    expect(await audio.playSfx('ui_button'), isTrue);
    expect(backend.calls, [
      'playSfx:assets/sounds/ui_button.wav:1.0',
      'playSfx:assets/sounds/ui_button.wav:1.0',
    ]);
  });

  test('HCAudioService returns null when looping SFX playback fails', () async {
    final catalog = HCAudioCatalog(
      sfx: {'footstep': HCAudioCue.asset('assets/sounds/footstep.wav')},
    );
    final backend = _FakeAudioBackend()
      ..failLoopingSfx('assets/sounds/footstep.wav');
    final audio = HCAudioService(backend: backend, catalog: catalog);

    expect(await audio.playLoopingSfx('footstep'), isNull);
  });

  test('HCAudioService returns false when BGM playback fails', () async {
    final catalog = HCAudioCatalog(
      bgm: {'gameplay': HCAudioCue.asset('assets/sounds/gameplay_bgm.mp3')},
    );
    final backend = _FakeAudioBackend()
      ..failBgm('assets/sounds/gameplay_bgm.mp3');
    final audio = HCAudioService(backend: backend, catalog: catalog);

    expect(await audio.playBgm('gameplay'), isFalse);

    backend.clearFailures();

    expect(await audio.playBgm('gameplay'), isTrue);
  });
  test(
    'HCAudioService stops all SFX and clears active instance tracking',
    () async {
      final catalog = HCAudioCatalog(
        sfx: {
          'ui_button': HCAudioCue.asset(
            'assets/sounds/ui_button.wav',
            maxInstances: 1,
          ),
        },
      );
      final backend = _FakeAudioBackend();
      final audio = HCAudioService(backend: backend, catalog: catalog);

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
    },
  );

  test(
    'HCAudioService forwards preload pause resume and dispose to backend',
    () async {
      final catalog = HCAudioCatalog(
        bgm: {'gameplay': HCAudioCue.asset('assets/sounds/gameplay_bgm.mp3')},
        sfx: {'ui_button': HCAudioCue.asset('assets/sounds/ui_button.wav')},
      );
      final backend = _FakeAudioBackend();
      final audio = HCAudioService(backend: backend, catalog: catalog);

      await audio.preloadAll();
      await audio.pauseAll();
      await audio.resumeAll();
      await audio.dispose();

      expect(backend.calls, [
        'preload:assets/sounds/gameplay_bgm.mp3',
        'preload:assets/sounds/ui_button.wav',
        'pauseAll',
        'resumeAll',
        'dispose',
      ]);
    },
  );

  test('HCAudioService ignores playback after dispose', () async {
    final catalog = HCAudioCatalog(
      bgm: {'gameplay': HCAudioCue.asset('assets/sounds/gameplay_bgm.mp3')},
      sfx: {'ui_button': HCAudioCue.asset('assets/sounds/ui_button.wav')},
    );
    final backend = _FakeAudioBackend();
    final audio = HCAudioService(backend: backend, catalog: catalog);

    await audio.dispose();

    expect(await audio.playBgm('gameplay'), isFalse);
    expect(await audio.playSfx('ui_button'), isFalse);
    await audio.stopBgm();
    await audio.pauseAll();
    await audio.resumeAll();
    await audio.preloadAll();
    await audio.dispose();

    expect(backend.calls, ['dispose']);
  });

  test('HCAudioplayersAudioBackend implements HCAudioBackend contract', () {
    final backend = HCAudioplayersAudioBackend();

    expect(backend, isA<HCAudioBackend>());
  });
}

final class _FakeAudioBackend implements HCAudioBackend {
  final calls = <String>[];
  final bgmVolumes = <double>[];
  final _failedCalls = <String>{};
  Completer<void>? _sfxBlocker;
  Completer<void>? _sfxComplete;
  Completer<void>? _playBgmBlocker;
  Completer<void>? _stopBgmBlocker;
  final _bgmVolumeBlockers = <Completer<void>>[];
  final _bgmVolumeSetAttempts = <Completer<void>>[];
  var _nextBgmVolumeBlocker = 0;
  String? _heldSfxAssetPath;
  String? currentBgmAssetPath;
  bool isDisposed = false;

  void failPreload(String assetPath) => _fail('preload', assetPath);

  void failSfx(String assetPath) => _fail('sfx', assetPath);

  void failLoopingSfx(String assetPath) => _fail('loopingSfx', assetPath);

  void failBgm(String assetPath) => _fail('bgm', assetPath);

  void clearFailures() {
    _failedCalls.clear();
  }

  void _fail(String operation, String assetPath) {
    _failedCalls.add('$operation:$assetPath');
  }

  bool _shouldFail(String operation, HCAudioCue cue) {
    return _failedCalls.contains('$operation:${cue.assetPath}');
  }

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

  void holdPlayBgm() {
    _playBgmBlocker = Completer<void>();
  }

  void releasePlayBgm() {
    _playBgmBlocker?.complete();
    _playBgmBlocker = null;
  }

  void holdStopBgm() {
    _stopBgmBlocker = Completer<void>();
  }

  void releaseStopBgm() {
    _stopBgmBlocker?.complete();
    _stopBgmBlocker = null;
  }

  void holdBgmVolumeSets(int count) {
    _bgmVolumeBlockers.clear();
    _bgmVolumeSetAttempts.clear();
    _nextBgmVolumeBlocker = 0;
    for (var i = 0; i < count; i++) {
      _bgmVolumeBlockers.add(Completer<void>());
      _bgmVolumeSetAttempts.add(Completer<void>());
    }
  }

  void releaseBgmVolumeSet(int index) {
    _bgmVolumeBlockers[index].complete();
  }

  Future<void> waitForBgmVolumeSetAttempt(int count) {
    return _bgmVolumeSetAttempts[count - 1].future;
  }

  @override
  Future<void> preload(HCAudioCue cue) async {
    calls.add('preload:${cue.assetPath}');
    if (_shouldFail('preload', cue)) {
      throw StateError('missing ${cue.assetPath}');
    }
  }

  @override
  Future<void> playBgm(
    HCAudioCue cue, {
    required double volume,
    required bool loop,
  }) async {
    calls.add('playBgm:${cue.assetPath}:$volume:$loop');
    if (_shouldFail('bgm', cue)) {
      throw StateError('missing ${cue.assetPath}');
    }
    await _playBgmBlocker?.future;
    if (!isDisposed) {
      currentBgmAssetPath = cue.assetPath;
    }
  }

  @override
  Future<void> setBgmVolume(double volume) async {
    if (_nextBgmVolumeBlocker < _bgmVolumeBlockers.length) {
      final blockerIndex = _nextBgmVolumeBlocker++;
      _bgmVolumeSetAttempts[blockerIndex].complete();
      await _bgmVolumeBlockers[blockerIndex].future;
    }
    bgmVolumes.add(volume);
    calls.add('setBgmVolume:$volume');
  }

  @override
  Future<void> playSfx(HCAudioCue cue, {required double volume}) async {
    calls.add('playSfx:${cue.assetPath}:$volume');
    if (_shouldFail('sfx', cue)) {
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

  @override
  Future<HCAudioLoopHandle> playLoopingSfx(
    HCAudioCue cue, {
    required double volume,
  }) async {
    calls.add('playLoopingSfx:${cue.assetPath}:$volume');
    if (_shouldFail('loopingSfx', cue)) {
      throw StateError('missing ${cue.assetPath}');
    }
    return _FakeAudioLoopHandle(calls, cue.assetPath);
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
  Future<void> stopBgm() async {
    calls.add('stopBgm');
    await _stopBgmBlocker?.future;
    currentBgmAssetPath = null;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    isDisposed = true;
    currentBgmAssetPath = null;
  }
}

final class _FakeAudioLoopHandle implements HCAudioLoopHandle {
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

Future<void> _waitForSetBgmVolume(_FakeAudioBackend backend) async {
  for (var i = 0; i < 50; i++) {
    if (backend.calls.any((call) => call.startsWith('setBgmVolume:'))) {
      return;
    }
    await Future<void>.delayed(Duration(milliseconds: 1));
  }
}

Future<void> _waitForBgmVolumeCount(
  _FakeAudioBackend backend,
  int count,
) async {
  for (var i = 0; i < 50; i++) {
    if (backend.bgmVolumes.length >= count) {
      return;
    }
    await Future<void>.delayed(Duration(milliseconds: 1));
  }
}
