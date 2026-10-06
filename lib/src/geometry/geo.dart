import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Projects WGS84 longitude/latitude onto a local tangent plane in meters.
///
/// Scene axes: +X is east, +Z is north, +Y is up. flutter_scene's world is
/// left-handed (seen from above with north up, +X is on the right), so this
/// is what puts east on the right and draws each circuit as on a map, not
/// mirrored.
///
/// An equirectangular projection around [originLon]/[originLat], scaled by
/// the Earth's radii of curvature there: across the few kilometres of a
/// circuit, positions stay well under a meter from true.
class LocalProjection {
  factory LocalProjection(double originLon, double originLat) {
    final phi = originLat * math.pi / 180;
    final w = 1 - _e2 * math.pow(math.sin(phi), 2);
    // Radii of curvature along the meridian (north-south) and the prime
    // vertical (east-west) at the origin.
    final meridian = _a * (1 - _e2) / math.pow(w, 1.5);
    final primeVertical = _a / math.sqrt(w);
    return LocalProjection._(
      originLon,
      originLat,
      primeVertical * math.cos(phi) * math.pi / 180,
      meridian * math.pi / 180,
    );
  }

  LocalProjection._(
    this.originLon,
    this.originLat,
    this._metersPerDegLon,
    this._metersPerDegLat,
  );

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

  /// The WGS84 ellipsoid: equatorial radius in meters, and the square of
  /// its eccentricity.
  static const double _a = 6378137, _e2 = 6.69437999014e-3;

  final double originLon;
  final double originLat;
  final double _metersPerDegLon;
  final double _metersPerDegLat;

  /// Returns the scene position of [lon]/[lat] at height [y].
  Vector3 project(double lon, double lat, [double y = 0]) => Vector3(
    (lon - originLon) * _metersPerDegLon,
    y,
    (lat - originLat) * _metersPerDegLat,
  );
}
