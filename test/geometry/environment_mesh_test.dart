import 'dart:typed_data';

import 'package:f1_scene/src/data/circuit_environment.dart';
import 'package:f1_scene/src/geometry/environment_mesh.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:f1_scene/src/geometry/track_projector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import '../support/circuits.dart';

double area(List<Vector2> ring, List<(int, int, int)> triangles) {
  var sum = 0.0;
  for (final (a, b, c) in triangles) {
    final p = ring[a], q = ring[b], r = ring[c];
    sum += ((q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)) / 2;
  }
  return sum;
}

void main() {
  group('triangulate', () {
    test('a square', () {
      final ring = [
        Vector2(0, 0),
        Vector2(10, 0),
        Vector2(10, 10),
        Vector2(0, 10),
      ];
      final t = triangulate(ring);
      expect(t, hasLength(2));
      expect(area(ring, t), closeTo(100, 1e-9));
    });

    test('a concave L', () {
      final ring = [
        Vector2(0, 0),
        Vector2(20, 0),
        Vector2(20, 10),
        Vector2(10, 10),
        Vector2(10, 20),
        Vector2(0, 20),
      ];
      final t = triangulate(ring);
      expect(t, hasLength(4));
      expect(area(ring, t), closeTo(300, 1e-9));
    });
  });

  group('environment around Bahrain', () {
    final stations = TrackStations.sample(loadCircuit('bh-2002'));
    final track = TrackProjector(stations);
    final lo =
        stations.center.map((c) => c.x).reduce((a, b) => a < b ? a : b) - 1000;
    final hi =
        stations.center.map((c) => c.x).reduce((a, b) => a > b ? a : b) + 1000;
    final south =
        stations.center.map((c) => c.z).reduce((a, b) => a > b ? a : b) + 1000;
    final north =
        stations.center.map((c) => c.z).reduce((a, b) => a < b ? a : b) - 1000;

    /// A 30 m plateau over the whole circuit, so it would bury the track.
    CircuitEnvironment plateau({List<EnvironmentShape> buildings = const []}) =>
        CircuitEnvironment(
          terrain: TerrainGrid(
            // The real grids are 64 x 64 over a similar area.
            size: 64,
            minX: lo,
            maxX: hi,
            southZ: south,
            northZ: north,
            heights: Float64List(64 * 64)..fillRange(0, 64 * 64, 30),
          ),
          water: const [],
          landuse: const [],
          roads: const [],
          buildings: buildings,
        );

    test('presses the ground below the track and keeps it far away', () {
      final builder = EnvironmentMeshBuilder(plateau(), track);
      // Under the centerline and both edges, all the way round.
      for (var i = 0; i < stations.length; i += 5) {
        for (final p in [
          stations.center[i],
          stations.leftEdge(i),
          stations.rightEdge(i),
        ]) {
          expect(builder.groundAt(p.x, p.z), lessThan(p.y - 0.3), reason: '$i');
        }
      }
      expect(builder.groundAt(lo + 50, south - 50), closeTo(30, 1e-6));
    });

    test('builds the ground up to the track over a valley', () {
      final valley = CircuitEnvironment(
        terrain: TerrainGrid(
          size: 64,
          minX: lo,
          maxX: hi,
          southZ: south,
          northZ: north,
          heights: Float64List(64 * 64)..fillRange(0, 64 * 64, -40),
        ),
        water: const [],
        landuse: const [],
        roads: const [],
        buildings: const [],
      );
      final builder = EnvironmentMeshBuilder(valley, track);
      for (var i = 0; i < stations.length; i += 25) {
        final c = stations.center[i];
        expect(builder.groundAt(c.x, c.z), closeTo(c.y - 1.5, 1.0));
      }
      expect(builder.groundAt(lo + 50, south - 50), closeTo(-40, 1e-6));
    });

    test('skips buildings on the circuit', () {
      Vector2 at(int station, double lateral) {
        final p = track.place(station.toDouble(), lateral).position;
        return Vector2(p.x, p.z);
      }

      List<Vector2> square(Vector2 c) => [
        c + Vector2(-5, -5),
        c + Vector2(5, -5),
        c + Vector2(5, 5),
        c + Vector2(-5, 5),
      ];
      final onTrack = EnvironmentShape(
        'building',
        square(at(500, 0)),
        height: 10,
      );
      final beside = EnvironmentShape(
        'building',
        square(at(500, 60)),
        height: 10,
      );
      final mesh = EnvironmentMeshBuilder(
        plateau(buildings: [onTrack, beside]),
        track,
      ).buildings();
      // One box: 4 walls and a 2-triangle roof.
      expect(mesh.triangleCount, 4 * 2 + 2);
    });

    test('terrain surface faces up', () {
      final mesh = EnvironmentMeshBuilder(plateau(), track).terrainBlock(-50);
      final surfaceTriangles = 126 * 126 * 2; // (64 * 2 - 1) - 1 squared, x2
      for (var t = 0; t < surfaceTriangles; t++) {
        Vector3 v(int k) {
          final i = mesh.indices[t * 3 + k];
          return Vector3(
            mesh.positions[i * 3],
            mesh.positions[i * 3 + 1],
            mesh.positions[i * 3 + 2],
          );
        }

        expect((v(1) - v(0)).cross(v(2) - v(0)).y, greaterThan(0));
      }
    });
  });
}
