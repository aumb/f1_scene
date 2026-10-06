import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'device_store.dart';

DeviceStore? open(String name) {
  try {
    return FileStore(Directory('${Directory.systemTemp.path}/$name'));
  } catch (_) {
    return null;
  }
}

/// One file per entry in [directory], named by a hash of its key. The key
/// is stored at the start of the file too, so a hash collision reads as a
/// miss rather than someone else's data.
class FileStore implements DeviceStore {
  FileStore(this.directory);

  final Directory directory;

  File _file(String key) => File('${directory.path}/${_hash(key)}.bin');

  @override
  Future<Uint8List?> read(String key) async {
    try {
      final file = _file(key);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final header = ByteData.sublistView(bytes, 0, 4).getUint32(0);
      final stored = utf8.decode(Uint8List.sublistView(bytes, 4, 4 + header));
      if (stored != key) return null;
      return Uint8List.sublistView(bytes, 4 + header);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    try {
      await directory.create(recursive: true);
      final name = utf8.encode(key);
      final out = BytesBuilder(copy: false)
        ..add((ByteData(4)..setUint32(0, name.length)).buffer.asUint8List())
        ..add(name)
        ..add(bytes);
      // Write aside and rename, so a reader never sees half a file.
      final file = _file(key);
      final part = File('${file.path}.part');
      await part.writeAsBytes(out.takeBytes(), flush: true);
      await part.rename(file.path);
    } catch (_) {
      // Disk full or not writable: carry on without it.
    }
  }

  /// 64-bit FNV-1a, in hex.
  static String _hash(String key) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(key)) {
      h ^= b;
      h *= 0x100000001b3;
    }
    return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }
}
