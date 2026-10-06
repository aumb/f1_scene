import 'dart:math' as math;
import 'dart:typed_data';

import 'package:f1_scene/src/data/circuit_environment.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';

/// Flat ground [height] meters up, reaching [margin] meters past [stations]
/// on every side, with [buildings] and nothing else on it. A 64 x 64 grid,
/// like the real ones.
CircuitEnvironment flatEnvironment(
  TrackStations stations, {
  required double height,
  double margin = 1000,
  List<EnvironmentShape> buildings = const [],
}) {
  final xs = stations.center.map((c) => c.x);
  final zs = stations.center.map((c) => c.z);
  return CircuitEnvironment(
    terrain: TerrainGrid(
      size: 64,
      minX: xs.reduce(math.min) - margin,
      maxX: xs.reduce(math.max) + margin,
      southZ: zs.reduce(math.min) - margin,
      northZ: zs.reduce(math.max) + margin,
      heights: Float64List(64 * 64)..fillRange(0, 64 * 64, height),
    ),
    water: const [],
    landuse: const [],
    roads: const [],
    buildings: buildings,
  );
}
