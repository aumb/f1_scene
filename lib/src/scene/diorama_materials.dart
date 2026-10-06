import 'package:flutter_scene/scene.dart';

import '../geometry/mesh_arrays.dart';

/// The materials the diorama is drawn with.
///
/// Colours come from each mesh's vertices, so most of these only set the
/// finish. Surfaces lying flush on another win the depth tie by
/// [Material.depthLayer]: the pit lane gives way to the track where they
/// merge (-1); roads and water draw over the ground and kerbs over the
/// track (1), DRS bands over kerbs (2), and lines over everything (3).
class DioramaMaterials {
  final surface = _matte(0.5);
  final skirt = _matte(0.8)..baseColorFactor = linearColor(0x2C3038);
  final slab = _matte(0.95)..baseColorFactor = linearColor(0x1A1D23);
  final terrain = _matte(0.95);
  final building = _matte(0.8);
  final road = _matte(0.85, depthLayer: 1);
  final water = _matte(0.15, depthLayer: 1);
  final tree = _matte(0.9)..baseColorFactor = linearColor(0x35593C);
  final pit = _matte(0.7, depthLayer: -1);
  final kerb = _matte(0.6, depthLayer: 1);
  final drs = _matte(0.6, depthLayer: 2);
  final line = _matte(0.6, depthLayer: 3);

  static PhysicallyBasedMaterial _matte(
    double roughness, {
    int depthLayer = 0,
  }) => PhysicallyBasedMaterial()
    ..metallicFactor = 0
    ..roughnessFactor = roughness
    ..depthLayer = depthLayer;
}
