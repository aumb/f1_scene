import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'device_store.dart';

DeviceStore? open(String name) {
  try {
    // Cache Storage exists only in secure contexts (https, localhost).
    if (!web.window.isSecureContext) return null;
    return _CacheStorageStore(
      web.window.caches
          .open(name)
          .toDart
          .then<web.Cache?>((cache) => cache)
          .catchError((Object _) => null),
    );
  } catch (_) {
    return null;
  }
}

/// Entries in the browser's Cache Storage, which holds far more than
/// localStorage and survives reloads and later visits.
class _CacheStorageStore implements DeviceStore {
  _CacheStorageStore(this._cache);

  final Future<web.Cache?> _cache;

  /// Cache Storage is keyed by URL; any key becomes one on a made-up host.
  static String _url(String key) =>
      'https://cache.f1-scene.invalid/${Uri.encodeComponent(key)}';

  @override
  Future<Uint8List?> read(String key) async {
    try {
      final cache = await _cache;
      if (cache == null) return null;
      final hit = await cache.match(_url(key).toJS).toDart;
      if (hit == null) return null;
      return (await hit.arrayBuffer().toDart).toDart.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    try {
      final cache = await _cache;
      await cache?.put(_url(key).toJS, web.Response(bytes.toJS)).toDart;
    } catch (_) {
      // Over quota or blocked: carry on without it.
    }
  }
}
