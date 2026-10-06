import 'package:flutter_scene/scene.dart';

import '../geometry/mesh_arrays.dart';

/// Uploads [arrays] as flutter_scene geometry. Pass
/// [GeometryStorage.updatable] to rewrite its vertices later.
MeshGeometry uploadMesh(
  MeshArrays arrays, {
  GeometryStorage storage = GeometryStorage.fixed,
}) => MeshGeometry.fromArrays(
  positions: arrays.positions,
  normals: arrays.normals,
  colors: arrays.colors,
  texCoords: arrays.texCoords,
  indices: arrays.indices,
  storage: storage,
);

/// Flags every node under [node] as a static shadow caster, so the engine
/// caches its shadow map instead of redrawing it each frame. Only for
/// content that never moves.
void markStaticShadows(Node node) {
  node.shadowStatic = true;
  for (final child in node.children) {
    markStaticShadows(child);
  }
}
