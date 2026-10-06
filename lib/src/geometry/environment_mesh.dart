import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../data/circuit_environment.dart';
import 'track_mesh.dart';
import 'track_projector.dart';

/// Builds the meshes around a circuit from its [CircuitEnvironment].
///
/// The terrain is upsampled and pressed down wherever it would rise through
/// the track, and everything else (buildings, roads, water, trees) sits on
/// that adjusted ground. Shapes that would cross the circuit are skipped.
class EnvironmentMeshBuilder {
  EnvironmentMeshBuilder(this.environment, this.track) {
    _buildGround();
  }

  final CircuitEnvironment environment;
  final TrackProjector track;

  /// Terrain nodes per side after upsampling.
  late final int _size;
  late final double _minX, _maxX, _southZ, _northZ;
  late final Float64List _ground;
  late final List<Vector4> _colors;

  static final _terrain = linearColor(0x22262D);
  static final _grass = linearColor(0x26332A);
  static final _wood = linearColor(0x1E2C21);
  static final _built = linearColor(0x2A2D33);
  static final _waterBed = linearColor(0x14303E);
  static final _sea = linearColor(0x173A4C);
  static final _skirt = linearColor(0x15181D);

  /// Ground height at scene ([x], [z]) after adjusting for the track.
  double groundAt(double x, double z) {
    final fx = ((x - _minX) / (_maxX - _minX)).clamp(0.0, 1.0) * (_size - 1);
    final fy =
        ((z - _southZ) / (_northZ - _southZ)).clamp(0.0, 1.0) * (_size - 1);
    final c = math.min(_size - 2, fx.floor()),
        r = math.min(_size - 2, fy.floor());
    final tx = fx - c, ty = fy - r;
    double node(int r, int c) => _ground[r * _size + c];
    final a = node(r, c) + (node(r, c + 1) - node(r, c)) * tx;
    final b = node(r + 1, c) + (node(r + 1, c + 1) - node(r + 1, c)) * tx;
    return a + (b - a) * ty;
  }

  /// What blocks a camera's view or stands where it would: this terrain
  /// and these buildings, as built.
  late final SceneryObstacles obstacles = SceneryObstacles._(groundAt, _solids);

  /// The buildings that get built: all but those standing on or right next
  /// to the track (OpenStreetMap footprints are a few meters off at times).
  late final List<_Solid> _solids = [
    for (final b in environment.buildings)
      if (_ccw(_open(b.points)) case final ring when ring.length >= 3)
        if (_centroidClear(ring))
          () {
            final ground = ring.map((p) => groundAt(p.x, p.y)).reduce(math.min);
            return _Solid(
              ring,
              _Box.of(ring),
              ground,
              ground + (b.height > 0 ? b.height : 8),
            );
          }(),
  ];

  bool _centroidClear(List<Vector2> ring) {
    final c =
        ring.fold(Vector2.zero(), (s, p) => s + p) / ring.length.toDouble();
    return _beyondTrack(c.x, c.y, within: 6) >= 6;
  }

  /// Lowest ground height, for sizing the block under it.
  double get lowestGround => _ground.reduce(math.min);

  /// Distance from ([x], [z]) to the nearest track edge, negative on the
  /// track. Only searches as far as [within] past the widest edge; anything
  /// further reports [within].
  double _beyondTrack(double x, double z, {required double within}) {
    final p = track.projectWithin(x, z, within + _widestHalf);
    if (p == null) return within;
    final (lo, hi) = track.lateralLimits(p.along);
    return p.distance - math.max(-lo, hi);
  }

  /// The widest centerline-to-edge distance anywhere on the circuit.
  late final double _widestHalf = [
    ...track.stations.leftOffset,
    ...track.stations.rightOffset,
  ].reduce(math.max);

