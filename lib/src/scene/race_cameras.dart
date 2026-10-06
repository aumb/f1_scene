import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../geometry/environment_mesh.dart';
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

/// From the car itself: a camera on the airbox looking down the track, as
/// the broadcast T-cam does. Dragging looks around.
class OnboardCameraController extends CameraController {
  OnboardCameraController() : super(smoothing: 0.1);

  /// The pose to ride with, read every frame.
  CarPose? Function()? target;

  /// Extra yaw from dragging, relative to straight ahead.
  double lookYaw = 0;

  double _yaw = 0;
  double _pitch = 0;
  bool _initialized = false;

  /// Takes up the car's heading on the next frame instead of easing over.
  void reset() => _initialized = false;

  @override
  void update(double deltaSeconds) {
    final pose = target?.call();
    if (pose == null) return;
    final dt = clampDeltaSeconds(deltaSeconds);
    // The camera is fixed to the car, but where it looks eases a touch, so
    // the view turns with the car rather than twitching with it.
    if (_initialized) {
      _yaw += _wrapPi(pose.heading - _yaw) * settleResponse(0.08, dt);
      _pitch += (pose.pitch - _pitch) * settleResponse(0.2, dt);
    } else {
      _yaw = pose.heading;
      _pitch = pose.pitch;
      _initialized = true;
    }
    // On top of the airbox, behind the driver's head.
    final h = pose.heading;
    final eye =
        pose.position + Vector3(math.sin(h) * -0.15, 1.05, math.cos(h) * -0.15);
    final yaw = _yaw + lookYaw;
    final ahead = Vector3(
      math.sin(yaw) * math.cos(_pitch),
      math.sin(_pitch),
      math.cos(yaw) * math.cos(_pitch),
    );
    // Looking a little down, so the nose sits low in the frame.
    node.lookAtFrom(eye, eye + ahead * 30 + Vector3(0, -1.6, 0));
  }

  @override
  void handleDragUpdate(Offset delta) {
    lookYaw = (lookYaw - delta.dx * math.pi / viewportSize.width).clamp(
      -math.pi,
      math.pi,
    );
  }
}

/// A trackside camera position and which stretches of track it sees.
class TvPost {
  TvPost(this.position, this.station, [this._visible]);

  final Vector3 position;

  /// The station whose approach this post films.
  final int station;

  /// Track buckets ([TvCameraController.bucketStations] stations each) with
  /// a clear view from here; null when nothing can block it.
  final Set<int>? _visible;

  /// Whether a car at [along] stations is in clear view.
  bool sees(double along) =>
      _visible?.contains(along ~/ TvCameraController.bucketStations) ?? true;
}

/// Broadcast-style camera: fixed posts around the circuit, cutting to the
/// one the car is approaching and zooming to keep it framed.
class TvCameraController extends CameraController {
  TvCameraController({
    required this.posts,
    required this.track,
    required this.projection,
  }) : super(smoothing: 0.15);

  /// Trackside camera posts, from [TvCameraController.placePosts]. Replace
  /// them when the scenery arrives or goes, so none sits inside it or
  /// films a wall.
  List<TvPost> posts;

  /// The circuit, to tell which stretch the car is on.
  final TrackProjector track;

  /// The lens to zoom; restore its field of view when leaving this mode.
  final PerspectiveProjection projection;

  /// The pose to film, read every frame.
  CarPose? Function()? target;

  /// Width of the shot around the car, in meters.
  static const double _frameWidth = 26;

  /// Stations per visibility bucket.
  static const int bucketStations = 4;

  int? _active;
  int? _hint;
  final _look = Vector3.zero();

  /// Picks a fresh post on the next frame.
  void reset() => _active = null;

  @override
  void update(double deltaSeconds) {
    final pose = target?.call();
    if (pose == null || posts.isEmpty) return;
    final dt = clampDeltaSeconds(deltaSeconds);
    final onTrack = track.project(
      pose.position.x,
      pose.position.z,
      hint: _hint,
    );
    _hint = onTrack.station;
    final along = onTrack.along;

    // Prefer the post the car is heading toward among those with a clear
    // view of it, and only cut when another is clearly better or this one
    // loses sight, so shots hold rather than flicker between posts.
    final ahead =
        pose.position +
        Vector3(math.sin(pose.heading), 0, math.cos(pose.heading)) * 70;
    double distance(int i) => posts[i].position.distanceTo(ahead);
    int? best;
    for (var i = 0; i < posts.length; i++) {
      if (!posts[i].sees(along)) continue;
      if (best == null || distance(i) < distance(best)) best = i;
    }
    final active = _active;
    best ??= active ?? 0;
    final cut =
        active == null ||
        (!posts[active].sees(along) && posts[best].sees(along)) ||
        distance(best) < 0.7 * distance(active) ||
        posts[active].position.distanceTo(pose.position) > 420;
    final look = pose.position + Vector3(0, 0.6, 0);
    if (cut) {
      _active = best;
      _look.setFrom(look);
    } else {
      _look.addScaled(look - _look, smoothingResponse(dt));
    }

    final eye = posts[_active!].position;
    final range = math.max(1.0, eye.distanceTo(_look));
    projection.fovRadiansY = (2 * math.atan(_frameWidth / 2 / range)).clamp(
      4 * degrees2Radians,
      40 * degrees2Radians,
    );
    node.lookAtFrom(eye, _look);
  }

