import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../geometry/track_projector.dart';
import '../race/car_motion.dart';
import 'map_camera.dart';
import 'race_cameras.dart';

enum CameraMode {
  /// Free orbit around the whole circuit.
  orbit,

  /// Behind the followed car.
  chase,

  /// Riding on the followed car.
  onboard,

  /// Trackside broadcast cameras on the followed car.
  tv,
}

/// What the gesture layer can ask of the cameras.
abstract interface class CameraInput {
  set viewportSize(Size size);

  /// A rotate drag of [delta] logical pixels.
  void orbitDrag(Offset delta);

  /// Rotation about the vertical axis, radians (trackpad two-finger twist).
  void rotate(double radians);

  /// A pan from [from] to [to] (logical pixels): drag the view along.
  void panDrag(Offset from, Offset to);

  /// Zoom by [factor] (above 1 is closer) around [focal].
  void zoomAt(double factor, Offset focal);
}

/// The scene's camera and the controllers that can drive it: the free
/// orbit camera, and the chase, onboard and TV cameras that film the
/// followed car. Gestures go to whichever is active.
class CameraRig implements CameraInput {
  /// Adds the camera to [scene].
  CameraRig(Scene scene) {
    scene.add(
      _node
        ..addComponent(_component)
        ..addComponent(orbit),
    );
  }

  static const double _fovY = 35 * vm.degrees2Radians;

  /// Onboard gets the wide lens a car-mounted camera has.
  static const double _onboardFovY = 62 * vm.degrees2Radians;

  static const double _defaultAzimuth = 0.5, _defaultPolar = 0.8;

  final _node = Node(name: 'camera');
  final _projection = PerspectiveProjection(
    fovRadiansY: _fovY,
    near: 1,
    far: 40000,
  );
  late final _component = CameraComponent(
    projection: _projection,
    activateOnMount: true,
  );

  /// Free camera around the circuit.
  late final orbit = MapCameraController(
    azimuth: _defaultAzimuth,
    polar: _defaultPolar,
  )..camera = () => _component.toCamera();

  /// Camera behind the followed car.
  late final chase = ChaseCameraController()..target = _followedPose;

  /// Camera riding on the followed car.
  late final onboard = OnboardCameraController()..target = _followedPose;

  /// Trackside cameras around the current circuit; see [setTrack].
  TvCameraController? _tv;

  CameraMode _mode = CameraMode.orbit;
  int? _followed;

  /// What the orbit camera frames; see [setTrack].
  vm.Aabb3? _bounds;

  /// Whether the orbit camera still shows the framing it was given, so a
  /// change of viewport (the window, the layout settling) re-frames it.
  /// Moving the camera by hand ends that.
  bool _framed = false;

  /// Every car's pose this frame, for the cameras that film one.
  Map<int, CarPose> poses = const {};

  CarPose? _followedPose() => poses[_followed];

  CameraMode get mode => _mode;
  set mode(CameraMode mode) {
    if (mode == _mode) return;
    _node.removeComponent(_active);
    _mode = mode;
    _projection.fovRadiansY = mode == CameraMode.onboard ? _onboardFovY : _fovY;
    _resetCarCameras();
    _node.addComponent(_active);
  }

  /// The controller driving the camera now.
  CameraController get _active => switch (_mode) {
    CameraMode.orbit => orbit,
    CameraMode.chase => chase,
    CameraMode.onboard => onboard,
    CameraMode.tv => _tv ?? orbit,
  };

  /// The driver the chase, onboard and TV cameras film.
  int? get followedDriver => _followed;
  set followedDriver(int? driver) {
    _followed = driver;
    _resetCarCameras();
  }

  /// Cuts the car cameras straight to the followed car on the next frame.
  void _resetCarCameras() {
    chase.reset();
    onboard.reset();
    _tv?.reset();
  }

  /// How much to enlarge the cars: from the orbit camera they grow with
  /// distance, so they stay readable; the other cameras are close enough
  /// for real size.
  double get carScale =>
      _mode == CameraMode.orbit ? (orbit.distance / 300).clamp(1.0, 10.0) : 1.0;

  /// Points the cameras at a new circuit: [bounds] to frame, [track] for
  /// the TV cameras to follow cars along, and their [posts].
  void setTrack({
    required vm.Aabb3 bounds,
    required TrackProjector track,
    required List<TvPost> posts,
  }) {
    final tv = TvCameraController(
      posts: posts,
      track: track,
      projection: _projection,
    )..target = _followedPose;
    if (_mode == CameraMode.tv) {
      _node
        ..removeComponent(_active)
        ..addComponent(tv);
    }
    _tv = tv;
    _bounds = bounds;
    frame();
  }

  /// Moves the TV cameras to [posts], when the scenery arrives or goes.
  set tvPosts(List<TvPost> posts) => _tv?.posts = posts;

  /// Points the orbit camera at the whole circuit, fitting its bounding
  /// sphere inside the narrower of the two fields of view.
  void frame() {
    final bounds = _bounds;
    if (bounds == null) return;
    _framed = true;
    final radius = (bounds.max - bounds.min).length / 2;
    final viewport = orbit.viewportSize;
    final aspect = viewport.height > 0 ? viewport.width / viewport.height : 1.0;
    final halfFovY = _fovY / 2;
    final halfFovX = math.atan(math.tan(halfFovY) * aspect);
    final distance = radius / math.sin(math.min(halfFovX, halfFovY));
    orbit.frame(bounds.center, distance * 1.05);
  }

  /// Back to the active camera's default view. TV cameras have none, so
  /// they hand back to the orbit camera's.
  void resetView() {
    switch (_mode) {
      case CameraMode.orbit || CameraMode.tv:
        mode = CameraMode.orbit;
        frame();
        orbit.setAngles(azimuth: _defaultAzimuth, polar: _defaultPolar);
      case CameraMode.chase:
        chase.resetView();
      case CameraMode.onboard:
        onboard.resetView();
    }
  }

  // Gestures, routed to the active camera. TV cameras take none; the chase
  // and onboard cameras have no pan, so a pan turns them as a drag does.

  @override
  set viewportSize(Size size) {
    final changed = size != orbit.viewportSize;
    orbit.viewportSize = size;
    chase.viewportSize = size;
    onboard.viewportSize = size;
    if (changed && _framed) frame();
  }

  @override
  void orbitDrag(Offset delta) {
    _handMoved();
    _active.handleDragUpdate(delta);
  }

  @override
  void rotate(double radians) {
    _handMoved();
    switch (_mode) {
      case CameraMode.orbit:
        orbit.orbitBy(radians, 0);
      case CameraMode.chase:
        chase.yawOffset += radians;
      case CameraMode.onboard:
        onboard.lookBy(radians);
      case CameraMode.tv:
        break;
    }
  }

  @override
  void panDrag(Offset from, Offset to) {
    _handMoved();
    switch (_mode) {
      case CameraMode.orbit:
        orbit.dragGround(from, to);
      case CameraMode.chase || CameraMode.onboard:
        _active.handleDragUpdate(to - from);
      case CameraMode.tv:
        break;
    }
  }

  @override
  void zoomAt(double factor, Offset focal) {
    _handMoved();
    switch (_mode) {
      case CameraMode.orbit:
        orbit.zoomAt(factor, focal);
      case CameraMode.chase:
        chase.zoomBy(factor);
      case CameraMode.onboard || CameraMode.tv:
        break;
    }
  }

  void _handMoved() {
    if (_mode == CameraMode.orbit) _framed = false;
  }
}
