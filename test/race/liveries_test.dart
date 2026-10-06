import 'package:f1_scene/src/geometry/car_mesh.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:f1_scene/src/race/liveries.dart';
import 'package:f1_scene/src/race/race_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

RaceDriver driver(String team, [int colour = 0x123456]) => RaceDriver(
  number: 1,
  acronym: 'TST',
  fullName: 'Test Driver',
  teamName: team,
  teamColour: colour,
);

void main() {
  test('each team gets its own scheme, by season where it changed', () {
    final redBull = Livery.of(driver('Red Bull Racing'), 2024);
    final juniors = Livery.of(driver('Racing Bulls'), 2025);
    expect(juniors, isNot(redBull));
    expect(Livery.of(driver('RB'), 2024), juniors);
    expect(
      Livery.of(driver('Haas F1 Team'), 2023),
      isNot(Livery.of(driver('Haas F1 Team'), 2024)),
    );
    // A team not listed is painted in OpenF1's team colour.
    final unknown = Livery.of(driver('Andretti', 0x2050A0), 2027);
    expect(unknown.upper, 0x2050A0);
    expect(unknown, Livery.fromColour(0x2050A0));
  });

  group('car paint', () {
    final car = CarMeshes.build();
    final colours = (
      upper: Vector4(1, 0, 0, 1),
      lower: Vector4(0, 1, 0, 1),
      nose: Vector4(0, 0, 1, 1),
      engineCover: Vector4(1, 1, 0, 1),
      wings: Vector4(0, 1, 1, 1),
    );
    final painted = car.paint(colours);
    Vector4 colourOf(int v) => Vector4(
      painted.colors![v * 4],
      painted.colors![v * 4 + 1],
      painted.colors![v * 4 + 2],
      painted.colors![v * 4 + 3],
    );

    test('every face is one colour, so paints meet along crisp lines', () {
      final parts = [
        car.upper,
        car.lower,
        car.nose,
        car.engineCover,
        car.wings,
      ];
      expect(painted.vertexCount, parts.fold(0, (n, p) => n + p.vertexCount));
      for (var t = 0; t < painted.indices.length; t += 3) {
        final a = colourOf(painted.indices[t]);
        expect(colourOf(painted.indices[t + 1]), a);
        expect(colourOf(painted.indices[t + 2]), a);
      }
    });

    test('the lower paint is below the upper', () {
      double meanHeight(MeshArrays mesh) {
        var sum = 0.0;
        for (var v = 0; v < mesh.vertexCount; v++) {
          sum += mesh.positions[v * 3 + 1];
        }
        return sum / mesh.vertexCount;
      }

      expect(meanHeight(car.lower), lessThan(meanHeight(car.upper) - 0.1));
    });

    test('number plates map the whole image', () {
      final plates = car.numberPlates;
      expect(plates.triangleCount, 6); // nose and both endplates
      expect(plates.texCoords, everyElement(inInclusiveRange(0, 1)));
    });
  });
}
