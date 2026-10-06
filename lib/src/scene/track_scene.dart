import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../data/circuit.dart';
import '../geometry/track_mesh.dart';
import '../race/race_replay.dart';
import 'cars_layer.dart';

/// Owns the flutter_scene [Scene] for a circuit diorama: a dark base slab,
/// the extruded track ribbon, a start/finish line, lights, an orbit camera
/// and, during a replay, the cars.
///
/// Plain Dart, no widgets; `TrackScreen` displays it.
class TrackScene {
  final Scene scene = Scene();

  /// Drives the camera; wire input with a `CameraControls` widget.
  late final OrbitCameraController orbit;
  late final Node _camera;

  Circuit? _circuit;
  TrackMeshBuilder? _builder;
  Node? _diorama;
  MeshGeometry? _surface;
  RaceReplay? _replay;
  CarsLayer? _cars;

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
  final _slabMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = linearColor(0x1A1D23)
    ..metallicFactor = 0
    ..roughnessFactor = 0.95;
  final _lineMaterial = PhysicallyBasedMaterial()
    ..metallicFactor = 0
    ..roughnessFactor = 0.6
    // Lies on the track surface; win the depth tie at any distance.
    ..depthLayer = 1;

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

    orbit = OrbitCameraController(
      distance: 2500,
      azimuth: _defaultAzimuth,
      polar: _defaultPolar,
      minDistance: 25,
      maxDistance: 9000,
      minPolar: 0.08,
      smoothing: 0.12,
    );
    _camera = Node(name: 'camera');
    scene.add(
      _camera
        ..addComponent(
          CameraComponent(
            projection: PerspectiveProjection(
              fovRadiansY: _fovY,
              near: 1,
              far: 40000,
            ),
            activateOnMount: true,
          ),
        )
        ..addComponent(orbit),
    );
  }

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
    final trackMesh = Mesh.primitives(
      primitives: [
        MeshPrimitive(surface, _surfaceMaterial),
        MeshPrimitive(_geometry(builder.skirts(baseY)), _skirtMaterial),
      ],
    );
    final root = Node(name: 'diorama ${circuit.summary.id}')
      ..add(_slab(circuit, baseY))
      ..add(Node(name: 'track', mesh: trackMesh))
      ..add(
        Node(
          name: 'start-finish',
          mesh: Mesh(_geometry(builder.startFinishLine()), _lineMaterial),
        ),
      );
    scene.add(root);

    _circuit = circuit;
    _builder = builder;
    _diorama = root;
    _surface = surface;
    frameCircuit();
  }

  /// Shows the cars of [replay] on the current circuit, or none. The caller
  /// keeps ownership of the replay.
  void showRace(RaceReplay? replay) {
    final cars = _cars;
    if (cars != null) scene.remove(cars.root);
    _replay = replay;
    _cars = replay == null ? null : CarsLayer(replay.drivers);
    if (_cars case final cars?) scene.add(cars.root);
  }

  /// Per-frame update: advances the replay and poses the cars.
  void tick(double deltaSeconds) {
    final replay = _replay, cars = _cars;
    if (replay == null || cars == null) return;
    replay.tick(deltaSeconds);
    // Grow cars with distance so they stay readable from far away.
    cars.update(replay.poses(), scale: (orbit.distance / 300).clamp(1.0, 10.0));
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
    // OrbitCameraController.frame places the eye at radius * 2 * margin.
    orbit.frame(bounds, margin: distance * 1.05 / (radius * 2));
  }

  /// Frames the circuit and eases back to the default viewing angle.
  void resetView() {
    frameCircuit();
    // OrbitCameraController exposes no angle getters, so recover them from
    // the eye offset: (-sin(az) * h, sin(polar) * d, -cos(az) * h).
    final offset = _camera.globalTransform.getTranslation() - orbit.target;
    if (offset.length2 == 0) return;
    final azimuth = math.atan2(-offset.x, -offset.z);
    final polar = math.asin((offset.y / offset.length).clamp(-1.0, 1.0));
    // Turn the short way round.
    final turn =
        (_defaultAzimuth - azimuth + math.pi) % (2 * math.pi) - math.pi;
    orbit.orbitBy(turn, _defaultPolar - polar);
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
