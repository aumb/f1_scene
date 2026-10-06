import 'dart:ui';

import 'package:f1_scene/src/scene/map_camera.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  // A camera 1000 m back and up from the origin, looking at it.
  final camera = PerspectiveCamera(
    position: vm.Vector3(0, 700, -700),
    target: vm.Vector3.zero(),
  );
  MapCameraController controller() => MapCameraController()
    ..camera = (() => camera)
    ..viewportSize = const Size(800, 600);

  test('dragging moves the ground with the pointer', () {
    final c = controller();
    // Drag the screen centre to the right: the ground under it follows,
    // so the target moves the other way along the ground.
    c.dragGround(const Offset(400, 300), const Offset(500, 300));
    final under = camera.screenPointToRay(
      const Offset(500, 300),
      const Size(800, 600),
    );
    final t = -under.origin.y / under.direction.y;
    final groundNowUnderPointer = under.origin + under.direction * t;
    // The point that was at the centre (the origin) is now under (500, 300):
    // the target shifted by the same distance in the opposite direction.
    final target = c.targetGoal;
    expect((target + groundNowUnderPointer).length, lessThan(1e-6));
  });

  test('zooming keeps the point under the cursor fixed', () {
    final c = controller();
    final focal = const Offset(600, 450);
    final ray = camera.screenPointToRay(focal, const Size(800, 600));
    final point =
        ray.origin + ray.direction * (-ray.origin.y / ray.direction.y);
    c.zoomAt(2, focal);
    // The target moved halfway toward the point; the distance halved.
    final expected = point + (vm.Vector3.zero() - point) / 2;
    expect(c.targetGoal.distanceTo(expected), lessThan(1e-6));
  });
}