  void _buildGround() {
    final grid = environment.terrain;
    _size = grid.size * 2 - 1;
    _minX = grid.minX;
    _maxX = grid.maxX;
    _southZ = grid.southZ;
    _northZ = grid.northZ;
    final n = _size;
    double nodeX(int c) => _minX + (_maxX - _minX) * c / (n - 1);
    double nodeZ(int r) => _southZ + (_northZ - _southZ) * r / (n - 1);

    _ground = Float64List(n * n);
    _colors = List.filled(n * n, _terrain);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        _ground[r * n + c] = grid.heightAt(nodeX(c), nodeZ(r));
      }
    }

    // Visit each shape's nodes through its bounding box, rather than test
    // every node against every shape (some circuits have thousands).
    void forNodesInside(List<Vector2> ring, void Function(int node) visit) {
      if (ring.length < 3) return;
      final box = _Box.of(ring);
      int column(double x) => ((x - _minX) / (_maxX - _minX) * (n - 1)).round();
      int row(double z) =>
          ((z - _southZ) / (_northZ - _southZ) * (n - 1)).round();
      final c0 = math.max(0, math.min(column(box.minX), column(box.maxX)));
      final c1 = math.min(n - 1, math.max(column(box.minX), column(box.maxX)));
      final r0 = math.max(0, math.min(row(box.minZ), row(box.maxZ)));
      final r1 = math.min(n - 1, math.max(row(box.minZ), row(box.maxZ)));
      for (var r = r0; r <= r1; r++) {
        for (var c = c0; c <= c1; c++) {
          if (_inside(ring, nodeX(c), nodeZ(r))) visit(r * n + c);
        }
      }
    }

    // The sea, from the coarse flood mask.
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (grid.isSea(nodeX(c), nodeZ(r))) _colors[r * n + c] = _sea;
      }
    }

    // Land use tints the ground; woods win over other uses.
    for (final shape in environment.landuse) {
      final color = switch (shape.kind) {
        'wood' || 'forest' => _wood,
        'grass' || 'park' || 'meadow' => _grass,
        _ => _built,
      };
      forNodesInside(shape.points, (i) {
        if (_colors[i] != _wood) _colors[i] = color;
      });
    }
    // Water bodies sit at the lowest terrain along their shore.
    for (final w in environment.water) {
      if (w.points.isEmpty) continue;
      final level = w.points
          .map((p) => grid.heightAt(p.x, p.y))
          .reduce(math.min);
      forNodesInside(w.points, (i) {
        _ground[i] = math.min(_ground[i], level - 0.5);
        _colors[i] = _waterBed;
      });
    }

    // Shape the ground to the track: cut it down where it would rise
    // through the ribbon, build it up where it falls away below, and ease
    // back to the real terrain away from the edge. The bed stays flat for a
    // whole cell past the edge, because the surface between nodes
    // interpolates and a sloping node any closer could lift it over the
    // track. Beyond 150 m the terrain is left alone.
    final cell = math.sqrt(
      math.pow((_maxX - _minX) / (n - 1), 2) +
          math.pow((_northZ - _southZ) / (n - 1), 2),
    );
    final flat = 12 + cell;
    const slope = 0.35;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final p = track.projectWithin(nodeX(c), nodeZ(r), 150 + _widestHalf);
        if (p == null) continue;
        final (lo, hi) = track.lateralLimits(p.along);
        final beyond = p.distance - math.max(-lo, hi);
        final bed = track.stations.center[p.station].y - 1.5;
        final give = math.max(0.0, beyond - flat) * slope;
        final i = r * n + c;
        _ground[i] = _ground[i].clamp(bed - give, bed + give);
      }
    }
  }

  /// The terrain surface plus skirts down to [baseY], one diorama block.
  MeshArrays terrainBlock(double baseY) {
    final n = _size;
    final positions = <double>[], normals = <double>[], colors = <double>[];
    final indices = <int>[];
    double nodeX(int c) => _minX + (_maxX - _minX) * c / (n - 1);
    double nodeZ(int r) => _southZ + (_northZ - _southZ) * r / (n - 1);

    void vertex(Vector3 p, Vector3 normal, Vector4 color) {
      positions.addAll([p.x, p.y, p.z]);
      normals.addAll([normal.x, normal.y, normal.z]);
      colors.addAll([color.x, color.y, color.z, color.w]);
    }

    // Surface, with normals from the height differences.
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        double h(int rr, int cc) =>
            _ground[rr.clamp(0, n - 1) * n + cc.clamp(0, n - 1)];
        final dx = nodeX(1) - nodeX(0), dz = nodeZ(1) - nodeZ(0);
        final normal = Vector3(
          -(h(r, c + 1) - h(r, c - 1)) / (2 * dx),
          1,
          -(h(r + 1, c) - h(r - 1, c)) / (2 * dz),
        )..normalize();
        vertex(
          Vector3(nodeX(c), _ground[r * n + c], nodeZ(r)),
          normal,
          _colors[r * n + c],
        );
      }
    }
    for (var r = 0; r + 1 < n; r++) {
      for (var c = 0; c + 1 < n; c++) {
        final v00 = r * n + c, v01 = v00 + 1, v10 = v00 + n, v11 = v10 + 1;
        // Rows run north (-Z), columns east (+X): this order faces up.
        indices.addAll([v00, v01, v10, v01, v11, v10]);
      }
    }

    // Skirts around the four edges, facing out.
    void skirt(List<(int, int)> nodes, Vector3 outward) {
      for (var k = 0; k + 1 < nodes.length; k++) {
        final (r0, c0) = nodes[k];
        final (r1, c1) = nodes[k + 1];
        final a = Vector3(nodeX(c0), _ground[r0 * n + c0], nodeZ(r0));
        final b = Vector3(nodeX(c1), _ground[r1 * n + c1], nodeZ(r1));
        final v = positions.length ~/ 3;
        vertex(a, outward, _skirt);
        vertex(b, outward, _skirt);
        vertex(Vector3(b.x, baseY, b.z), outward, _skirt);
        vertex(Vector3(a.x, baseY, a.z), outward, _skirt);
        _addQuad(indices, positions, v, v + 1, v + 2, v + 3, outward);
      }
    }

    skirt([for (var c = 0; c < n; c++) (0, c)], Vector3(0, 0, 1)); // south
    skirt([for (var c = 0; c < n; c++) (n - 1, c)], Vector3(0, 0, -1)); // north
    skirt([for (var r = 0; r < n; r++) (r, 0)], Vector3(-1, 0, 0)); // west
    skirt([for (var r = 0; r < n; r++) (r, n - 1)], Vector3(1, 0, 0)); // east
    return _arrays(positions, normals, colors, indices);
  }

  /// Every building extruded from the ground, roofs flat.
  MeshArrays buildings() {
    final positions = <double>[], normals = <double>[], colors = <double>[];
    final indices = <int>[];
    final wall = linearColor(0x3C424C), roof = linearColor(0x4B525D);
    for (final _Solid(:ring, :ground, :top) in _solids) {
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i], c = ring[(i + 1) % ring.length];
        final edge = c - a;
        if (edge.length2 < 1e-4) continue;
        final outward = Vector3(edge.y, 0, -edge.x)..normalize();
        final v = positions.length ~/ 3;
        for (final p in [
          Vector3(a.x, ground, a.y),
          Vector3(c.x, ground, c.y),
          Vector3(c.x, top, c.y),
          Vector3(a.x, top, a.y),
        ]) {
          positions.addAll([p.x, p.y, p.z]);
          normals.addAll([outward.x, 0, outward.z]);
          colors.addAll([wall.x, wall.y, wall.z, 1]);
        }
        _addQuad(indices, positions, v, v + 1, v + 2, v + 3, outward);
      }
      final base = positions.length ~/ 3;
      for (final p in ring) {
        positions.addAll([p.x, top, p.y]);
        normals.addAll([0, 1, 0]);
        colors.addAll([roof.x, roof.y, roof.z, 1]);
      }
      for (final t in triangulate(ring)) {
        _addTriangleFacing(
          indices,
          positions,
          base + t.$1,
          base + t.$2,
          base + t.$3,
          Vector3(0, 1, 0),
        );
      }
    }
    return _arrays(positions, normals, colors, indices);
  }

  /// Roads as ribbons draped over the ground, broken where they would cross
  /// the circuit. Footpaths and race tracks are left out.
  MeshArrays roads() {
    final positions = <double>[], normals = <double>[], colors = <double>[];
    final indices = <int>[];
    final color = linearColor(0x363B43);
    for (final road in environment.roads) {
      final width = _roadWidth(road.kind);
      if (width == null) continue;
      // Points every ~10 m so the ribbon follows the ground.
      final dense = <Vector2>[];
      for (var i = 0; i + 1 < road.points.length; i++) {
        final a = road.points[i], b = road.points[i + 1];
        final steps = math.max(1, (a.distanceTo(b) / 10).ceil());
        for (var k = 0; k < steps; k++) {
          dense.add(a + (b - a) * (k / steps));
        }
      }
      if (road.points.isNotEmpty) dense.add(road.points.last);

      var previous = -1;
      for (var i = 0; i < dense.length; i++) {
        final p = dense[i];
        if (_beyondTrack(p.x, p.y, within: width / 2 + 3) < width / 2 + 3) {
          previous = -1;
          continue;
        }
        final ahead = dense[math.min(i + 1, dense.length - 1)];
        final behind = dense[math.max(i - 1, 0)];
        final direction = ahead - behind;
        if (direction.length2 < 1e-6) continue;
        direction.normalize();
        final side = Vector2(direction.y, -direction.x) * (width / 2);
        final v = positions.length ~/ 3;
        for (final q in [p + side, p - side]) {
          positions.addAll([q.x, groundAt(q.x, q.y) + 0.25, q.y]);
          normals.addAll([0, 1, 0]);
          colors.addAll([color.x, color.y, color.z, 1]);
        }
        if (previous >= 0) {
          _addTriangleFacing(
            indices,
            positions,
            previous,
            previous + 1,
            v,
            Vector3(0, 1, 0),
          );
          _addTriangleFacing(
            indices,
            positions,
            previous + 1,
            v + 1,
            v,
            Vector3(0, 1, 0),
          );
        }
        previous = v;
      }
    }
    return _arrays(positions, normals, colors, indices);
  }

  /// Lakes, rivers and sea as flat surfaces at their shore's lowest ground.
  MeshArrays water() {
    final positions = <double>[], normals = <double>[], colors = <double>[];
    final indices = <int>[];
    final color = linearColor(0x1B4A60);
    for (final w in environment.water) {
      final ring = _ccw(_open(w.points));
      if (ring.length < 3) continue;
      final level =
          ring
              .map((p) => environment.terrain.heightAt(p.x, p.y))
              .reduce(math.min) +
          0.05;
      final base = positions.length ~/ 3;
      for (final p in ring) {
        positions.addAll([p.x, level, p.y]);
        normals.addAll([0, 1, 0]);
        colors.addAll([color.x, color.y, color.z, 1]);
      }
      for (final t in triangulate(ring)) {
        _addTriangleFacing(
          indices,
          positions,
          base + t.$1,
          base + t.$2,
          base + t.$3,
          Vector3(0, 1, 0),
        );
      }
    }
    return _arrays(positions, normals, colors, indices);
  }

  /// Tree positions scattered through woodland, about one per [spacing]
  /// square meters, at most [limit].
  List<Vector3> trees({double spacing = 260, int limit = 3000, int seed = 7}) {
    final random = math.Random(seed);
    final out = <Vector3>[];
    for (final shape in environment.landuse) {
      if (shape.kind != 'wood' && shape.kind != 'forest') continue;
      final ring = _open(shape.points);
      if (ring.length < 3) continue;
      final box = _Box.of(ring);
      final wanted = (_area(ring).abs() / spacing).round();
      var placed = 0, attempts = 0;
      while (placed < wanted && attempts < wanted * 4 && out.length < limit) {
        attempts++;
        final x = box.minX + random.nextDouble() * (box.maxX - box.minX);
        final z = box.minZ + random.nextDouble() * (box.maxZ - box.minZ);
        if (!_inside(ring, x, z) || _beyondTrack(x, z, within: 8) < 8) continue;
        out.add(Vector3(x, groundAt(x, z), z));
        placed++;
      }
    }
    return out;
  }

  static double? _roadWidth(String highway) => switch (highway) {
    'motorway' || 'trunk' => 14,
    'primary' => 11,
    'secondary' => 9,
    'tertiary' => 7,
    'motorway_link' ||
    'trunk_link' ||
    'primary_link' ||
    'secondary_link' ||
    'tertiary_link' ||
    'unclassified' ||
    'residential' => 6,
    'service' || 'living_street' => 4,
    _ => null, // raceway (the circuit itself), footways, tracks, steps...
  };
}

