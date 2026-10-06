import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../geometry/track_mesh.dart';
import '../geometry/track_projector.dart';
import '../race/car_motion.dart';

/// Third-person camera behind a car, turning with it.
///
/// Unlike [FollowCameraController], whose orbit is fixed in world space, the
/// yaw eases toward the car's heading, so the view stays behind the car
/// through corners. Drag orbits around the car, scroll dollies.
class ChaseCameraController extends CameraController {
  ChaseCameraController() : super(smoothing: 0.2);

  /// The pose to chase, read every frame.
  CarPose? Function()? target;

  double distance = 18;
  double pitch = 0.24;

  /// Extra yaw from dragging, relative to straight behind the car.
  double yawOffset = 0;

  final _eye = Vector3.zero();
  final _look = Vector3.zero();
  double _yaw = 0;
  bool _initialized = false;

  /// Snaps to the target on the next frame instead of easing over.
  void reset() => _initialized = false;

  /// Back to straight behind the car at the default distance.
  void resetView() {
    distance = 18;
    pitch = 0.24;
    yawOffset = 0;
    reset();
  }

  @override
  void update(double deltaSeconds) {
    final pose = target?.call();
    if (pose == null) return;
    final dt = clampDeltaSeconds(deltaSeconds);
    final goalYaw = pose.heading + yawOffset;
    if (_initialized) {
      _yaw += _wrapPi(goalYaw - _yaw) * settleResponse(0.6, dt);
    } else {
      _yaw = goalYaw;
    }
    final look = pose.position + Vector3(0, 1.0, 0);
    final eye =
        look -
        Vector3(math.sin(_yaw), 0, math.cos(_yaw)) *
            (math.cos(pitch) * distance) +
        Vector3(0, math.sin(pitch) * distance, 0);
    // Cut instead of swooping when the car jumps (a seek, a new driver).
    if (!_initialized || _look.distanceTo(look) > 150) {
      _eye.setFrom(eye);
      _look.setFrom(look);
      _initialized = true;
    } else {
      _eye.addScaled(eye - _eye, smoothingResponse(dt));
      _look.addScaled(look - _look, settleResponse(0.05, dt));
    }
    node.lookAtFrom(_eye, _look);
  }

  @override
  void handleDragUpdate(Offset delta) {
    final k = math.pi / viewportSize.height;
    yawOffset -= delta.dx * k;
    pitch = (pitch + delta.dy * k).clamp(0.02, 1.3);
  }

  @override
  void handleScroll(double scrollDelta) {
    distance = (distance * math.exp(scrollDelta / 600)).clamp(6.0, 200.0);
  }

  @override
  void handleScaleUpdate(double scaleFactor, Offset focalDelta) {
    distance = (distance / scaleFactor).clamp(6.0, 200.0);
  }
}

/// Broadcast-style camera: fixed posts around the circuit, cutting to the
/// one the car is approaching and zooming to keep it framed.
class TvCameraController extends CameraController {
  TvCameraController({required this.posts, required this.projection})
    : super(smoothing: 0.15);

  /// Trackside camera positions, from [TvCameraController.placePosts].
  final List<Vector3> posts;

  /// The lens to zoom; restore its field of view when leaving this mode.
  final PerspectiveProjection projection;

  /// The pose to film, read every frame.
  CarPose? Function()? target;

  /// Width of the shot around the car, in meters.
  static const double _frameWidth = 26;

  int? _active;
  final _look = Vector3.zero();

  /// Picks a fresh post on the next frame.
  void reset() => _active = null;

  @override
  void update(double deltaSeconds) {
    final pose = target?.call();
    if (pose == null || posts.isEmpty) return;
    final dt = clampDeltaSeconds(deltaSeconds);

    // Prefer the post the car is heading toward, and only cut when another
    // is clearly better, so shots hold rather than flicker between posts.
    final ahead =
        pose.position +
        Vector3(math.sin(pose.heading), 0, math.cos(pose.heading)) * 70;
    var best = 0;
    for (var i = 1; i < posts.length; i++) {
      if (posts[i].distanceTo(ahead) < posts[best].distanceTo(ahead)) best = i;
    }
    final active = _active;
    final cut =
        active == null ||
        posts[best].distanceTo(ahead) < 0.7 * posts[active].distanceTo(ahead) ||
        posts[active].distanceTo(pose.position) > 420;
    final look = pose.position + Vector3(0, 0.6, 0);
    if (cut) {
      _active = best;
      _look.setFrom(look);
    } else {
      _look.addScaled(look - _look, smoothingResponse(dt));
    }

    final eye = posts[_active!];
    final distance = math.max(1.0, eye.distanceTo(_look));
    projection.fovRadiansY = (2 * math.atan(_frameWidth / 2 / distance)).clamp(
      4 * degrees2Radians,
      40 * degrees2Radians,
    );
    node.lookAtFrom(eye, _look);
  }

  /// Camera posts every ~[spacing] meters around the circuit, on the outside
  /// of the bend, [setback] meters beyond the edge and raised [height].
  /// Posts that would sit over another part of the track are dropped.
  static List<Vector3> placePosts(
    TrackStations stations,
    TrackProjector projector, {
    double spacing = 220,
    double setback = 28,
    double height = 9,
  }) {
    final n = stations.length;
    final step = math.max(1, (spacing / projector.metersPerStation).round());
    final reach = math.max(1, (50 / projector.metersPerStation).round());
    final posts = <Vector3>[];
    for (var i = 0; i < n; i += step) {
      final a = stations.forward[(i - reach + n) % n];
      final b = stations.forward[(i + reach) % n];
      // Outside of a left-hander is the right, and vice versa.
      final turningLeft = a.cross(b).y > 0;
      for (final side in turningLeft ? [-1.0, 1.0] : [1.0, -1.0]) {
        final edge = side > 0
            ? stations.leftOffset[i]
            : stations.rightOffset[i];
        final p =
            stations.center[i] +
            stations.left[i] * (side * (edge + setback)) +
            Vector3(0, height, 0);
        // Keep clear of every other stretch of track.
        if (projector.project(p.x, p.z).distance < setback - 2) continue;
        posts.add(p);
        break;
      }
    }
    return posts;
  }
}

double _wrapPi(double a) => (a + math.pi) % (2 * math.pi) - math.pi;
