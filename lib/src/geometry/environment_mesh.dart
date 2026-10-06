import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../data/circuit_environment.dart';
import 'mesh_arrays.dart';
import 'track_projector.dart';

/// Builds the meshes around a circuit from its [CircuitEnvironment].
///
/// The terrain is upsampled, then cut down or built up to sit just under the
/// track, and everything else (buildings, roads, water, trees) stands on
/// that shaped ground. Buildings, roads and trees that would touch the
/// circuit are left out, and nothing reaches past the ground's edges:
/// OpenStreetMap shapes that cross them come whole, roads sometimes
/// kilometres beyond.
class EnvironmentMeshBuilder {
  EnvironmentMeshBuilder(this.environment, this.track)
    : _ground = _upsample(environment.terrain) {
    _colors = List.filled(_ground.size * _ground.size, _terrain);
    _tintGround();
    _sinkWater();
    _fitToTrack();
  }

  final CircuitEnvironment environment;
  final TrackProjector track;

  /// The terrain at twice its resolution, shaped to the track.
  final TerrainGrid _ground;

  /// The ground's colour at each of its nodes.
  late final List<Vector4> _colors;

  /// The ground's extent; everything built stays within it.
  late final _bounds = _Box(
    _ground.minX,
    _ground.maxX,
    _ground.southZ,
    _ground.northZ,
  );

  static final _terrain = linearColor(0x22262D);
  static final _grass = linearColor(0x26332A);
  static final _wood = linearColor(0x1E2C21);
  static final _built = linearColor(0x2A2D33);
  static final _waterBed = linearColor(0x14303E);
  static final _sea = linearColor(0x173A4C);
  static final _skirt = linearColor(0x15181D);

  /// How the ground meets the track: flat and [_bedDepth] below it out to
  /// [_runoff] meters past the edge (plus a grid cell), then easing back to
  /// the real terrain at most [_slope] steep, and untouched beyond [_reach].
  static const double _bedDepth = 1.5, _runoff = 12, _slope = 0.35;
  static const double _reach = 150;

  /// Height of a building OpenStreetMap gives none for, meters.
  static const double _defaultHeight = 8;

  /// Ground height at scene ([x], [z]), as shaped to the track.
  double groundAt(double x, double z) => _ground.heightAt(x, z);

  /// Lowest ground height, for sizing the block under it.
  double get lowestGround => _ground.heights.reduce(math.min);

  /// What blocks a camera's view or stands where it would: this terrain
  /// and these buildings, as built.
  late final SceneryObstacles obstacles = SceneryObstacles._(groundAt, _solids);

  /// The buildings that get built: all but those touching the track.
  late final List<_Solid> _solids = [
    for (final building in environment.buildings) ?_solidOf(building),
  ];

  _Solid? _solidOf(EnvironmentShape building) {
    final ring = _ccw(_open(building.points));
    if (ring.length < 3) return null;
    if (!ring.every((p) => _bounds.contains(p.x, p.y))) return null;
    if (!_clearOfTrack(ring)) return null;
    final ground = ring.map((p) => groundAt(p.x, p.y)).reduce(math.min);
    final height = building.height > 0 ? building.height : _defaultHeight;
    return _Solid(ring, _Box.of(ring), ground, ground + height);
  }

  /// Whether a footprint keeps clear of the track: no corner on it, and its
  /// middle 6 m or more past the edge (OpenStreetMap footprints are a few
  /// meters off at times).
  bool _clearOfTrack(List<Vector2> ring) {
    final middle =
        ring.fold(Vector2.zero(), (sum, p) => sum + p) / ring.length.toDouble();
    return _beyondTrack(middle.x, middle.y, within: 6) >= 6 &&
        ring.every((p) => _beyondTrack(p.x, p.y, within: 1) > 0);
  }

  /// Distance from ([x], [z]) to the nearest track edge, negative on the
  /// track. Only searches as far as [within] past the widest edge; anything
  /// further reports [within].
  double _beyondTrack(double x, double z, {required double within}) {
    final p = track.projectWithin(x, z, within + _widestHalf);
    if (p == null) return within;
    return p.distance - _widerHalf(p.along);
  }

  /// The wider of the two centerline-to-edge distances at [along]: measuring
  /// from it errs toward keeping clear of the track.
  double _widerHalf(double along) {
    final (:min, :max) = track.lateralLimits(along);
    return math.max(-min, max);
  }

  /// The widest centerline-to-edge distance anywhere on the circuit.
  late final double _widestHalf = [
    ...track.stations.leftOffset,
    ...track.stations.rightOffset,
  ].reduce(math.max);

