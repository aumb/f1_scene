import 'dart:typed_data';

import 'package:f1_scene/src/data/data_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Uint8List bytes(int n) => Uint8List(n)..fillRange(0, n, 1);

void main() {
  test('keeps only device entries on the device', () async {
    final store = FakeStore();
    final cache = DataCache(store: store)
      ..write('a', bytes(4), Keep.session)
      ..write('b', bytes(4), Keep.device)
      ..write('c', bytes(4), Keep.nothing);
    await Future<void>.delayed(Duration.zero);
    expect(store.entries.keys, ['b']);
    expect(await cache.read('a'), isNotNull);
    expect(await cache.read('c'), isNull);

    // A fresh start (a reload): only the device entry is still there.
    final reloaded = DataCache(store: store);
    expect(await reloaded.read('a'), isNull);
    expect(await reloaded.read('b'), bytes(4));
  });

  test('drops the least recently used from memory', () async {
    final cache = DataCache(memoryBytes: 40);
    await cache.write('a', bytes(10), Keep.session);
    await cache.write('b', bytes(10), Keep.session);
    await cache.write('c', bytes(10), Keep.session);
    await cache.read('a'); // now the most recent
    await cache.write('d', bytes(10), Keep.session);
    await cache.write('e', bytes(10), Keep.session);
    expect(await cache.read('b'), isNull);
    expect(await cache.read('a'), isNotNull);
    expect(await cache.read('e'), isNotNull);
  });
}
