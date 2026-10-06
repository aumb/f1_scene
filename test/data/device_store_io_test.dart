import 'dart:io';
import 'dart:typed_data';

import 'package:f1_scene/src/data/device_store_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('files on disk read back only under their own key', () async {
    final dir = await Directory.systemTemp.createTemp('f1_scene_store');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileStore(dir);
    final bytes = Uint8List(1000)..fillRange(0, 1000, 7);
    await store.write('https://example/a?x=1', bytes);
    expect(await store.read('https://example/a?x=1'), bytes);
    expect(await store.read('https://example/a?x=2'), isNull);
    expect(dir.listSync().whereType<File>(), hasLength(1));
  });
}
