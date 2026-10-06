import 'dart:math' as math;

/// Uniform grid over 2D points for nearest-neighbour queries.
class PointGrid {
  PointGrid(this.xs, this.ys, {this.cellSize = 20})
    : assert(xs.length == ys.length && xs.isNotEmpty) {
    for (var i = 0; i < xs.length; i++) {
      _cells.putIfAbsent(_cellOf(xs[i], ys[i]), () => []).add(i);
    }
  }

  final List<double> xs;
  final List<double> ys;
  final double cellSize;
  final _cells = <(int, int), List<int>>{};

  (int, int) _cellOf(double x, double y) =>
      ((x / cellSize).floor(), (y / cellSize).floor());

  /// Index of the point closest to ([x], [y]) and its squared distance.
  ({int index, double distanceSquared}) nearest(double x, double y) {
    final (cx, cy) = _cellOf(x, y);
    var best = -1;
    var bestD2 = double.infinity;
    for (var ring = 0; ; ring++) {
      // Every point outside the searched rings is at least this far away.
      final reach = (ring - 1) * cellSize;
      if (best >= 0 && reach > 0 && reach * reach > bestD2) break;
      for (var dx = -ring; dx <= ring; dx++) {
        for (var dy = -ring; dy <= ring; dy++) {
          if (math.max(dx.abs(), dy.abs()) != ring) continue;
          final cell = _cells[(cx + dx, cy + dy)];
          if (cell == null) continue;
          for (final i in cell) {
            final ex = xs[i] - x, ey = ys[i] - y;
            final d2 = ex * ex + ey * ey;
            if (d2 < bestD2) {
              bestD2 = d2;
              best = i;
            }
          }
        }
      }
      // Far outside the data: fall back to a scan rather than ringing forever.
      if (best < 0 && ring > 64) return _scan(x, y);
    }
    return (index: best, distanceSquared: bestD2);
  }

  ({int index, double distanceSquared}) _scan(double x, double y) {
    var best = 0;
    var bestD2 = double.infinity;
    for (var i = 0; i < xs.length; i++) {
      final ex = xs[i] - x, ey = ys[i] - y;
      final d2 = ex * ex + ey * ey;
      if (d2 < bestD2) {
        bestD2 = d2;
        best = i;
      }
    }
    return (index: best, distanceSquared: bestD2);
  }
}
