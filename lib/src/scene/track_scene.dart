import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../data/circuit.dart';
import '../data/circuit_environment.dart';
import '../geometry/environment_mesh.dart';
import '../geometry/track_mesh.dart';
import '../geometry/track_projector.dart';
import '../race/car_motion.dart';
import '../race/race_replay.dart';
import 'cars_layer.dart';
import 'map_camera.dart';
import 'race_cameras.dart';

enum CameraMode {
  /// Free orbit around the whole circuit.
  orbit,

  /// Behind the followed car.
  chase,

  /// Trackside broadcast cameras on the followed car.
  tv,
}

/// Owns the flutter_scene [Scene] for a circuit diorama: a dark base slab,
/// the extruded track ribbon, a start/finish line, lights, the cameras and,
/// during a replay, the cars and pit lane.
///
/// Plain Dart, no widgets; `TrackScreen` displays it.
class TrackScene implements CameraInput {
  final Scene scene = Scene();

  /// Free camera around the circuit.
  late final MapCameraController orbit;

  /// Camera behind the followed car.
  late final ChaseCameraController chase;

  late final Node _camera;
  late final PerspectiveProjection _projection;
  TvCameraController? _tv;

  /// TV posts around the plain slab, and around the scenery once loaded.
  List<TvPost> _slabPosts = const [];
  List<TvPost>? _sceneryPosts;
  CameraMode _cameraMode = CameraMode.orbit;
  int? _followed;
  Map<int, CarPose> _poses = const {};

  Circuit? _circuit;
  TrackMeshBuilder? _builder;
  Node? _diorama;
  MeshGeometry? _surface;
  MeshGeometry? _skirts;
  Node? _slabNode;
  Node? _environmentNode;
  bool _sceneryVisible = true;
  RaceReplay? _replay;
  CarsLayer? _cars;
  Node? _raceRoot;
  Node? _drsNode;
  double _baseY = 0;

  /// World meters between the lowest point of the track and the slab.
  static const double _plinth = 1.5;

  /// Margin of slab around the track, in meters.
  static const double _slabMargin = 160;
  static const double _slabThickness = 40;

  static const double _fovY = 35 * vm.degrees2Radians;
  static const double _defaultAzimuth = 0.5;
  static const double _defaultPolar = 0.8;

  final _surfaceMaterial = PhysicallyBasedMaterial()
    ..metallicFactor = 0
    ..roughnessFactor = 0.5;
  final _skirtMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = linearColor(0x2C3038)
    ..metallicFactor = 0
    ..roughnessFactor = 0.8;
  final _terrainMaterial = PhysicallyBasedMaterial()
    ..metallicFactor = 0
    ..roughnessFactor = 0.95;
  final _buildingMaterial = PhysicallyBasedMaterial()
    ..metallicFactor = 0
    ..roughnessFactor = 0.8;
  final _roadMaterial = PhysicallyBasedMaterial()
    ..metallicFactor = 0
    ..roughnessFactor = 0.85
    // Draped just above the ground; win any tie with it.
    ..depthLayer = 1;
  final _waterMaterial = PhysicallyBasedMaterial()
    ..metallicFactor = 0
    ..roughnessFactor = 0.15
    ..depthLayer = 1;
  final _slabMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = linearColor(0x1A1D23)
    ..metallicFactor = 0
    ..roughnessFactor = 0.95;
  // Markings lie flush on the track surface and win the depth tie by
  // layer: kerbs over the surface, DRS bands over kerbs, lines over all.
  final _kerbMaterial = _overlay(depthLayer: 1);
  final _drsMaterial = _overlay(depthLayer: 2);
  final _lineMaterial = _overlay(depthLayer: 3);

  static PhysicallyBasedMaterial _overlay({required int depthLayer}) =>
      PhysicallyBasedMaterial()
        ..metallicFactor = 0
        ..roughnessFactor = 0.6
        ..depthLayer = depthLayer;
  final _pitMaterial = PhysicallyBasedMaterial()
    ..metallicFactor = 0
    ..roughnessFactor = 0.7
    // Where the pit lane merges into the track, the track wins.
    ..depthLayer = -1;

