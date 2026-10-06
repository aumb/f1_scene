import 'dart:typed_data';

import 'device_store_none.dart'
    if (dart.library.js_interop) 'device_store_web.dart'
    if (dart.library.io) 'device_store_io.dart'
    as platform;

/// Bytes kept on this device between runs: the browser's Cache Storage on
/// the web, files in the temporary directory elsewhere.
///
/// Storage can be full, blocked (some private windows) or cleared at any
/// time, so a failed write is ignored and a failed read is a miss.
abstract interface class DeviceStore {
  Future<Uint8List?> read(String key);

  Future<void> write(String key, Uint8List bytes);
}

/// The store named [name] on this platform, or null where there is none.
DeviceStore? openDeviceStore(String name) => platform.open(name);