  /// [grid] with a node added between every two, interpolated.
  static TerrainGrid _upsample(TerrainGrid grid) {
    final n = grid.size * 2 - 1;
    final fine = TerrainGrid(
      size: n,
      minX: grid.minX,
      maxX: grid.maxX,
      southZ: grid.southZ,
      northZ: grid.northZ,
      heights: Float64List(n * n),
    );
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        fine.heights[r * n + c] = grid.heightAt(fine.nodeX(c), fine.nodeZ(r));
      }
    }
    return fine;
  }

  /// Calls [visit] with each ground node inside [ring], looking only within
  /// its bounding box rather than testing every node against every shape
  /// (some circuits have thousands).
  void _forNodesInside(List<Vector2> ring, void Function(int node) visit) {
    if (ring.length < 3) return;
    final box = _Box.of(ring);
    final (r0, c0) = _ground.nearestNode(box.minX, box.minZ);
    final (r1, c1) = _ground.nearestNode(box.maxX, box.maxZ);
    for (var r = math.min(r0, r1); r <= math.max(r0, r1); r++) {
      for (var c = math.min(c0, c1); c <= math.max(c0, c1); c++) {
        if (_inside(ring, _ground.nodeX(c), _ground.nodeZ(r))) {
          visit(r * _ground.size + c);
        }
      }
    }
  }

  /// Colours the sea, from the terrain's coarse flood mask, and tints the
  /// land by use; woods win over other uses.
  void _tintGround() {
    final n = _ground.size;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (environment.terrain.isSea(_ground.nodeX(c), _ground.nodeZ(r))) {
          _colors[r * n + c] = _sea;
        }
      }
    }
    for (final shape in environment.landuse) {
      final color = switch (shape.kind) {
        'wood' || 'forest' => _wood,
        'grass' || 'park' || 'meadow' => _grass,
        _ => _built,
      };
      _forNodesInside(shape.points, (i) {
        if (_colors[i] != _wood) _colors[i] = color;
      });
    }
  }

  /// Sinks the ground under each lake and river a little below its surface.
  void _sinkWater() {
    for (final w in environment.water) {
      if (w.points.isEmpty) continue;
      final level = _waterLevel(w.points);
      _forNodesInside(w.points, (i) {
        _ground.heights[i] = math.min(_ground.heights[i], level - 0.5);
        _colors[i] = _waterBed;
      });
    }
  }

  /// A body of water's surface: at the lowest real terrain along its shore.
  double _waterLevel(List<Vector2> shore) =>
      shore.map((p) => environment.terrain.heightAt(p.x, p.y)).reduce(math.min);

  /// Shapes the ground to the track: cuts it down where it would rise
  /// through the ribbon, builds it up where it falls away below, and eases
  /// back to the real terrain away from the edge.
  void _fitToTrack() {
    final n = _ground.size;
    // The flat bed reaches a whole cell further, because the surface between
    // nodes interpolates: a sloping node any closer could lift it over the
    // track.
    final cell = math.sqrt(
      math.pow(_ground.nodeX(1) - _ground.nodeX(0), 2) +
          math.pow(_ground.nodeZ(1) - _ground.nodeZ(0), 2),
    );
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final x = _ground.nodeX(c), z = _ground.nodeZ(r);
        final p = track.projectWithin(x, z, _reach + _widestHalf);
        if (p == null) continue;
        final beyond = p.distance - _widerHalf(p.along);
        final bed = track.stations.center[p.station].y - _bedDepth;
        final give = math.max(0.0, beyond - _runoff - cell) * _slope;
        final i = r * n + c;
        _ground.heights[i] = _ground.heights[i].clamp(bed - give, bed + give);
      }
    }
  }

  /// The terrain surface plus skirts down to [baseY], one diorama block.
  MeshArrays terrainBlock(double baseY) {
    final n = _ground.size;
    final mesh = MeshBuilder();
    final dx = _ground.nodeX(1) - _ground.nodeX(0);
    final dz = _ground.nodeZ(1) - _ground.nodeZ(0);
    double h(int r, int c) =>
        _ground.heights[r.clamp(0, n - 1) * n + c.clamp(0, n - 1)];
    Vector3 node(int r, int c) =>
        Vector3(_ground.nodeX(c), h(r, c), _ground.nodeZ(r));

    // Surface, with normals from the height differences.
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final normal = Vector3(
          -(h(r, c + 1) - h(r, c - 1)) / (2 * dx),
          1,
          -(h(r + 1, c) - h(r - 1, c)) / (2 * dz),
        )..normalize();
        mesh.vertex(node(r, c), normal, color: _colors[r * n + c]);
      }
    }
    final up = Vector3(0, 1, 0);
    for (var r = 0; r + 1 < n; r++) {
      for (var c = 0; c + 1 < n; c++) {
        final v00 = r * n + c, v01 = v00 + 1, v10 = v00 + n, v11 = v10 + 1;
        mesh.quadFacing(v01, v11, v10, v00, up);
      }
    }

    // Skirts around the four edges, facing out.
    void skirt(List<(int, int)> nodes, Vector3 outward) {
      for (var k = 0; k + 1 < nodes.length; k++) {
        final a = node(nodes[k].$1, nodes[k].$2);
        final b = node(nodes[k + 1].$1, nodes[k + 1].$2);
        mesh.flatQuad(
          a,
          b,
          Vector3(b.x, baseY, b.z),
          Vector3(a.x, baseY, a.z),
          outward,
          color: _skirt,
        );
      }
    }

    skirt([for (var c = 0; c < n; c++) (0, c)], Vector3(0, 0, -1)); // south
    skirt([for (var c = 0; c < n; c++) (n - 1, c)], Vector3(0, 0, 1)); // north
    skirt([for (var r = 0; r < n; r++) (r, 0)], Vector3(-1, 0, 0)); // west
    skirt([for (var r = 0; r < n; r++) (r, n - 1)], Vector3(1, 0, 0)); // east
    return mesh.build();
  }

  /// Every building extruded from the ground, roofs flat.
  MeshArrays buildings() {
    final mesh = MeshBuilder();
    final wall = linearColor(0x3C424C), roof = linearColor(0x4B525D);
    final up = Vector3(0, 1, 0);
    for (final _Solid(:ring, :ground, :top) in _solids) {
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i], c = ring[(i + 1) % ring.length];
        final edge = c - a;
        if (edge.length2 < 1e-4) continue;
        // The ring runs counter-clockwise in (x, z), so outside is to the
        // right of each edge.
        final outward = Vector3(edge.y, 0, -edge.x)..normalize();
        mesh.flatQuad(
          Vector3(a.x, ground, a.y),
          Vector3(c.x, ground, c.y),
          Vector3(c.x, top, c.y),
          Vector3(a.x, top, a.y),
          outward,
          color: wall,
        );
      }
      final base = mesh.vertexCount;
      for (final p in ring) {
        mesh.vertex(Vector3(p.x, top, p.y), up, color: roof);
      }
      for (final (a, b, c) in triangulate(ring)) {
        mesh.triangleFacing(base + a, base + b, base + c, up);
      }
    }
    return mesh.build();
  }

  /// Roads as ribbons draped over the ground, broken where they would cross
  /// the circuit or leave the ground. Footpaths and race tracks are left
  /// out.
  MeshArrays roads() {
    final mesh = MeshBuilder();
    final color = linearColor(0x363B43);
    for (final road in environment.roads) {
      final width = _roadWidth(road.kind);
      if (width == null) continue;
      // Kept far enough inside the edges that the ribbon's sides are too.
      for (final run in _bounds.inset(width / 2).runsInside(road.points)) {
        _addRoad(mesh, run, width, color);
      }
    }
    return mesh.build();
  }

  /// One stretch of road through [line], [width] meters wide.
  void _addRoad(
    MeshBuilder mesh,
    List<Vector2> line,
    double width,
    Vector4 color,
  ) {
    final up = Vector3(0, 1, 0);
    // Points every ~10 m so the ribbon follows the ground.
    final dense = <Vector2>[];
    for (var i = 0; i + 1 < line.length; i++) {
      final a = line[i], b = line[i + 1];
      final steps = math.max(1, (a.distanceTo(b) / 10).ceil());
      for (var k = 0; k < steps; k++) {
        dense.add(a + (b - a) * (k / steps));
      }
    }
    dense.add(line.last);

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
      final v = mesh.vertexCount;
      for (final q in [p + side, p - side]) {
        mesh.vertex(
          Vector3(q.x, groundAt(q.x, q.y) + 0.25, q.y),
          up,
          color: color,
        );
      }
      if (previous >= 0) {
        mesh.quadFacing(previous, previous + 1, v + 1, v, up);
      }
      previous = v;
    }
  }

  /// Lakes, rivers and sea as flat surfaces at their shore's lowest ground.
  MeshArrays water() {
    final mesh = MeshBuilder();
    final color = linearColor(0x1B4A60);
    final up = Vector3(0, 1, 0);
    for (final w in environment.water) {
      final ring = _bounds.clipPolygon(_ccw(_open(w.points)));
      if (ring.length < 3) continue;
      final level = _waterLevel(ring) + 0.05;
      final base = mesh.vertexCount;
      for (final p in ring) {
        mesh.vertex(Vector3(p.x, level, p.y), up, color: color);
      }
      for (final (a, b, c) in triangulate(ring)) {
        mesh.triangleFacing(base + a, base + b, base + c, up);
      }
    }
    return mesh.build();
  }

  /// Tree positions scattered through woodland, about one per [areaPerTree]
  /// square meters, at most [limit].
  List<Vector3> trees({
    double areaPerTree = 260,
    int limit = 3000,
    int seed = 7,
  }) {
    final random = math.Random(seed);
    final out = <Vector3>[];
    for (final shape in environment.landuse) {
      if (shape.kind != 'wood' && shape.kind != 'forest') continue;
      final ring = _open(shape.points);
      if (ring.length < 3) continue;
      final box = _Box.of(ring);
      final wanted = (_area(ring).abs() / areaPerTree).round();
      var placed = 0, attempts = 0;
      while (placed < wanted && attempts < wanted * 4 && out.length < limit) {
        attempts++;
        final x = box.minX + random.nextDouble() * (box.maxX - box.minX);
        final z = box.minZ + random.nextDouble() * (box.maxZ - box.minZ);
        if (!_bounds.contains(x, z) || !_inside(ring, x, z)) continue;
        if (_beyondTrack(x, z, within: 8) < 8) continue;
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

  /// This box shrunk by [margin] on every side.
  _Box inset(double margin) =>
      _Box(minX + margin, maxX - margin, minZ + margin, maxZ - margin);

  /// The part of the segment from [a] to [b] inside this box, or null when
  /// it misses (Liang-Barsky: each edge narrows the range of the segment's
  /// parameter that lies on its inner side).
  (Vector2, Vector2)? clip(Vector2 a, Vector2 b) {
    final d = b - a;
    var t0 = 0.0, t1 = 1.0;
    for (final (p, q) in [
      (-d.x, a.x - minX),
      (d.x, maxX - a.x),
      (-d.y, a.y - minZ),
      (d.y, maxZ - a.y),
    ]) {
      if (p == 0) {
        // Parallel to this edge: wholly inside it or wholly out.
        if (q < 0) return null;
        continue;
      }
      final t = q / p;
      if (p < 0) {
        if (t > t1) return null;
        t0 = math.max(t0, t);
      } else {
        if (t < t0) return null;
        t1 = math.min(t1, t);
      }
    }
    return (a + d * t0, a + d * t1);
  }

  /// The stretches of the polyline [line] inside this box, cut where it
  /// crosses the edges.
  List<List<Vector2>> runsInside(List<Vector2> line) {
    final runs = <List<Vector2>>[];
    List<Vector2>? run;
    for (var i = 0; i + 1 < line.length; i++) {
      final clipped = clip(line[i], line[i + 1]);
      if (clipped == null) {
        run = null;
        continue;
      }
      final (a, b) = clipped;
      if (run == null || run.last.distanceTo(a) > 1e-6) runs.add(run = [a]);
      run.add(b);
      // Left the box: the next stretch inside starts afresh.
      if (b.distanceTo(line[i + 1]) > 1e-6) run = null;
    }
    return runs;
  }

  /// The polygon [ring] cut down to this box (Sutherland-Hodgman: clip
  /// against each edge in turn). Keeps the winding.
  List<Vector2> clipPolygon(List<Vector2> ring) {
    var out = ring;
    for (final (inside, cross)
        in <(bool Function(Vector2), Vector2 Function(Vector2, Vector2))>[
          ((p) => p.x >= minX, (a, b) => _atX(a, b, minX)),
          ((p) => p.x <= maxX, (a, b) => _atX(a, b, maxX)),
          ((p) => p.y >= minZ, (a, b) => _atY(a, b, minZ)),
          ((p) => p.y <= maxZ, (a, b) => _atY(a, b, maxZ)),
        ]) {
      if (out.isEmpty) break;
      final next = <Vector2>[];
      for (var i = 0; i < out.length; i++) {
        final a = out[i], b = out[(i + 1) % out.length];
        if (inside(a)) next.add(a);
        if (inside(a) != inside(b)) next.add(cross(a, b));
      }
      out = next;
    }
    return out;
  }

  /// Where the segment from [a] to [b] crosses x = [x], and z = [z].
  static Vector2 _atX(Vector2 a, Vector2 b, double x) =>
      a + (b - a) * ((x - a.x) / (b.x - a.x));
  static Vector2 _atY(Vector2 a, Vector2 b, double z) =>
      a + (b - a) * ((z - a.y) / (b.y - a.y));
}
