import 'package:f1_scene/src/data/circuit_environment.dart';
import 'package:f1_scene/src/geometry/environment_mesh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import '../support/circuits.dart';
import '../support/environment.dart';
import '../support/mesh.dart';

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
    final (:stations, :track) = bahrain();

    /// A 30 m plateau over the whole circuit, so it would bury the track.
    CircuitEnvironment plateau({List<EnvironmentShape> buildings = const []}) =>
        flatEnvironment(stations, height: 30, buildings: buildings);

    // A point well inside the grid's south-west corner, far from the track.
    final grid = plateau().terrain;
    final cornerX = grid.minX + 50, cornerZ = grid.southZ + 50;

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
      expect(builder.groundAt(cornerX, cornerZ), closeTo(30, 1e-6));
    });

    test('builds the ground up to the track over a valley', () {
      final valley = flatEnvironment(stations, height: -40);
      final builder = EnvironmentMeshBuilder(valley, track);
      for (var i = 0; i < stations.length; i += 25) {
        final c = stations.center[i];
        expect(builder.groundAt(c.x, c.z), closeTo(c.y - 1.5, 1.0));
      }
      expect(builder.groundAt(cornerX, cornerZ), closeTo(-40, 1e-6));
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

    test('sight lines stop at buildings and hills', () {
      // A 20 m tall block 60 m left of the track at station 500.
      final c = track.place(500, 60).position;
      final block = EnvironmentShape('building', [
        Vector2(c.x - 6, c.z - 6),
        Vector2(c.x + 6, c.z - 6),
        Vector2(c.x + 6, c.z + 6),
        Vector2(c.x - 6, c.z + 6),
      ], height: 20);
      final obstacles = EnvironmentMeshBuilder(
        plateau(buildings: [block]),
        track,
      ).obstacles;
      final ground = obstacles.groundAt(c.x, c.z);

      expect(obstacles.isBuilt(c.x, c.z), isTrue);
      expect(obstacles.isBuilt(c.x + 8, c.z), isFalse);
      expect(obstacles.isBuilt(c.x + 8, c.z, margin: 3), isTrue);

      // Straight through the block at half its height, then over its roof.
      final west = Vector3(c.x - 40, ground + 10, c.z);
      final east = Vector3(c.x + 40, ground + 10, c.z);
      expect(obstacles.canSee(west, east), isFalse);
      expect(
        obstacles.canSee(west..y = ground + 25, east..y = ground + 25),
        isTrue,
      );
      // Into the 30 m plateau from below it.
      expect(
        obstacles.canSee(
          Vector3(cornerX, 10, cornerZ),
          Vector3(cornerX + 200, 10, cornerZ),
        ),
        isFalse,
      );
    });

    test('terrain surface faces up', () {
      final mesh = EnvironmentMeshBuilder(plateau(), track).terrainBlock(-50);
      // The surface comes first: the grid upsampled to 127 x 127 nodes,
      // two triangles a cell. The skirts follow.
      const surfaceTriangles = 126 * 126 * 2;
      for (final normal in faceNormals(mesh).take(surfaceTriangles)) {
        expect(normal.y, greaterThan(0));
      }
    });
  });
}
