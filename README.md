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
