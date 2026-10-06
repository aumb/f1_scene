import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../geometry/car_mesh.dart';
import '../geometry/track_mesh.dart';
import '../race/car_motion.dart';
import '../race/race_models.dart';

/// One car model per driver, posed from replay poses every frame.
///
/// Every car shares the same geometry; only the body material differs, in
/// the team colour. Real size is a few pixels from a whole-circuit view, so
/// the orbit camera asks for cars scaled up with distance.
class CarsLayer {
  CarsLayer(List<RaceDriver> drivers) {
    final shared = _SharedCar.instance;
    for (final driver in drivers) {
      final body = PhysicallyBasedMaterial()
        ..baseColorFactor = linearColor(driver.teamColour)
        ..metallicFactor = 0.25
        ..roughnessFactor = 0.35;
      final node = Node(
        name: 'car ${driver.acronym}',
        mesh: Mesh.primitives(
          primitives: [
            MeshPrimitive(shared.body, body),
            MeshPrimitive(shared.carbon, shared.carbonMaterial),
            MeshPrimitive(shared.tyres, shared.tyreMaterial),
            MeshPrimitive(shared.accent, shared.accentMaterial),
          ],
        ),
      )..visible = false;
      _cars[driver.number] = node;
      root.add(node);
    }
  }

  final root = Node(name: 'cars');
  final _cars = <int, Node>{};

  /// The scene node of [driver]'s car, for cameras to follow.
  Node? nodeOf(int driver) => _cars[driver];

  /// Outlines [driver]'s car, or none.
  set highlighted(int? driver) {
    for (final MapEntry(key: number, value: node) in _cars.entries) {
      node.highlightColor = number == driver ? _highlight : null;
    }
  }

  static final _highlight = vm.Vector4(1, 1, 1, 1);

  /// Places every car in [poses] and hides the rest. [scale] enlarges the
  /// cars uniformly about their contact point.
  void update(Map<int, CarPose> poses, {double scale = 1}) {
    for (final MapEntry(key: number, value: node) in _cars.entries) {
      final pose = poses[number];
      if (pose == null) {
        node.visible = false;
        continue;
      }
      node
        ..visible = true
        ..localTransform = vm.Matrix4.compose(
          pose.position,
          pose.rotation,
          vm.Vector3.all(scale),
        );
    }
  }
}

/// GPU geometry and the non-team materials, built once and shared by every
/// car in every race.
class _SharedCar {
  _SharedCar._() {
    final meshes = CarMeshes.build();
    MeshGeometry upload(MeshArrays arrays) => MeshGeometry.fromArrays(
      positions: arrays.positions,
      normals: arrays.normals,
      indices: arrays.indices,
    );
    body = upload(meshes.body);
    carbon = upload(meshes.carbon);
    tyres = upload(meshes.tyres);
    accent = upload(meshes.accent);
  }

  static final instance = _SharedCar._();

  late final MeshGeometry body;
  late final MeshGeometry carbon;
  late final MeshGeometry tyres;
  late final MeshGeometry accent;

  final carbonMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = linearColor(0x17191E)
    ..metallicFactor = 0.1
    ..roughnessFactor = 0.5;
  final tyreMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = linearColor(0x101012)
    ..metallicFactor = 0
    ..roughnessFactor = 0.9;
  final accentMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = linearColor(0xE8E8E8)
    ..metallicFactor = 0
    ..roughnessFactor = 0.4;
}
