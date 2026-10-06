import 'dart:math' as math;
import 'dart:typed_data';

import 'package:f1_scene/src/data/circuit_environment.dart';
import 'package:f1_scene/src/geometry/environment_mesh.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:f1_scene/src/geometry/track_projector.dart';
import 'package:f1_scene/src/race/car_motion.dart';
import 'package:f1_scene/src/scene/race_cameras.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import '../support/circuits.dart';

void main() {
  final stations = TrackStations.sample(loadCircuit('bh-2002'));
  final track = TrackProjector(stations);

  /// Bahrain in a city: 12 m blocks, 20 m tall, every 45 m from 25 m to
  /// 150 m off the track, on flat ground below the circuit.
  SceneryObstacles city() {
    final xs = stations.center.map((c) => c.x),
        zs = stations.center.map((c) => c.z);
    final minX = xs.reduce(math.min) - 300, maxX = xs.reduce(math.max) + 300;
    final minZ = zs.reduce(math.min) - 300, maxZ = zs.reduce(math.max) + 300;
    final low = stations.center.map((c) => c.y).reduce(math.min) - 3;
    final buildings = <EnvironmentShape>[];
    for (var x = minX; x < maxX; x += 45) {
      for (var z = minZ; z < maxZ; z += 45) {
        final off = track.project(x, z).distance;
        if (off < 25 || off > 150) continue;
        buildings.add(
          EnvironmentShape('building', [
            Vector2(x - 6, z - 6),
            Vector2(x + 6, z - 6),
            Vector2(x + 6, z + 6),
            Vector2(x - 6, z + 6),
          ], height: 20),
        );
      }
    }
    return EnvironmentMeshBuilder(
      CircuitEnvironment(
        terrain: TerrainGrid(
          size: 64,
          minX: minX,
          maxX: maxX,
          // North is -Z in the scene.
          southZ: maxZ,
          northZ: minZ,
          heights: Float64List(64 * 64)..fillRange(0, 64 * 64, low),
        ),
        water: const [],
        landuse: const [],
        roads: const [],
        buildings: buildings,
      ),
      track,
    ).obstacles;
  }

  test('posts stand clear of buildings and see the approach they film', () {
    final obstacles = city();
    final posts = TvCameraController.placePosts(
      stations,
      track,
      obstacles: obstacles,
    );
    expect(posts.length, greaterThan(10));
    final mps = track.metersPerStation;
    for (final post in posts) {
      final p = post.position;
      expect(obstacles.isBuilt(p.x, p.z), isFalse);
      // What the post claims to see, it sees.
      final anchor = post.station;
      var seen = 0, total = 0;
      for (var j = anchor - (180 / mps).round(); j < anchor; j += 8) {
        final along = (j % stations.length).toDouble();
        final target = stations.center[along.toInt()] + Vector3(0, 1.2, 0);
        expect(
          post.sees(along),
          obstacles.canSee(
            p,
            stations.center[(along.toInt() ~/ 4 * 4 + 2) % stations.length] +
                Vector3(0, 1.2, 0),
          ),
        );
        total++;
        if (obstacles.canSee(p, target)) seen++;
      }
      expect(seen / total, greaterThan(0.4), reason: 'post at $anchor');
    }
  });

  test('cuts to a post that can see the car', () {
    // A car on the main straight, two posts ahead of it: the nearer one
    // with its view blocked.
    final at = 100.0;
    final pose = CarPose(
      track.place(at, 0).position,
      math.atan2(stations.forward[100].x, stations.forward[100].z),
    );
    Vector3 beside(double along) =>
        track.place(along, -40).position + Vector3(0, 9, 0);
    final blocked = TvPost(beside(130), 130, const {});
    final clear = TvPost(beside(180), 180, {
      for (var b = 0; b < stations.length ~/ 4 + 1; b++) b,
    });
    final projection = PerspectiveProjection(
      fovRadiansY: 0.6,
      near: 1,
      far: 10000,
    );
    final tv = TvCameraController(
      posts: [blocked, clear],
      track: track,
      projection: projection,
    )..target = (() => pose);
    final node = Node()..addComponent(tv);
    tv.update(1 / 60);
    final eye = node.localTransform.getTranslation();
    expect(eye.distanceTo(clear.position), lessThan(1e-3));
    expect(blocked.sees(at), isFalse);
  });
}