  /// Camera posts every ~[spacing] meters around the circuit, preferably on
  /// the outside of the bend, beyond the edge and raised.
  ///
  /// Without [obstacles] each post stands 28 m back and 9 m up. With them,
  /// positions further back, higher or on the inside are tried until one
  /// has a clear view of the approach it films, never inside a building;
  /// a stretch with no clear view at all gets no post.
  static List<TvPost> placePosts(
    TrackStations stations,
    TrackProjector projector, {
    SceneryObstacles? obstacles,
    double spacing = 220,
  }) {
    final n = stations.length;
    final mps = projector.metersPerStation;
    final step = math.max(1, (spacing / mps).round());
    final reach = math.max(1, (50 / mps).round());
    int stationsIn(double meters) => (meters / mps).round();

    // What a post at station i is for: the approach to it and a little
    // past, where it is the camera the car heads toward.
    final filmFrom = stationsIn(180), filmTo = stationsIn(40);
    // What it may be cut to when its neighbours are blocked.
    final seeFrom = stationsIn(320), seeTo = stationsIn(160);

    Vector3 targetAt(int j) => stations.center[j % n] + Vector3(0, 1.2, 0);
    int wrap(int j) => stations.closed ? j % n : j.clamp(0, n - 1);

    final posts = <TvPost>[];
    for (var i = 0; i < n; i += step) {
      final a = stations.forward[wrap(i - reach)];
      final b = stations.forward[wrap(i + reach)];
      // Outside of a left-hander is the right, and vice versa.
      final turningLeft = a.cross(b).y > 0;

      Vector3? bestPosition;
      var bestScore = -1.0;
      search:
      for (final side in turningLeft ? [-1.0, 1.0] : [1.0, -1.0]) {
        final edge = side > 0
            ? stations.leftOffset[i]
            : stations.rightOffset[i];
        for (final (setback, height)
            in obstacles == null ? const [(28.0, 9.0)] : _candidates) {
          final ground =
              stations.center[i] + stations.left[i] * (side * (edge + setback));
          // Keep clear of every other stretch of track.
          if (projector.project(ground.x, ground.z).distance < setback - 2) {
            continue;
          }
          if (obstacles == null) {
            bestPosition = ground + Vector3(0, height, 0);
            break search;
          }
          if (obstacles.isBuilt(ground.x, ground.z, margin: 4)) continue;
          final p = Vector3(
            ground.x,
            math.max(
              ground.y + height,
              obstacles.groundAt(ground.x, ground.z) + 4,
            ),
            ground.z,
          );
          var seen = 0, total = 0;
          for (var j = i - filmFrom; j <= i + filmTo; j += bucketStations) {
            if (!stations.closed && (j < 0 || j >= n)) continue;
            total++;
            if (obstacles.canSee(p, targetAt(j))) seen++;
          }
          final score = total == 0 ? 0.0 : seen / total;
          if (score > bestScore) {
            bestScore = score;
            bestPosition = p;
          }
          if (score >= 0.9) break search;
        }
      }
      if (bestPosition == null) continue;
      if (obstacles == null) {
        posts.add(TvPost(bestPosition, i));
        continue;
      }
      if (bestScore < 0.5) continue;
      final visible = <int>{}, checked = <int>{};
      for (var j = i - seeFrom; j <= i + seeTo; j++) {
        if (!stations.closed && (j < 0 || j >= n)) continue;
        final bucket = wrap(j) ~/ bucketStations;
        if (!checked.add(bucket)) continue;
        // The middle of the bucket stands for all of it.
        final mid = bucket * bucketStations + bucketStations ~/ 2;
        if (obstacles.canSee(bestPosition, targetAt(mid))) visible.add(bucket);
      }
      posts.add(TvPost(bestPosition, i, visible));
    }
    return posts;
  }

  /// Setback beyond the edge and height above the track, in meters, in the
  /// order tried: a low post close in frames best, so go further and higher
  /// only as buildings demand (a camera on a crane or a rooftop).
  static const _candidates = [
    (28.0, 9.0),
    (20.0, 14.0),
    (40.0, 16.0),
    (60.0, 24.0),
    (90.0, 36.0),
  ];
}

double _wrapPi(double a) => (a + math.pi) % (2 * math.pi) - math.pi;