  Future<void> initialize() async {
    await Scene.initializeStaticResources();

    // Stylized-diorama look: filmic, slightly saturated, grounded by AO,
    // with a vignette to frame the slab against the dark background.
    scene.environmentSettings = EnvironmentSettings(
      toneMapping: ToneMappingMode.aces,
      environmentIntensity: 0.6,
      exposure: 0.85,
      colorGradingEnabled: true,
      saturation: 1.15,
      contrast: 1.05,
      bloomEnabled: true,
      bloomThreshold: 1.0,
      bloomIntensity: 0.12,
      ambientOcclusionEnabled: true,
      ambientOcclusionMethod: AmbientOcclusionMethod.groundTruth,
      ambientOcclusionHalfResolution: true,
      vignetteEnabled: true,
      vignetteIntensity: 0.3,
    );
    scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(-0.45, -1.0, -0.35),
      intensity: 3.2,
      castsShadow: true,
      // The camera sits kilometres away; shadows must reach the whole slab.
      shadowMaxDistance: 9000,
      shadowMapResolution: 2048,
      // At this scale a shadow texel spans meters, so the default
      // centimeter biases leave the slab shadowing itself in rings (acne).
      shadowDepthBias: 1.0,
      shadowNormalBias: 2.0,
    );

    orbit = MapCameraController(azimuth: _defaultAzimuth, polar: _defaultPolar)
      ..camera = () => _cameraComponent.toCamera();
    chase = ChaseCameraController()..target = _followedPose;
    _projection = PerspectiveProjection(
      fovRadiansY: _fovY,
      near: 1,
      far: 40000,
    );
    _cameraComponent = CameraComponent(
      projection: _projection,
      activateOnMount: true,
    );
    _camera = Node(name: 'camera');
    scene.add(
      _camera
        ..addComponent(_cameraComponent)
        ..addComponent(orbit),
    );
  }

  late final CameraComponent _cameraComponent;

  // Camera input, routed to whichever camera is active. TV cameras take
  // none; the chase camera has no pan, so a pan swings it round the car.

  @override
  set viewportSize(Size size) {
    orbit.viewportSize = size;
    chase.viewportSize = size;
  }

  @override
  void orbitDrag(Offset delta) {
    switch (_cameraMode) {
      case CameraMode.orbit:
        final k = math.pi / math.max(1.0, orbit.viewportSize.height);
        // Drag down to look from higher up, as in map apps.
        orbit.orbitBy(-delta.dx * k, delta.dy * k);
      case CameraMode.chase:
        chase.handleDragUpdate(delta);
      case CameraMode.tv:
        break;
    }
  }

  @override
  void rotate(double radians) {
    switch (_cameraMode) {
      case CameraMode.orbit:
        orbit.orbitBy(radians, 0);
      case CameraMode.chase:
        chase.yawOffset += radians;
      case CameraMode.tv:
        break;
    }
  }

  @override
  void panDrag(Offset from, Offset to) {
    switch (_cameraMode) {
      case CameraMode.orbit:
        orbit.dragGround(from, to);
      case CameraMode.chase:
        chase.handleDragUpdate(to - from);
      case CameraMode.tv:
        break;
    }
  }

  @override
  void zoomAt(double factor, Offset focal) {
    switch (_cameraMode) {
      case CameraMode.orbit:
        orbit.zoomAt(factor, focal);
      case CameraMode.chase:
        chase.distance = (chase.distance / factor).clamp(6.0, 200.0);
      case CameraMode.tv:
        break;
    }
  }

  CameraMode get cameraMode => _cameraMode;

  /// Switches the camera. Chase and TV film [followedDriver].
  set cameraMode(CameraMode mode) {
    if (mode == _cameraMode) return;
    _camera.removeComponent(activeController);
    _cameraMode = mode;
    _projection.fovRadiansY = _fovY;
    chase.reset();
    _tv?.reset();
    _camera.addComponent(activeController);
  }

  /// The controller driving the camera now, for `CameraControls`.
  CameraController get activeController => switch (_cameraMode) {
    CameraMode.orbit => orbit,
    CameraMode.chase => chase,
    CameraMode.tv => _tv ?? orbit,
  };

  /// The driver the chase and TV cameras film, outlined in orbit view.
  int? get followedDriver => _followed;
  set followedDriver(int? driver) {
    _followed = driver;
    chase.reset();
    _tv?.reset();
  }

  CarPose? _followedPose() => _poses[_followed];

  Circuit? get circuit => _circuit;

  /// The cross-sections the current track was built from.
  TrackStations? get stations => _builder?.stations;

  /// Replaces the diorama with [circuit] and frames it. Any race shown on
  /// the previous circuit is removed.
  void showCircuit(Circuit circuit, TrackColorMode mode) {
    showRace(null);
    final diorama = _diorama;
    if (diorama != null) scene.remove(diorama);

    final stations = TrackStations.sample(circuit);
    final builder = TrackMeshBuilder(circuit, stations);
    final baseY = circuit.elevationRange.$1 - _plinth;

    // Updatable, so a tint change rewrites the color stream in place.
    final surface = _geometry(
      builder.surface(mode),
      storage: GeometryStorage.updatable,
    );
    // Updatable, so the skirts can reach down into terrain that arrives
    // later.
    final skirts = _geometry(
      builder.skirts(baseY),
      storage: GeometryStorage.updatable,
    );
    final trackMesh = Mesh.primitives(
      primitives: [
        MeshPrimitive(surface, _surfaceMaterial),
        MeshPrimitive(skirts, _skirtMaterial),
      ],
    );
    final root = Node(name: 'diorama ${circuit.summary.id}')
      ..add(_slabNode = _slab(circuit, baseY))
      ..add(Node(name: 'track', mesh: trackMesh))
      ..add(
        Node(
          name: 'kerbs',
          mesh: Mesh(_geometry(builder.kerbs()), _kerbMaterial),
        )..shadowCastingMode = ShadowCastingMode.off,
      )
      ..add(
        Node(
          name: 'start-finish',
          mesh: Mesh(_geometry(builder.startFinishLine()), _lineMaterial),
        )..shadowCastingMode = ShadowCastingMode.off,
      );
    if (circuit.sectors.length > 1) {
      root.add(
        Node(
          name: 'sector lines',
          mesh: Mesh(_geometry(builder.sectorLines()), _lineMaterial),
        )..shadowCastingMode = ShadowCastingMode.off,
      );
    }
    _markStatic(root);
    scene.add(root);

    _circuit = circuit;
    _builder = builder;
    _diorama = root;
    _surface = surface;
    _skirts = skirts;
    _environmentNode = null;
    _baseY = baseY;

    final projector = TrackProjector(stations);
    _slabPosts = TvCameraController.placePosts(stations, projector);
    _sceneryPosts = null;
    final tv = TvCameraController(
      posts: _slabPosts,
      track: projector,
      projection: _projection,
    )..target = _followedPose;
    if (_cameraMode == CameraMode.tv) {
      _camera
        ..removeComponent(activeController)
        ..addComponent(tv);
    }
    _tv = tv;
    frameCircuit();
  }

  /// Whether the terrain, buildings and roads around the circuit show (when
  /// loaded); otherwise the plain slab does.
  bool get sceneryVisible => _sceneryVisible;
  set sceneryVisible(bool visible) {
    _sceneryVisible = visible;
    final environment = _environmentNode;
    environment?.visible = visible;
    _slabNode?.visible = environment == null || !visible;
    final posts = visible ? _sceneryPosts ?? _slabPosts : _slabPosts;
    final tv = _tv;
    if (tv != null && !identical(tv.posts, posts)) {
      tv
        ..posts = posts
        ..reset();
    }
  }

  /// Surrounds the current circuit with [environment] in place of the slab.
  void showEnvironment(CircuitEnvironment environment) {
    final root = _diorama, builder = _builder, skirts = _skirts;
    if (root == null || builder == null || skirts == null) return;
    final previous = _environmentNode;
    if (previous != null) root.remove(previous);

    final meshes = EnvironmentMeshBuilder(
      environment,
      TrackProjector(builder.stations),
    );
    final baseY = math.min(meshes.lowestGround, _baseY) - 25;
    final node = Node(name: 'environment')
      ..add(
        Node(
          name: 'terrain',
          mesh: Mesh(_geometry(meshes.terrainBlock(baseY)), _terrainMaterial),
        ),
      )
      ..add(
        Node(
          name: 'buildings',
          mesh: Mesh(_geometry(meshes.buildings()), _buildingMaterial),
        ),
      )
      ..add(
        Node(
          name: 'roads',
          mesh: Mesh(_geometry(meshes.roads()), _roadMaterial),
        )..shadowCastingMode = ShadowCastingMode.off,
      )
      ..add(
        Node(
          name: 'water',
          mesh: Mesh(_geometry(meshes.water()), _waterMaterial),
        )..shadowCastingMode = ShadowCastingMode.off,
      );
    final trees = meshes.trees();
    if (trees.isNotEmpty) node.add(_trees(trees));
    _markStatic(node);
    root.add(node);
    _environmentNode = node;

    // TV posts that stand clear of the buildings and see past them.
    _sceneryPosts = TvCameraController.placePosts(
      builder.stations,
      TrackProjector(builder.stations),
      obstacles: meshes.obstacles,
    );

    // Reach the skirts down into the block, so no gap opens under the
    // ribbon where the ground falls away.
    _baseY = baseY;
    skirts.updatePositions(builder.skirts(baseY).positions);
    sceneryVisible = _sceneryVisible;
  }

  /// Flags every node under [node] as a static shadow caster, so the
  /// engine caches its shadow map instead of redrawing it each frame. Only
  /// for content that never moves.
  static void _markStatic(Node node) {
    node.shadowStatic = true;
    for (final child in node.children) {
      _markStatic(child);
    }
  }

  Node _trees(List<vm.Vector3> positions) {
    final random = math.Random(3);
    final mesh = InstancedMesh(
      geometry: CylinderGeometry(
        bottomRadius: 2.4,
        topRadius: 0,
        height: 8,
        radialSegments: 7,
      ),
      material: PhysicallyBasedMaterial()
        ..baseColorFactor = linearColor(0x35593C)
        ..metallicFactor = 0
        ..roughnessFactor = 0.9,
      cullInstances: true,
    );
    for (final p in positions) {
      // 10-16 m: forest trees, tall enough to read from the orbit view.
      final scale = 1.2 + random.nextDouble() * 0.8;
      mesh.addInstance(
        vm.Matrix4.compose(
          // The cone is centered on its origin; stand it on the ground.
          p + vm.Vector3(0, 4 * scale, 0),
          vm.Quaternion.identity(),
          vm.Vector3.all(scale),
        ),
        color: vm.Vector4.all(0.8 + random.nextDouble() * 0.4)..w = 1,
      );
    }
    return Node(name: 'trees')..addComponent(InstancedMeshComponent(mesh));
  }

  /// Shows the cars and pit lane of [replay] on the current circuit, or
  /// none. The caller keeps ownership of the replay.
  void showRace(RaceReplay? replay) {
    final previous = _raceRoot;
    if (previous != null) scene.remove(previous);
    _replay?.drsZones.removeListener(_showDrsZones);
    _drsNode = null;
    _replay = replay;
    _poses = const {};
    _cars = null;
    _raceRoot = null;
    if (replay == null) return;

    final cars = CarsLayer(replay.drivers);
    final root = Node(name: 'race')..add(cars.root);
    final pitLane = replay.pitLane;
    if (pitLane != null) {
      root.add(
        Node(
          name: 'pit lane',
          mesh: Mesh.primitives(
            primitives: [
              MeshPrimitive(
                _geometry(
                  ribbonSurface(
                    pitLane,
                    uniformRibbonColors(pitLane, linearColor(0x3A3E46)),
                  ),
                ),
                _pitMaterial,
              ),
              MeshPrimitive(
                _geometry(ribbonSkirts(pitLane, _baseY)),
                _skirtMaterial,
              ),
            ],
          ),
        )..shadowStatic = true,
      );
    }
    scene.add(root);
    _cars = cars;
    _raceRoot = root;
    replay.drsZones.addListener(_showDrsZones);
    _showDrsZones();
    if (!replay.drivers.any((d) => d.number == _followed)) {
      followedDriver = replay.featuredDriver;
    }
  }

  /// (Re)draws the current replay's DRS zones, which arrive after it loads.
  void _showDrsZones() {
    final replay = _replay, root = _raceRoot, builder = _builder;
    if (replay == null || root == null || builder == null) return;
    final previous = _drsNode;
    if (previous != null) root.remove(previous);
    final zones = replay.drsZones.value;
    if (zones.isEmpty) return;
    final node = Node(
      name: 'drs zones',
      mesh: Mesh(
        _geometry(builder.drsBands([for (final z in zones) (z.start, z.end)])),
        _drsMaterial,
      ),
    )..shadowCastingMode = ShadowCastingMode.off;
    root.add(node);
    _drsNode = node;
  }

  /// Per-frame update: advances the replay and poses the cars. Runs before
  /// the camera controllers update, so they see this frame's poses.
  void tick(double deltaSeconds) {
    final replay = _replay, cars = _cars;
    if (replay == null || cars == null) return;
    replay.tick(deltaSeconds);
    _poses = replay.currentPoses;
    // From the orbit camera, grow cars with distance so they stay readable;
    // the chase and TV cameras are close enough for real size.
    final scale = _cameraMode == CameraMode.orbit
        ? (orbit.distance / 300).clamp(1.0, 10.0)
        : 1.0;
    cars
      ..update(_poses, scale: scale)
      ..highlighted = _cameraMode == CameraMode.orbit ? _followed : null;
  }

  /// Re-tints the driving surface without rebuilding anything else.
  void setColorMode(TrackColorMode mode) {
    final builder = _builder, surface = _surface;
    if (builder == null || surface == null) return;
    surface.updateColors(builder.surfaceColors(mode));
  }

  /// Points the orbit camera at the whole circuit, fitting its bounding
  /// sphere inside the narrower of the two fields of view.
  void frameCircuit() {
    final circuit = _circuit;
    if (circuit == null) return;
    final bounds = circuit.bounds;
    final radius = (bounds.max - bounds.min).length / 2;
    final viewport = orbit.viewportSize;
    final aspect = viewport.height > 0 ? viewport.width / viewport.height : 1.0;
    final halfFovY = _fovY / 2;
    final halfFovX = math.atan(math.tan(halfFovY) * aspect);
    final distance = radius / math.sin(math.min(halfFovX, halfFovY));
    orbit.frame(bounds.center, distance * 1.05);
  }

  /// Frames the circuit and eases back to the default viewing angle.
  void resetView() {
    frameCircuit();
    orbit.setAngles(azimuth: _defaultAzimuth, polar: _defaultPolar);
  }

  /// The diorama base: a dark block whose top sits [_plinth] below the
  /// lowest point of the track.
  Node _slab(Circuit circuit, double topY) {
    final bounds = circuit.bounds;
    final center = bounds.center;
    final size = bounds.max - bounds.min;
    final extent = vm.Vector3(
      size.x + _slabMargin * 2,
      _slabThickness,
      size.z + _slabMargin * 2,
    );
    return Node(
      name: 'slab',
      // Cuboids are centered on their origin.
      localTransform: vm.Matrix4.translation(
        vm.Vector3(center.x, topY - _slabThickness / 2, center.z),
      ),
      mesh: Mesh(CuboidGeometry(extent), _slabMaterial),
    );
  }

  static MeshGeometry _geometry(
    MeshArrays arrays, {
    GeometryStorage storage = GeometryStorage.fixed,
  }) => MeshGeometry.fromArrays(
    positions: arrays.positions,
    normals: arrays.normals,
    colors: arrays.colors,
    indices: arrays.indices,
    storage: storage,
  );
}
