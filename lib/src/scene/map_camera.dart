import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// A map-style camera: it orbits a target point on the ground, pans by
/// dragging the ground itself, and zooms toward the point under the cursor.
///
/// Unlike [OrbitCameraController], whose pan moves the target in the screen
/// plane and whose zoom always heads for the target, everything here stays
/// on the ground plane, the way map apps behave.
class MapCameraController extends CameraController {
  MapCameraController({
    double distance = 2500,
    double azimuth = 0,
    double polar = 0.8,
    this.minDistance = 25,
    this.maxDistance = 9000,
    this.minPolar = 0.08,
    this.maxPolar = math.pi / 2 - 0.02,
    super.smoothing = 0.12,
  }) : _distance = distance,
       _distanceGoal = distance,
       _azimuth = azimuth,
       _azimuthGoal = azimuth,
       _polar = polar,
       _polarGoal = polar;

  final double minDistance;
  final double maxDistance;
  final double minPolar;
  final double maxPolar;

  /// Supplies the camera to cast pointer rays from; set once mounted.
  Camera Function()? camera;

  Vector3 _target = Vector3.zero();
  Vector3 _targetGoal = Vector3.zero();
  double _distance;
  double _distanceGoal;
  double _azimuth;
  double _azimuthGoal;
  double _polar;
  double _polarGoal;

  /// Where the target is easing to.
  Vector3 get targetGoal => _targetGoal.clone();

  /// The distance from the target now, as eased.
  double get distance => _distance;

  /// Eases to look at [center] from [distance] away.
  void frame(Vector3 center, double distance) {
    _targetGoal = center.clone();
    _distanceGoal = distance.clamp(minDistance, maxDistance);
  }

  /// Eases to the given viewing angles, turning the short way round.
  void setAngles({required double azimuth, required double polar}) {
    final turn = (azimuth - _azimuthGoal + math.pi) % (2 * math.pi) - math.pi;
    _azimuthGoal += turn;
    _polarGoal = polar.clamp(minPolar, maxPolar);
  }

  /// A drag orbits: a drag the height of the view turns half a circle.
  @override
  void handleDragUpdate(Offset delta) {
    final k = math.pi / math.max(1.0, viewportSize.height);
    // Drag down to look from higher up, as in map apps.
    orbitBy(-delta.dx * k, delta.dy * k);
  }

  /// Rotates around the target: [deltaAzimuth] about world up, [deltaPolar]
  /// in elevation, radians.
  void orbitBy(double deltaAzimuth, double deltaPolar) {
    _azimuthGoal += deltaAzimuth;
    _polarGoal = (_polarGoal + deltaPolar).clamp(minPolar, maxPolar);
  }

  /// Moves the ground so the point under [from] ends up under [to]
  /// (screen positions in logical pixels): dragging the map.
  void dragGround(Offset from, Offset to) {
    final a = _groundUnder(from), b = _groundUnder(to);
    if (a == null || b == null) return;
    final delta = a - b;
    // Keep a runaway drag near the horizon from flinging the camera away.
    final limit = _distance * 2;
    if (delta.length > limit) delta.scale(limit / delta.length);
    _targetGoal += delta;
  }

  /// Zooms by [factor] (above 1 moves closer) toward the ground under
  /// [focal], keeping that point fixed on screen.
  void zoomAt(double factor, Offset? focal) {
    if (factor <= 0) return;
    final newDistance = (_distanceGoal / factor).clamp(
      minDistance,
      maxDistance,
    );
    final applied = _distanceGoal / newDistance;
    final point = focal == null ? null : _groundUnder(focal);
    if (point != null && point.distanceTo(_targetGoal) < _distance * 4) {
      _targetGoal = point + (_targetGoal - point) / applied;
    }
    _distanceGoal = newDistance;
  }

  /// Where the ray through screen point [p] meets the horizontal plane at
  /// the target's height, or null when it points at or above the horizon.
  Vector3? _groundUnder(Offset p) {
    final camera = this.camera?.call();
    if (camera == null) return null;
    final ray = camera.screenPointToRay(p, viewportSize);
    final dy = ray.direction.y;
    if (dy > -1e-4) return null;
    final t = (_target.y - ray.origin.y) / dy;
    if (t <= 0) return null;
    return ray.origin + ray.direction * t;
  }

  @override
  void update(double deltaSeconds) {
    final r = smoothingResponse(clampDeltaSeconds(deltaSeconds));
    _azimuth += (_azimuthGoal - _azimuth) * r;
    _polar += (_polarGoal - _polar) * r;
    // Ease distance proportionally, so zooming feels the same near or far.
    _distance *= math.pow(_distanceGoal / _distance, r).toDouble();
    _target += (_targetGoal - _target) * r;
    final horizontal = math.cos(_polar) * _distance;
    final eye =
        _target +
        Vector3(-math.sin(_azimuth), 0, -math.cos(_azimuth)) * horizontal +
        Vector3(0, math.sin(_polar) * _distance, 0);
    node.lookAtFrom(eye, _target);
  }
}
