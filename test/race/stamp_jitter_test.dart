import 'dart:math' as math;

import 'package:f1_scene/src/race/location_batch.dart';
import 'package:f1_scene/src/race/stamp_jitter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Positions taken every 0.25 s, stamped up to 80 ms off: the same error
  // for every car in a batch, as OpenF1 does.
  final random = math.Random(7);
  final trueTimes = [for (var k = 0; k < 200; k++) 100 + k * 0.25];
  final stamps = [
    for (final t in trueTimes) t + (random.nextDouble() * 2 - 1) * 0.08,
  ];

  LocationBatch drive(Map<int, double Function(double t)> distanceAt) {
    final batch = LocationBatch(DateTime.utc(2024));
    for (final MapEntry(key: driver, value: d) in distanceAt.entries) {
      for (var k = 0; k < trueTimes.length; k++) {
        // Along a gentle arc, in decimetres like OpenF1.
        final s = d(trueTimes[k]);
        final angle = s / 20000;
        batch.add(
          driver,
          stamps[k],
          20000 * math.sin(angle),
          20000 * (1 - math.cos(angle)),
        );
      }
    }
    return batch;
  }

  test('recovers the shared stamp error from the cars at speed', () async {
    final batch = drive({
      for (var car = 1; car <= 12; car++)
        // 50-85 m/s, some braking, one parked.
        car: car == 12
            ? (t) => 0
            : (t) =>
                  (500 + 30 * car) * t -
                  (car.isEven ? 40 * math.max(0, t - 120) * (t - 120) : 0),
    });
    final corrected = (await correctStampJitter(batch)).samples[1]!.t;

    // Away from the ends, where each car's fit has neighbours both sides.
    final before = [for (var k = 8; k < 192; k++) stamps[k] - trueTimes[k]];
    final after = [for (var k = 8; k < 192; k++) corrected[k] - trueTimes[k]];
    double rms(Iterable<double> e) =>
        math.sqrt(e.map((v) => v * v).reduce((a, b) => a + b) / e.length);
    Iterable<double> steps(List<double> e) => [
      for (var k = 1; k < e.length; k++) e[k] - e[k - 1],
    ];
    // What makes cars surge is the error changing from one stamp to the
    // next; nearly all of that goes.
    expect(rms(steps(before)), greaterThan(0.06));
    expect(rms(steps(after)), lessThan(0.006));
    // A slow drift of all stamps together looks just like every car
    // changing speed at once, so some of the error itself remains.
    expect(rms(before), greaterThan(0.04));
    expect(rms(after), lessThan(0.015));
  });

  test('leaves the stamps alone with too few cars moving', () async {
    final batch = drive({1: (t) => 600 * t, 2: (t) => 0, 3: (t) => 0});
    expect((await correctStampJitter(batch)).samples[1]!.t, stamps);
  });

  test('keeps every car in time order', () async {
    final batch = drive({
      for (var car = 1; car <= 6; car++) car: (t) => 700 * t,
    });
    for (final s in (await correctStampJitter(batch)).samples.values) {
      for (var i = 1; i < s.t.length; i++) {
        expect(s.t[i], greaterThan(s.t[i - 1]));
      }
    }
  });
}
