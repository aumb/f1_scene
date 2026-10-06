import 'package:f1_scene/src/geometry/mesh_arrays.dart';
import 'package:vector_math/vector_math.dart';

/// Vertex [i]'s position.
Vector3 vertexOf(MeshArrays mesh, int i) => Vector3(
  mesh.positions[i * 3],
  mesh.positions[i * 3 + 1],
  mesh.positions[i * 3 + 2],
);

/// Each triangle's corners, in winding order.
Iterable<(Vector3, Vector3, Vector3)> trianglesOf(MeshArrays mesh) sync* {
  for (var t = 0; t < mesh.triangleCount; t++) {
    yield (
      vertexOf(mesh, mesh.indices[t * 3]),
      vertexOf(mesh, mesh.indices[t * 3 + 1]),
      vertexOf(mesh, mesh.indices[t * 3 + 2]),
    );
  }
}

/// Each triangle's face normal, from its winding: (b − a) × (c − a).
Iterable<Vector3> faceNormals(MeshArrays mesh) =>
    trianglesOf(mesh).map((t) => (t.$2 - t.$1).cross(t.$3 - t.$1));
