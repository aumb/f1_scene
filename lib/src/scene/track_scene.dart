import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../data/circuit.dart';
import '../data/circuit_environment.dart';
import '../geometry/environment_mesh.dart';
import '../geometry/mesh_arrays.dart';
import '../geometry/track_mesh.dart';
import '../geometry/track_projector.dart';
import '../race/race_replay.dart';
import 'camera_rig.dart';
import 'cars_layer.dart';
import 'diorama_materials.dart';
import 'mesh_upload.dart';
import 'race_cameras.dart';

/// Owns the flutter_scene [Scene] for a circuit diorama: the extruded track
/// with kerbs and start/finish and sector lines, a dark base slab or (once
/// fetched) the surrounding scenery, lights and post effects, the cameras
/// and, during a replay, the cars, pit lane and DRS zones.
///
/// Plain Dart, no widgets; `TrackScreen` displays it.
class TrackScene {
  final Scene scene = Scene();

  /// The camera and its controllers; set up by [initialize].
  late final CameraRig cameras;

  final _materials = DioramaMaterials();

  Circuit? _circuit;
  TrackMeshBuilder? _builder;
  TrackProjector? _projector;
  Node? _diorama;
  Node? _slabNode;
  Node? _environmentNode;
  bool _sceneryVisible = true;

  /// The track's skirts, which reach down into the scenery once it loads.
  MeshGeometry? _skirts;

  /// The bottom of the diorama: under the slab's top, then under the
  /// scenery block. [_trackBaseY] stays the former.
  double _baseY = 0, _trackBaseY = 0;

  /// TV posts around the plain slab, and around the scenery once loaded.
  List<TvPost> _slabPosts = const [];
  List<TvPost>? _sceneryPosts;

  RaceReplay? _replay;
  CarsLayer? _cars;
  Node? _raceRoot;
  MeshGeometry? _pitSkirts;
  Node? _drsNode;

  /// Meters between the lowest point of the track and the slab's top.
  static const double _plinth = 1.5;

  /// Margin of slab around the track, and its thickness, in meters.
  static const double _slabMargin = 160, _slabThickness = 40;

