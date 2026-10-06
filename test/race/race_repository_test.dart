import 'package:f1_scene/src/data/data_cache.dart';
import 'package:f1_scene/src/race/openf1_client.dart';
import 'package:f1_scene/src/race/race_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  /// A repository as one visit to the site makes it, over [store].
  RaceRepository visit(FakeOpenF1 api, FakeStore store) => RaceRepository(
    client: OpenF1Client(
      httpClient: api.client,
      cache: DataCache(store: store),
      rateLimits: const [],
    ),
  );

  test('a finished race comes back from the device after a reload', () async {
    final api = FakeOpenF1(raceEnd: DateTime.utc(2024, 3, 2, 17));
    final store = FakeStore();
    final epoch = DateTime.utc(2024, 3, 2, 15, 20);
    Future<void> watch() async {
      final repository = visit(api, store);
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

    await watch();
    expect(api.sent.map((u) => u.pathSegments.last).toSet(), {
      'sessions',
      'meetings',
      'drivers',
      'location',
    });
    api.sent.clear();
    await watch();
    // A past season: its calendar is final too, so nothing is asked again.
    expect(api.sent, isEmpty);
  });

  test('a race that just ended is not kept on the device', () async {
    final api = FakeOpenF1(raceEnd: DateTime.now().toUtc());
    final store = FakeStore();
    final repository = visit(api, store);
    await repository.races(DateTime.now().year);
    await repository.drivers(9);
    expect(store.entries, isEmpty);
  });
}