/// Ear-clipping triangulation of a simple polygon given counter-clockwise
/// in the (x, y) plane, as index triples into [ring].
List<(int, int, int)> triangulate(List<Vector2> ring) {
  final n = ring.length;
  if (n < 3) return const [];
  final remaining = List.generate(n, (i) => i);
  final out = <(int, int, int)>[];
  double cross(Vector2 a, Vector2 b, Vector2 c) =>
      (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  bool inTriangle(Vector2 p, Vector2 a, Vector2 b, Vector2 c) =>
      cross(a, b, p) >= 0 && cross(b, c, p) >= 0 && cross(c, a, p) >= 0;

  var guard = n * n;
  while (remaining.length > 3 && guard-- > 0) {
    var clipped = false;
    for (var k = 0; k < remaining.length; k++) {
      final i0 = remaining[(k - 1 + remaining.length) % remaining.length];
      final i1 = remaining[k];
      final i2 = remaining[(k + 1) % remaining.length];
      final a = ring[i0], b = ring[i1], c = ring[i2];
      if (cross(a, b, c) <= 1e-9) continue; // reflex or degenerate
      var ear = true;
      for (final j in remaining) {
        if (j == i0 || j == i1 || j == i2) continue;
        if (inTriangle(ring[j], a, b, c)) {
          ear = false;
          break;
        }
      }
      if (!ear) continue;
      out.add((i0, i1, i2));
      remaining.removeAt(k);
      clipped = true;
      break;
    }
    if (!clipped) break; // self-intersecting input; keep what we have
  }
  if (remaining.length == 3) {
    out.add((remaining[0], remaining[1], remaining[2]));
  }
  return out;
}

double _area(List<Vector2> ring) {
  var sum = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i], b = ring[(i + 1) % ring.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum / 2;
}

/// Drops a repeated closing point.
List<Vector2> _open(List<Vector2> ring) =>
    ring.length > 1 && ring.first.distanceTo(ring.last) < 1e-6
    ? ring.sublist(0, ring.length - 1)
    : ring;

/// [ring] counter-clockwise in (x, y).
List<Vector2> _ccw(List<Vector2> ring) =>
    _area(ring) < 0 ? ring.reversed.toList() : ring;

bool _inside(List<Vector2> ring, double x, double z) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i], b = ring[j];
    if ((a.y > z) != (b.y > z) &&
        x < (b.x - a.x) * (z - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

/// A building as built: its footprint (counter-clockwise) and the heights
/// of its base and flat roof.
class _Solid {
  const _Solid(this.ring, this.box, this.ground, this.top);

  final List<Vector2> ring;
  final _Box box;
  final double ground;
  final double top;
}

/// Where the built scenery blocks a camera: the terrain, and buildings
/// bucketed on a grid so a sight line only tests the ones it passes.
class SceneryObstacles {
  SceneryObstacles._(this._groundAt, this._solids) {
    for (var i = 0; i < _solids.length; i++) {
      final box = _solids[i].box;
      for (var cx = _cell(box.minX); cx <= _cell(box.maxX); cx++) {
        for (var cz = _cell(box.minZ); cz <= _cell(box.maxZ); cz++) {
          _grid.putIfAbsent(_key(cx, cz), () => []).add(i);
        }
      }
    }
  }

  final double Function(double x, double z) _groundAt;
  final List<_Solid> _solids;
  final _grid = <int, List<int>>{};

  static const double _cellSize = 40;

  /// Distance between the points a sight line is tested at, in meters.
  static const double _step = 2.5;

  static int _cell(double v) => (v / _cellSize).floor();
  static int _key(int cx, int cz) => (cx + 32768) * 65536 + (cz + 32768);

  double groundAt(double x, double z) => _groundAt(x, z);

  /// Whether ([x], [z]) is inside a building or within [margin] of one.
  bool isBuilt(double x, double z, {double margin = 0}) {
    for (final (dx, dz) in [
      (0.0, 0.0),
      (margin, 0.0),
      (-margin, 0.0),
      (0.0, margin),
      (0.0, -margin),
    ]) {
      if (_buildingAt(x + dx, z + dz, double.negativeInfinity) != null) {
        return true;
      }
    }
    return false;
  }

  /// Whether the straight line from [from] to [to] clears the terrain and
  /// every building. The last few meters before [to] are not tested: a
  /// target on the track stands on ground of its own.
  bool canSee(Vector3 from, Vector3 to) {
    final d = to - from;
    final length = d.length;
    final steps = ((length - 3) / _step).floor();
    for (var k = 1; k <= steps; k++) {
      final f = k * _step / length;
      final x = from.x + d.x * f, y = from.y + d.y * f, z = from.z + d.z * f;
      if (y < _groundAt(x, z) - 0.5) return false;
      if (_buildingAt(x, z, y) != null) return false;
    }
    return true;
  }

  /// The building whose footprint holds ([x], [z]) and whose roof is above
  /// [below], if any.
  _Solid? _buildingAt(double x, double z, double below) {
    final cell = _grid[_key(_cell(x), _cell(z))];
    if (cell == null) return null;
    for (final i in cell) {
      final s = _solids[i];
      if (below < s.top && s.box.contains(x, z) && _inside(s.ring, x, z)) {
        return s;
      }
    }
    return null;
  }
}

class _Box {
  _Box(this.minX, this.maxX, this.minZ, this.maxZ);

  factory _Box.of(List<Vector2> points) {
    if (points.isEmpty) return _Box(0, -1, 0, -1);
    var minX = double.infinity, maxX = -double.infinity;
    var minZ = double.infinity, maxZ = -double.infinity;
    for (final p in points) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minZ = math.min(minZ, p.y);
      maxZ = math.max(maxZ, p.y);
    }
    return _Box(minX, maxX, minZ, maxZ);
  }

  final double minX, maxX, minZ, maxZ;

  bool contains(double x, double z) =>
      x >= minX && x <= maxX && z >= minZ && z <= maxZ;
}

/// Adds quad [a]-[b]-[c]-[d] (in order around it) facing [normal].
void _addQuad(
  List<int> indices,
  List<double> positions,
  int a,
  int b,
  int c,
  int d,
  Vector3 normal,
) {
  _addTriangleFacing(indices, positions, a, b, c, normal);
  _addTriangleFacing(indices, positions, a, c, d, normal);
}

/// Adds triangle [a], [b], [c], wound so it faces [normal].
void _addTriangleFacing(
  List<int> indices,
  List<double> positions,
  int a,
  int b,
  int c,
  Vector3 normal,
) {
  Vector3 at(int i) =>
      Vector3(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2]);
  final pa = at(a);
  final face = (at(b) - pa).cross(at(c) - pa);
  if (face.dot(normal) >= 0) {
    indices.addAll([a, b, c]);
  } else {
    indices.addAll([a, c, b]);
  }
}

MeshArrays _arrays(
  List<double> positions,
  List<double> normals,
  List<double> colors,
  List<int> indices,
) => MeshArrays(
  positions: Float32List.fromList(positions),
  normals: Float32List.fromList(normals),
  colors: Float32List.fromList(colors),
  indices: Uint32List.fromList(indices),
);