  /// Depth of the scenery block below its lowest ground, in meters.
  static const double _blockDepth = 25;

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
    cameras = CameraRig(scene);
  }

  Circuit? get circuit => _circuit;

  /// The cross-sections the current track was built from.
  TrackStations? get stations => _builder?.stations;

  /// Replaces the diorama with [circuit] and frames it. Any race shown on
  /// the previous circuit is removed.
  void showCircuit(Circuit circuit) {
    showRace(null);
    final previous = _diorama;
    if (previous != null) scene.remove(previous);

    final stations = TrackStations.sample(circuit);
    final builder = TrackMeshBuilder(circuit, stations);
    final projector = TrackProjector(stations);
    final baseY = circuit.lowestElevation - _plinth;

    // Updatable, so the skirts can reach down into scenery that arrives
    // later.
    final skirts = uploadMesh(
      builder.skirts(baseY),
      storage: GeometryStorage.updatable,
    );
    final track = Mesh.primitives(
      primitives: [
        MeshPrimitive(uploadMesh(builder.surface()), _materials.surface),
        MeshPrimitive(skirts, _materials.skirt),
      ],
    );
    final root = Node(name: 'diorama ${circuit.summary.id}')
      ..add(_slabNode = _slab(circuit, baseY))
      ..add(Node(name: 'track', mesh: track))
      ..add(_flat('kerbs', builder.kerbs(), _materials.kerb))
      ..add(_flat('start-finish', builder.startFinishLine(), _materials.line));
    if (circuit.sectorStarts.length > 1) {
      root.add(_flat('sector lines', builder.sectorLines(), _materials.line));
    }
    markStaticShadows(root);
    scene.add(root);

    _circuit = circuit;
    _builder = builder;
    _projector = projector;
    _diorama = root;
    _skirts = skirts;
    _environmentNode = null;
    _baseY = _trackBaseY = baseY;
    _slabPosts = TvCameraController.placePosts(stations, projector);
    _sceneryPosts = null;
    cameras.setTrack(
      bounds: circuit.bounds,
      track: projector,
      posts: _slabPosts,
    );
  }

  /// A mesh lying on the track, too thin to cast a shadow.
  static Node _flat(String name, MeshArrays arrays, Material material) =>
      Node(name: name, mesh: Mesh(uploadMesh(arrays), material))
        ..shadowCastingMode = ShadowCastingMode.off;

  /// Whether the terrain, buildings and roads around the circuit show (when
  /// loaded); otherwise the plain slab does.
  bool get sceneryVisible => _sceneryVisible;
  set sceneryVisible(bool visible) {
    _sceneryVisible = visible;
    final environment = _environmentNode;
    environment?.visible = visible;
    _slabNode?.visible = environment == null || !visible;
    cameras.tvPosts = visible ? _sceneryPosts ?? _slabPosts : _slabPosts;
  }

  /// Surrounds the current circuit with [environment] in place of the slab.
  void showEnvironment(CircuitEnvironment environment) {
    final root = _diorama, builder = _builder, projector = _projector;
    if (root == null || builder == null || projector == null) return;
    final previous = _environmentNode;
    if (previous != null) root.remove(previous);

    final meshes = EnvironmentMeshBuilder(environment, projector);
    final baseY = math.min(meshes.lowestGround, _trackBaseY) - _blockDepth;
    final node = Node(name: 'environment')
      ..add(
        Node(
          name: 'terrain',
          mesh: Mesh(
            uploadMesh(meshes.terrainBlock(baseY)),
            _materials.terrain,
          ),
        ),
      )
      ..add(
        Node(
          name: 'buildings',
          mesh: Mesh(uploadMesh(meshes.buildings()), _materials.building),
        ),
      )
      ..add(_flat('roads', meshes.roads(), _materials.road))
      ..add(_flat('water', meshes.water(), _materials.water));
    final trees = meshes.trees();
    if (trees.isNotEmpty) node.add(_trees(trees));
    markStaticShadows(node);
    root.add(node);
    _environmentNode = node;

    // TV posts that stand clear of the buildings and see past them.
    _sceneryPosts = TvCameraController.placePosts(
      builder.stations,
      projector,
      obstacles: meshes.obstacles,
    );

    // Reach the skirts down into the block, so no gap opens under the
    // track or pit lane where the ground falls away.
    _baseY = baseY;
    _skirts?.updatePositions(builder.skirts(baseY).positions);
    final pitLane = _replay?.pitLane;
    if (pitLane != null) {
      _pitSkirts?.updatePositions(ribbonSkirts(pitLane, baseY).positions);
    }
    sceneryVisible = _sceneryVisible;
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
      material: _materials.tree,
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
    _pitSkirts = null;
    _replay = replay;
    cameras.poses = const {};
    _cars = null;
    _raceRoot = null;
    if (replay == null) return;

    final cars = CarsLayer(replay.drivers, year: replay.session.year);
    final root = Node(name: 'race')..add(cars.root);
    final pitLane = replay.pitLane;
    if (pitLane != null) {
      final skirts = uploadMesh(
        ribbonSkirts(pitLane, _baseY),
        storage: GeometryStorage.updatable,
      );
      root.add(
        Node(
          name: 'pit lane',
          mesh: Mesh.primitives(
            primitives: [
              MeshPrimitive(
                uploadMesh(ribbonSurface(pitLane, linearColor(0x3A3E46))),
                _materials.pit,
              ),
              MeshPrimitive(skirts, _materials.skirt),
            ],
          ),
        )..shadowStatic = true,
      );
      _pitSkirts = skirts;
    }
    scene.add(root);
    _cars = cars;
    _raceRoot = root;
    replay.drsZones.addListener(_showDrsZones);
    _showDrsZones();
    if (!replay.drivers.any((d) => d.number == cameras.followedDriver)) {
      cameras.followedDriver = replay.featuredDriver;
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
    final bands = builder.drsBands([for (final z in zones) (z.start, z.end)]);
    root.add(_drsNode = _flat('drs zones', bands, _materials.drs));
  }

  /// Per-frame update: advances the replay and poses the cars. Runs before
  /// the camera controllers update, so they see this frame's poses.
  void tick(double deltaSeconds) {
    final replay = _replay, cars = _cars;
    if (replay == null || cars == null) return;
    replay.tick(deltaSeconds);
    final poses = replay.currentPoses;
    cameras.poses = poses;
    cars
      ..update(poses, scale: cameras.carScale)
      // Outline the followed car from afar, where it is hard to pick out.
      ..highlighted = cameras.mode == CameraMode.orbit
          ? cameras.followedDriver
          : null;
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
      mesh: Mesh(CuboidGeometry(extent), _materials.slab),
    );
  }
}
