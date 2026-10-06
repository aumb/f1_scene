import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../geometry/car_mesh.dart';
import '../geometry/track_mesh.dart';
import '../race/car_motion.dart';
import '../race/liveries.dart';
import '../race/race_models.dart';
import '../race/traffic.dart';

/// One car model per driver, posed from replay poses every frame.
///
/// Every car shares the same geometry, painted per vertex in its team's
/// livery so the bodywork draws in one call, and carries its number on the
/// nose and rear wing. Real size is a few pixels from a whole-circuit view,
/// so the orbit camera asks for cars scaled up with distance.
class CarsLayer {
  CarsLayer(List<RaceDriver> drivers, {required int year}) {
    final shared = _SharedCar.instance;
    for (final driver in drivers) {
      final livery = Livery.of(driver, year);
      final node = Node(
        name: 'car ${driver.acronym}',
        mesh: Mesh.primitives(
          primitives: [
            MeshPrimitive(shared.bodyFor(livery), shared.paint),
            MeshPrimitive(shared.carbon, shared.carbonMaterial),
            MeshPrimitive(shared.tyres, shared.tyreMaterial),
            MeshPrimitive(shared.accent, shared.accentMaterial),
          ],
        ),
      )..visible = false;
      _cars[driver.number] = node;
      root.add(node);
      // The number is drawn as an image; add it once that is ready.
      numberTexture(driver.number, livery.number).then(
        (texture) {
          node.add(
            Node(
              name: 'number ${driver.number}',
              mesh: Mesh(
                shared.numberPlates,
                PhysicallyBasedMaterial(baseColorTexture: texture)
                  ..alphaMode = AlphaMode.blend
                  ..metallicFactor = 0
                  ..roughnessFactor = 0.45
                  // Over the paint it sits a centimetre above, from any range.
                  ..depthLayer = 1,
              ),
            )..shadowCastingMode = ShadowCastingMode.off,
          );
        },
        onError: (Object e) => debugPrint('No number for ${driver.number}: $e'),
      );
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
  /// cars about their contact point, each only as far as it stays clear of
  /// the others (see [readableScales]).
  void update(Map<int, CarPose> poses, {double scale = 1}) {
    final scales = scale > 1 ? readableScales(poses, scale) : const {};
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
          vm.Vector3.all(scales[number] ?? scale),
        );
    }
  }
}

/// The car number as an image: [fill] figures with a contrasting outline on
/// a transparent background, sized for the number plates.
Future<Texture2D> numberTexture(int number, int fill) async {
  const width = 256, height = 160;
  final light =
      0.2126 * ((fill >> 16) & 0xff) +
          0.7152 * ((fill >> 8) & 0xff) +
          0.0722 * (fill & 0xff) >
      140;
  TextPainter figures(Paint paint) => TextPainter(
    text: TextSpan(
      text: '$number',
      style: TextStyle(
        fontSize: 132,
        height: 1,
        fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic,
        foreground: paint,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final outline = figures(
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeJoin = StrokeJoin.round
      ..color = light ? const Color(0xFF15171A) : const Color(0xFFF4F5F7),
  );
  final body = figures(Paint()..color = Color(0xFF000000 | fill));
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final at = Offset((width - body.width) / 2, (height - body.height) / 2);
  outline.paint(canvas, at);
  body.paint(canvas, at);
  final image = await recorder.endRecording().toImage(width, height);
  try {
    return await Texture2D.fromImage(image);
  } finally {
    image.dispose();
  }
}

/// GPU geometry and the non-team materials, built once and shared by every
/// car in every race.
class _SharedCar {
  _SharedCar._() {
    _meshes = CarMeshes.build();
    carbon = _upload(_meshes.carbon);
    tyres = _upload(_meshes.tyres);
    accent = _upload(_meshes.accent);
    numberPlates = _upload(_meshes.numberPlates);
  }

  static final instance = _SharedCar._();

  late final CarMeshes _meshes;
  late final MeshGeometry carbon;
  late final MeshGeometry tyres;
  late final MeshGeometry accent;
  late final MeshGeometry numberPlates;
  final _bodies = <Livery, MeshGeometry>{};

  static MeshGeometry _upload(MeshArrays arrays) => MeshGeometry.fromArrays(
    positions: arrays.positions,
    normals: arrays.normals,
    colors: arrays.colors,
    texCoords: arrays.texCoords,
    indices: arrays.indices,
  );

  /// The painted bodywork in [livery], built once per team.
  MeshGeometry bodyFor(Livery livery) => _bodies[livery] ??= _upload(
    _meshes.paint((
      upper: linearColor(livery.upper),
      lower: linearColor(livery.lower),
      nose: linearColor(livery.nose),
      engineCover: linearColor(livery.engineCover),
      wings: linearColor(livery.wings),
    )),
  );

  /// Paint for every team: the colours come from the vertices.
  final paint = PhysicallyBasedMaterial()
    ..metallicFactor = 0.25
    ..roughnessFactor = 0.35;

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
