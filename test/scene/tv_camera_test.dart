import 'dart:math' as math;

import 'package:f1_scene/src/data/circuit_environment.dart';
import 'package:f1_scene/src/geometry/environment_mesh.dart';
import 'package:f1_scene/src/race/car_motion.dart';
import 'package:f1_scene/src/scene/race_cameras.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import '../support/circuits.dart';
import '../support/environment.dart';

void main() {
  final (:stations, :track) = bahrain();

  /// Bahrain in a city: 12 m blocks, 20 m tall, every 45 m from 25 m to
  /// 150 m off the track, on flat ground below the circuit.
  SceneryObstacles city() {
    final low = stations.center.map((c) => c.y).reduce(math.min) - 3;
    final grid = flatEnvironment(stations, height: low, margin: 300).terrain;
    final buildings = <EnvironmentShape>[];
    for (var x = grid.minX; x < grid.maxX; x += 45) {
      for (var z = grid.southZ; z < grid.northZ; z += 45) {
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
      flatEnvironment(stations, height: low, margin: 300, buildings: buildings),
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
      // What the post claims to see, it sees: each bucket of stations is
      // judged from its middle station.
      const bucket = TvCameraController.bucketStations;
      Vector3 target(int station) =>
          stations.center[station % stations.length] + Vector3(0, 1.2, 0);
      final anchor = post.station;
      var seen = 0, total = 0;
      for (var j = anchor - (180 / mps).round(); j < anchor; j += 8) {
        final station = j % stations.length;
        final middle = station ~/ bucket * bucket + bucket ~/ 2;
        expect(
          post.sees(station.toDouble()),
          obstacles.canSee(p, target(middle)),
        );
        total++;
        if (obstacles.canSee(p, target(station))) seen++;
      }
      expect(seen / total, greaterThan(0.4), reason: 'post at $anchor');
    }
  });

  test('cuts to a post that can see the car', () {
    // A car on the main straight, two posts ahead of it: the nearer one
    // with its view blocked.
    const at = 100;
    final forward = stations.forward[at];
    final pose = CarPose(
      track.place(at.toDouble(), 0).position,
      math.atan2(forward.x, forward.z),
    );
    Vector3 beside(double along) =>
        track.place(along, -40).position + Vector3(0, 9, 0);
    final blocked = TvPost(beside(130), 130, const {});
    final clear = TvPost(beside(180), 180, {
      for (
        var b = 0;
        b <= stations.length ~/ TvCameraController.bucketStations;
        b++
      )
        b,
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
    expect(blocked.sees(at.toDouble()), isFalse);
  });
}
