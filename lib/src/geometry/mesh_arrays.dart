import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// Raw triangle-list mesh arrays, independent of any renderer.
///
/// Every mesh here winds its triangles so that (b − a) × (c − a) points out
/// of the side meant to be seen.
class MeshArrays {
  MeshArrays({
    required this.positions,
    required this.normals,
    required this.indices,
    this.colors,
    this.texCoords,
  });

  final Float32List positions;
  final Float32List normals;
  final Float32List? colors;
  final Float32List? texCoords;
  final Uint32List indices;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
}

/// Linear-space RGBA from an sRGB `0xRRGGBB` value.
Vector4 linearColor(int rgb, [double alpha = 1]) {
  double channel(int shift) {
    final c = ((rgb >> shift) & 0xff) / 255;
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return Vector4(channel(16), channel(8), channel(0), alpha);
}

/// Collects vertices and triangles into [MeshArrays].
///
/// Triangles added "facing" a direction are wound to face it, so callers
/// list corners in whichever order is natural and never think about
/// winding. Either every vertex gets a colour (or texture coordinate) or
/// none does.
class MeshBuilder {
  final _positions = <double>[];
  final _normals = <double>[];
  final _colors = <double>[];
  final _texCoords = <double>[];
  final _indices = <int>[];

  int get vertexCount => _positions.length ~/ 3;

  /// Adds a vertex and returns its index.
  int vertex(Vector3 position, Vector3 normal, {Vector4? color, Vector2? uv}) {
    _positions.addAll([position.x, position.y, position.z]);
    _normals.addAll([normal.x, normal.y, normal.z]);
    if (color != null) _colors.addAll([color.x, color.y, color.z, color.w]);
    if (uv != null) _texCoords.addAll([uv.x, uv.y]);
    return vertexCount - 1;
  }

  /// Adds triangle [a], [b], [c], wound to face [normal].
  void triangleFacing(int a, int b, int c, Vector3 normal) {
    final pa = _at(a);
    final face = (_at(b) - pa).cross(_at(c) - pa);
    _indices.addAll(face.dot(normal) >= 0 ? [a, b, c] : [a, c, b]);
  }

  /// Adds quad [a]-[b]-[c]-[d] (corners in order around it), wound to face
  /// [normal].
  void quadFacing(int a, int b, int c, int d, Vector3 normal) {
    triangleFacing(a, b, c, normal);
    triangleFacing(a, c, d, normal);
  }

  /// Adds a flat quad with four vertices of its own, so its colour and
  /// shading stay crisp: corners [a]-[b]-[c]-[d] in order around it, all
  /// with [normal], which it faces.
  void flatQuad(
    Vector3 a,
    Vector3 b,
    Vector3 c,
    Vector3 d,
    Vector3 normal, {
    Vector4? color,
  }) {
    final v = vertexCount;
    for (final p in [a, b, c, d]) {
      vertex(p, normal, color: color);
    }
    quadFacing(v, v + 1, v + 2, v + 3, normal);
  }

  Vector3 _at(int i) =>
      Vector3(_positions[i * 3], _positions[i * 3 + 1], _positions[i * 3 + 2]);

  MeshArrays build() {
    final n = vertexCount;
    assert(_colors.isEmpty || _colors.length == n * 4, 'Colour every vertex');
    assert(
      _texCoords.isEmpty || _texCoords.length == n * 2,
      'Map every vertex',
    );
    return MeshArrays(
      positions: Float32List.fromList(_positions),
      normals: Float32List.fromList(_normals),
      colors: _colors.isEmpty ? null : Float32List.fromList(_colors),
      texCoords: _texCoords.isEmpty ? null : Float32List.fromList(_texCoords),
      indices: Uint32List.fromList(_indices),
    );
  }
}
