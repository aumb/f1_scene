import 'dart:math' as math;

import 'package:f1_scene/src/race/car_motion.dart';
import 'package:f1_scene/src/race/traffic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import '../support/circuits.dart';

void main() {
  final (:stations, :track) = bahrain();
  final traffic = TrafficSeparation(track);
  final mps = track.metersPerStation;

  /// A car on the shared line [lateral] left of center, [meters] along.
  CarPose car(double meters, {double lateral = 0, double speed = 70}) {
    final along = meters / mps;
    final placed = track.place(along, lateral);
    return CarPose(
      placed.position,
      0,
      along: along,
      lateral: lateral,
      speed: speed,
    );
  }

  double sideBySide(CarPose a, CarPose b) =>
      track.project(a.position.x, a.position.z).lateral -
      track.project(b.position.x, b.position.z).lateral;

  test('cars in the same spot end up side by side', () {
    final out = traffic.separate({4: car(800), 11: car(800)});
    expect(sideBySide(out[4]!, out[11]!), inInclusiveRange(2.2, 2.4));
    for (final pose in out.values) {
      final (:min, :max) = track.lateralLimits(pose.along!, margin: 1);
      expect(pose.lateral, inInclusiveRange(min - 1e-6, max + 1e-6));
    }
  });

  test('a pass goes round the side, smoothly, without swapping sides', () {
    // Car 4 at 80 m/s catches and passes car 11 at 70 m/s, both on the
    // shared line.
    double? previousA, previousB, previousHeading;
    for (var t = 0.0; t < 6; t += 1 / 60) {
      final out = traffic.separate({
        4: car(1000 + 80 * t, speed: 80),
        11: car(1030 + 70 * t, speed: 70),
      });
      final a = out[4]!, b = out[11]!;
      final gap = (a.along! - b.along!) * mps;
      final apart = a.lateral - b.lateral;
      expect(apart, greaterThanOrEqualTo(-1e-9), reason: 'sides swapped');
      if (gap.abs() < 5.2) expect(apart, greaterThan(2.0), reason: 't $t');
      if (previousA != null) {
        // Under 0.1 m a frame: a step, not a jump.
        expect((a.lateral - previousA).abs(), lessThan(0.1), reason: 't $t');
        expect((b.lateral - previousB!).abs(), lessThan(0.1), reason: 't $t');
      }
      if (previousHeading != null) {
        // Turning into and out of the step, never snapping.
        expect((a.heading - previousHeading).abs(), lessThan(0.02));
      }
      previousA = a.lateral;
      previousB = b.lateral;
      previousHeading = a.heading;
    }
    // Back on the line once clear.
    expect(previousA, closeTo(0, 1e-6));
  });

  test('a crawling car being lapped turns back without a snap', () {
    // Car 11 limps round at 15 m/s; car 4 laps it at 45 m/s, so the step
    // aside starts and ends far out, where it is still sideways in motion.
    final previous = <int, double>{};
    for (var t = 0.0; t < 3; t += 1 / 60) {
      final out = traffic.separate({
        4: car(1000 + 45 * t, speed: 45),
        11: car(1045 + 15 * t, speed: 15),
      });
      for (final MapEntry(key: driver, value: pose) in out.entries) {
        final before = previous[driver];
        if (before != null) {
          expect(
            (pose.heading - before).abs(),
            lessThan(0.02),
            reason: 'car $driver at t $t',
          );
        }
        previous[driver] = pose.heading;
      }
    }
  });

  test(
    'a reversed pass keeps cars facing and steering into their movement',
    () {
      CarPose reversedCar(double meters, double speed) {
        final along = meters / mps;
        final placed = track.place(along, 0);
        return CarPose(
          placed.position,
          math.atan2(-placed.forward.x, -placed.forward.z),
          pitch: -math.asin(placed.forward.y),
          along: along,
          speed: -speed,
          directionSign: -1,
        );
      }

      Map<int, CarPose> at(double t) => traffic.separate({
        4: reversedCar(1030 - 80 * t, 80),
        11: reversedCar(1000 - 70 * t, 70),
      });
      var turned = false;
      for (var t = 0.0; t < 6; t += 0.05) {
        final now = at(t), next = at(t + 0.01);
        final a = now[4]!, b = now[11]!;
        expect(a.lateral, lessThanOrEqualTo(b.lateral + 1e-9));
        if ((a.along! - b.along!).abs() * mps < 5.2) {
          expect(b.lateral - a.lateral, greaterThan(2));
        }
        for (final driver in now.keys) {
          final pose = now[driver]!;
          final nose = Matrix4.compose(
            Vector3.zero(),
            pose.rotation,
            Vector3.all(1),
          ).transform3(Vector3(0, 0, 1));
          final travel = (next[driver]!.position - pose.position).normalized();
          expect(nose.dot(travel), greaterThan(0.99));
          expect(pose.directionSign, -1);
          final base = reversedCar(
            driver == 4 ? 1030 - 80 * t : 1000 - 70 * t,
            driver == 4 ? 80 : 70,
          );
          if ((pose.heading - base.heading).abs() > 0.001) {
            turned = true;
          }
        }
      }
      expect(turned, isTrue);
    },
  );

  test('two pairs meeting reorder smoothly instead of jumping', () {
    // Cars 3 and 4 side by side; 18 and 27 side by side, catching them.
    // The fixed order across the track puts 4 left of 18, the reverse of
    // where each pair has it, so the pack has to reshuffle as they meet.
    final previous = <int, double>{};
    for (var t = 0.0; t < 6; t += 1 / 60) {
      final out = traffic.separate({
        3: car(1000 + 50 * t, speed: 50),
        4: car(1000 + 50 * t, speed: 50),
        18: car(985 + 52 * t, speed: 52),
        27: car(985 + 52 * t, speed: 52),
      });
      for (final MapEntry(key: driver, value: pose) in out.entries) {
        final before = previous[driver];
        if (before != null) {
          expect(
            (pose.lateral - before).abs(),
            lessThan(0.1),
            reason: 'car $driver at t $t',
          );
        }
        previous[driver] = pose.lateral;
      }
    }
  });

  test('three abreast, and against the edge', () {
    final three = traffic.separate({1: car(500), 2: car(500), 3: car(500)});
    expect(sideBySide(three[1]!, three[2]!), greaterThan(2.1));
    expect(sideBySide(three[2]!, three[3]!), greaterThan(2.1));

    // The shared line hugs the left edge: both still fit, inside it.
    final hi = track.lateralLimits(600 / mps, margin: 1).max;
    final edge = traffic.separate({
      1: car(600, lateral: hi),
      2: car(600, lateral: hi),
    });
    expect(edge[1]!.lateral, closeTo(hi, 1e-6));
    expect(sideBySide(edge[1]!, edge[2]!), greaterThan(2.1));
  });

  test('leaves cars apart, and in the pit lane, alone', () {
    final apart = {1: car(100), 2: car(200)};
    expect(traffic.separate(apart), apart);
    final pit = CarPose(car(100).position, 0, inPit: true);
    final out = traffic.separate({1: car(100), 2: pit});
    expect(out[2], same(pit));
    expect(out[1]!.lateral, 0);
  });

  group('readable scales', () {
    test('a lone car keeps the full scale', () {
      final scales = readableScales({1: car(100), 2: car(400)}, 5);
      expect(scales.values, everyElement(5));
    });

    test('cars close together shrink toward real size', () {
      final scales = readableScales({
        1: car(100, lateral: 1.15),
        2: car(100, lateral: -1.15),
        3: car(115),
      }, 5);
      // Side by side: only room for about real size.
      expect(scales[1], lessThan(1.3));
      // 15 m behind them: room for under three times.
      expect(scales[3], inInclusiveRange(2, 3));
    });
  });
}
