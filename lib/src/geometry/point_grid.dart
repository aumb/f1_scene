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
  ///
  /// With [maxDistance], gives up beyond it and returns index -1.
  ({int index, double distanceSquared}) nearest(
    double x,
    double y, {
    double? maxDistance,
  }) {
    final (cx, cy) = _cellOf(x, y);
    var best = -1;
    var bestD2 = maxDistance == null
        ? double.infinity
        : maxDistance * maxDistance;
    void visit(int gx, int gy) {
      final cell = _cells[(gx, gy)];
      if (cell == null) return;
      for (final i in cell) {
        final ex = xs[i] - x, ey = ys[i] - y;
        final d2 = ex * ex + ey * ey;
        if (d2 < bestD2) {
          bestD2 = d2;
          best = i;
        }
      }
    }

    for (var ring = 0; ; ring++) {
      // Every point outside the searched rings is at least this far away.
      final reach = (ring - 1) * cellSize;
      if (reach > 0 && reach * reach > bestD2) break;
      if (ring == 0) {
        visit(cx, cy);
      } else {
        // Only the ring's perimeter: its inside was searched already.
        for (var d = -ring; d <= ring; d++) {
          visit(cx + d, cy - ring);
          visit(cx + d, cy + ring);
        }
        for (var d = -ring + 1; d < ring; d++) {
          visit(cx - ring, cy + d);
          visit(cx + ring, cy + d);
        }
      }
      // Far outside the data: fall back to a scan rather than ringing forever.
      if (best < 0 && maxDistance == null && ring > 64) return _scan(x, y);
    }
    return (index: best, distanceSquared: best < 0 ? double.infinity : bestD2);
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
