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
