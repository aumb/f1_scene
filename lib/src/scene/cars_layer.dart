import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../geometry/track_mesh.dart';
import '../race/race_models.dart';
import '../race/race_replay.dart';

/// One node per car, posed from a [RaceReplay] every frame.
///
/// Cars are plain team-coloured blocks for now. Real size (5.6 m) is a few
/// pixels from a whole-circuit view, so they grow with camera distance.
class CarsLayer {
  CarsLayer(List<RaceDriver> drivers) {
    for (final driver in drivers) {
      final material = PhysicallyBasedMaterial()
        ..baseColorFactor = linearColor(driver.teamColour)
        ..metallicFactor = 0.2
        ..roughnessFactor = 0.4;
      final node = Node(
        name: 'car ${driver.acronym}',
        mesh: Mesh(_geometry, material),
      )..visible = false;
      _cars[driver.number] = node;
      root.add(node);
    }
  }

  static final _size = vm.Vector3(2.0, 1.0, 5.6);
  static final _geometry = CuboidGeometry(_size);

  final root = Node(name: 'cars');
  final _cars = <int, Node>{};

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
          // The cuboid is centered on its origin; lift it onto the surface.
          pose.position + vm.Vector3(0, _size.y / 2 * scale, 0),
          vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), pose.heading),
          vm.Vector3.all(scale),
        );
    }
  }
}
