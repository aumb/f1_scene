import 'package:f1_scene/src/scene/map_camera.dart';
import 'package:f1_scene/src/ui/scene_gestures.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Records what the gestures asked for.
class FakeInput implements CameraInput {
  final calls = <String>[];
  Offset orbited = Offset.zero;
  Offset panned = Offset.zero;
  double zoom = 1;
  double rotated = 0;

  @override
  set viewportSize(Size size) {}

  @override
  void orbitDrag(Offset delta) {
    calls.add('orbit');
    orbited += delta;
  }

  @override
  void panDrag(Offset from, Offset to) {
    calls.add('pan');
    panned += to - from;
  }

  @override
  void rotate(double radians) {
    calls.add('rotate');
    rotated += radians;
  }

  @override
  void zoomAt(double factor, Offset focal) {
    calls.add('zoom');
    zoom *= factor;
  }
}

void main() {
  late FakeInput input;

  Future<void> pump(WidgetTester tester) async {
    input = FakeInput();
    await tester.pumpWidget(
      MaterialApp(
        home: SceneGestures(input: input, child: const SizedBox.expand()),
      ),
    );
  }

  testWidgets('trackpad two-finger swipe pans with the fingers', (
    tester,
  ) async {
    await pump(tester);
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.hover(const Offset(100, 100)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 30)));
    expect(input.calls, ['pan']);
    // Fingers moving up scroll content up (natural scrolling): drag upward.
    expect(input.panned, const Offset(0, -30));
  });

  testWidgets('mouse wheel zooms', (tester) async {
    await pump(tester);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(100, 100)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    expect(input.calls, ['zoom']);
    expect(input.zoom, greaterThan(1), reason: 'wheel up zooms in');
  });

  testWidgets('pinch on the web zooms', (tester) async {
    await pump(tester);
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.hover(const Offset(50, 50)));
    await tester.sendEventToBinding(pointer.scale(1.25));
    expect(input.calls, ['zoom']);
    expect(input.zoom, closeTo(1.25, 1e-9));
  });

  testWidgets('desktop trackpad gestures pan, zoom and twist', (tester) async {
    await pump(tester);
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(
      pointer.panZoomStart(const Offset(100, 100)),
    );
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(
        const Offset(100, 100),
        pan: const Offset(20, 0),
        scale: 1.5,
        rotation: 0.2,
      ),
    );
    expect(input.panned, const Offset(20, 0));
    expect(input.zoom, closeTo(1.5, 1e-9));
    expect(input.rotated, closeTo(0.2, 1e-9));
  });

  testWidgets('left drag orbits, right drag pans', (tester) async {
    await pump(tester);
    await tester.dragFrom(const Offset(100, 100), const Offset(40, 0));
    expect(input.calls.toSet(), {'orbit'});
    input.calls.clear();
    await tester.dragFrom(
      const Offset(100, 100),
      const Offset(40, 0),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    expect(input.calls.toSet(), {'pan'});
  });

  group('MapCameraController', () {
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
  });
}
