import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Projects WGS84 longitude/latitude onto a local tangent plane in meters.
///
/// Scene axes: +X is east, -Z is north, +Y is up. An equirectangular
/// projection around [originLon]/[originLat] is accurate to well under a
/// meter across a circuit-sized area.
class LocalProjection {
  LocalProjection(this.originLon, this.originLat)
    : _metersPerDegLon = _metersPerDegLat * math.cos(originLat * math.pi / 180);

  /// Centers the projection on the bounding box of [lonLat] pairs.
  factory LocalProjection.centeredOn(Iterable<(double, double)> lonLat) {
    var minLon = double.infinity, maxLon = -double.infinity;
    var minLat = double.infinity, maxLat = -double.infinity;
    for (final (lon, lat) in lonLat) {
      minLon = math.min(minLon, lon);
      maxLon = math.max(maxLon, lon);
      minLat = math.min(minLat, lat);
      maxLat = math.max(maxLat, lat);
    }
    return LocalProjection((minLon + maxLon) / 2, (minLat + maxLat) / 2);
  }

  static const double _metersPerDegLat = 111320;

  final double originLon;
  final double originLat;
  final double _metersPerDegLon;

  /// Returns the scene position of [lon]/[lat] at height [y].
  Vector3 project(double lon, double lat, [double y = 0]) => Vector3(
    (lon - originLon) * _metersPerDegLon,
    y,
    -(lat - originLat) * _metersPerDegLat,
  );
}
