import 'dart:typed_data';

import 'device_store.dart';

/// How long a response may be kept.
enum Keep {
  /// Not at all.
  nothing,

  /// While the app runs.
  session,

  /// On this device across visits: data that can no longer change, like a
  /// race finished days ago or files at a pinned commit.
  device,
}

/// Responses kept in memory, and on the device when they can't change, so
/// revisiting a race, switching back to one or reloading the page costs no
/// requests. That spares the visitor OpenF1's per-IP rate limit (30
/// requests a minute), and spares OpenF1 the load.
class DataCache {
  DataCache({this.store, this.memoryBytes = 64 << 20});

  /// The app's cache. Bump the name when a stored format changes.
  static final instance = DataCache(store: openDeviceStore('f1_scene_v1'));

  /// Where entries outlive the app, if anywhere on this platform.
  final DeviceStore? store;

  /// Bytes held in memory before the least recently used go.
  final int memoryBytes;

  /// Least recently used first (map literals keep insertion order).
  final _memory = <String, Uint8List>{};
  int _bytes = 0;

  /// The bytes stored under [key], or null.
  Future<Uint8List?> read(String key) async {
    final hot = _memory.remove(key);
    if (hot != null) {
      _memory[key] = hot;
      return hot;
    }
    final stored = await store?.read(key);
    if (stored != null) _remember(key, stored);
    return stored;
  }

  /// Stores [bytes] under [key] for as long as [keep] allows.
  Future<void> write(String key, Uint8List bytes, Keep keep) async {
    if (keep == Keep.nothing) return;
    _remember(key, bytes);
    if (keep == Keep.device) await store?.write(key, bytes);
  }

  void _remember(String key, Uint8List bytes) {
    final old = _memory.remove(key);
    if (old != null) _bytes -= old.length;
    // One entry may not crowd out everything else.
    if (bytes.length > memoryBytes ~/ 4) return;
    _memory[key] = bytes;
    _bytes += bytes.length;
    while (_bytes > memoryBytes) {
      _bytes -= _memory.remove(_memory.keys.first)!.length;
    }
  }
}
