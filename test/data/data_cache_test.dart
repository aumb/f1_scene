import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:f1_scene/src/data/data_cache.dart';
import 'package:f1_scene/src/data/device_store.dart';
import 'package:f1_scene/src/data/device_store_io.dart';
import 'package:f1_scene/src/race/openf1_client.dart';
import 'package:f1_scene/src/race/race_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A device store in memory, standing in for the browser's or the disk.
class FakeStore implements DeviceStore {
  final entries = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, Uint8List bytes) async => entries[key] = bytes;
}

Uint8List bytes(int n, [int fill = 1]) => Uint8List(n)..fillRange(0, n, fill);

void main() {
  group('DataCache', () {
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
  });

  test('files on disk read back only under their own key', () async {
    final dir = await Directory.systemTemp.createTemp('f1_scene_store');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileStore(dir);
    await store.write('https://example/a?x=1', bytes(1000, 7));
    expect(await store.read('https://example/a?x=1'), bytes(1000, 7));
    expect(await store.read('https://example/a?x=2'), isNull);
    expect(dir.listSync().whereType<File>(), hasLength(1));
  });

  group('OpenF1 requests', () {
    late List<Uri> sent;
    MockClient api({DateTime? raceEnd}) => MockClient((request) async {
      sent.add(request.url);
      final rows = switch (request.url.pathSegments.last) {
        'sessions' => [
          {
            'session_key': 9,
            'meeting_key': 1,
            'circuit_key': 3,
            'circuit_short_name': 'Sakhir',
            'location': 'Sakhir',
            'year': 2024,
            'country_name': 'Bahrain',
            'date_start': raceEnd!
                .subtract(const Duration(hours: 2))
                .toIso8601String(),
            'date_end': raceEnd.toIso8601String(),
          },
        ],
        'meetings' => [
          {'meeting_key': 1, 'meeting_name': 'Bahrain Grand Prix'},
        ],
        'location' => [
          for (var i = 0; i < 4; i++)
            {
              'driver_number': 1 + i % 2,
              'date': '2024-03-02T15:20:0$i.250000+00:00',
              'x': 100 + i,
              'y': -50 - i,
            },
        ],
        _ => [
          {'driver_number': 1, 'name_acronym': 'VER'},
        ],
      };
      return http.Response(jsonEncode(rows), 200);
    });

    setUp(() => sent = []);

    test('ask once, however often or at once they are asked for', () async {
      final client = OpenF1Client(httpClient: api(), cache: DataCache());
      await client.get('drivers', {'session_key': 9});
      await client.get('drivers', {'session_key': 9});
      await Future.wait([
        client.get('laps', {'session_key': 9}),
        client.get('laps', {'session_key': 9}),
      ]);
      expect(sent, hasLength(2));
      await client.get('stints', {'session_key': 9}, keep: Keep.nothing);
      await client.get('stints', {'session_key': 9}, keep: Keep.nothing);
      expect(sent, hasLength(4));
    });

    test('a finished race comes back from the device after a reload', () async {
      final store = FakeStore();
      final epoch = DateTime.utc(2024, 3, 2, 15, 20);
      Future<void> visit() async {
        final repository = RaceRepository(
          client: OpenF1Client(
            httpClient: api(raceEnd: DateTime.utc(2024, 3, 2, 17)),
            cache: DataCache(store: store),
          ),
        );
        await repository.races(2024);
        await repository.drivers(9);
        final batch = await repository.locations(
          9,
          epoch: epoch,
          from: epoch,
          to: epoch.add(const Duration(minutes: 5)),
        );
        expect(batch.samples[1]!.t, [0.25, 2.25]);
        expect(batch.samples[2]!.x, [101, 103]);
      }

      await visit();
      final first = [...sent];
      sent.clear();
      await visit();
      expect(first.map((u) => u.pathSegments.last).toSet(), {
        'sessions',
        'meetings',
        'drivers',
        'location',
      });
      // A past season: its calendar is final too, so nothing is asked again.
      expect(sent, isEmpty);
    });

    test('a race that just ended is not kept on the device', () async {
      final store = FakeStore();
      final repository = RaceRepository(
        client: OpenF1Client(
          httpClient: api(raceEnd: DateTime.now().toUtc()),
          cache: DataCache(store: store),
        ),
      );
      await repository.races(DateTime.now().year);
      await repository.drivers(9);
      expect(store.entries, isEmpty);
    });
  });

  test('position batches survive the binary form', () {
    final epoch = DateTime.utc(2024, 3, 2, 15);
    final batch = LocationBatch(epoch)
      ..add(1, 10.125, 1498, -412)
      ..add(44, 10.375, -2003.5, 77)
      ..add(1, 10.5, 1500, -411);
    // Read back against an epoch a minute later.
    final later = epoch.add(const Duration(minutes: 1));
    final back = LocationBatch.fromBytes(batch.toBytes(), later)!;
    expect(back.samples[1]!.t, [closeTo(-49.875, 1e-9), closeTo(-49.5, 1e-9)]);
    expect(back.samples[1]!.x, [1498, 1500]);
    expect(back.samples[44]!.x, [-2003.5]);
    expect(back.samples[44]!.y, [77]);
    expect(LocationBatch.fromBytes(Uint8List(24), epoch), isNull);
  });
}
