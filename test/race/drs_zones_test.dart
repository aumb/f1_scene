import 'package:f1_scene/src/geometry/track_alignment.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:f1_scene/src/geometry/track_projector.dart';
import 'package:f1_scene/src/race/drs_zones.dart';
import 'package:f1_scene/src/race/location_batch.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/circuits.dart';

const identity = SimilarityTransform2D(scale: 1, rotation: 0, tx: 0, ty: 0);

void main() {
  final stations = TrackStations.sample(loadCircuit('bh-2002'));
  final track = TrackProjector(stations);
  final n = stations.length;

  /// One car lapping at 2 stations per 0.25 s, DRS open inside [zones].
  ({LocationBatch locations, Map<int, List<double>> open}) lap(
    List<(int, int)> zones,
  ) {
    final batch = LocationBatch(DateTime.utc(2024));
    final open = <double>[];
    for (var k = 0; k < n ~/ 2; k++) {
      final t = k * 0.25;
      final station = (k * 2) % n;
      final p = track.place(station.toDouble(), 0).position;
      batch.add(1, t, p.x, p.z);
      final inZone = zones.any(
        (z) => z.$1 <= z.$2
            ? station >= z.$1 && station <= z.$2
            : station >= z.$1 || station <= z.$2,
      );
      if (inZone) open.add(t);
    }
    return (locations: batch, open: {1: open});
  }

  test('finds each zone where DRS was open', () {
    final data = lap([(100, 400), (1500, 1700)]);
    final zones = drsZonesFrom(
      openTimes: data.open,
      locations: data.locations,
      transform: identity,
      track: track,
    );
    expect(zones, hasLength(2));
    expect(zones[0].start, closeTo(100, 3));
    expect(zones[0].end, closeTo(400, 3));
    expect(zones[1].start, closeTo(1500, 3));
  });

  test('joins a zone across the start/finish seam', () {
    final data = lap([(n - 200, 150)]);
    final zones = drsZonesFrom(
      openTimes: data.open,
      locations: data.locations,
      transform: identity,
      track: track,
    );
    expect(zones, hasLength(1));
    expect(zones.single.start, greaterThan(zones.single.end));
  });

  test('is empty without DRS use', () {
    final data = lap([]);
    expect(
      drsZonesFrom(
        openTimes: data.open,
        locations: data.locations,
        transform: identity,
        track: track,
      ),
      isEmpty,
    );
  });
}
