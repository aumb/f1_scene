import 'package:f1_scene/src/scene/adaptive_resolution.dart';
import 'package:flutter_test/flutter_test.dart';

const vsync = 1 / 120;

/// Feeds [seconds] of frames: every [missEvery]th frame takes two refresh
/// intervals (a missed frame), the rest one. 0 never misses.
void run(AdaptiveResolution r, double seconds, {int missEvery = 0}) {
  var t = 0.0;
  for (var i = 0; t < seconds; i++) {
    final missed = missEvery > 0 && i % missEvery == 0;
    final dt = missed ? 2 * vsync : vsync;
    r.record(dt);
    t += dt;
  }
}

void main() {
  test('starts within the pixel budget', () {
    final r = AdaptiveResolution(budget: 2.6e6)..start(6.4e6);
    expect(r.scale, closeTo(0.64, 0.01));
    expect((AdaptiveResolution()..start(1e6)).scale, 1.0);
    expect((AdaptiveResolution()..start(1e9)).scale, 0.5);
  });

  test('drops while frames are missed, down to the floor', () {
    final r = AdaptiveResolution()..start(1e6);
    // Every other frame missed: fill-bound at about 80 fps on 120 Hz.
    run(r, 3, missEvery: 2);
    expect(r.scale, lessThanOrEqualTo(0.75));
    run(r, 30, missEvery: 2);
    expect(r.scale, 0.5);
  });

  test('climbs back once frames keep up, and holds where they do', () {
    final r = AdaptiveResolution()..start(1e9); // 0.5
    run(r, 2); // learn the refresh rate
    run(r, 40);
    expect(r.scale, 1.0);
  });

  test('a raise that misses frames is undone and not retried for a while', () {
    final r = AdaptiveResolution()..start(1e9);
    run(r, 4); // calm: raises to 0.55
    expect(r.scale, 0.55);
    run(r, 2, missEvery: 3); // that raise was too much
    expect(r.scale, 0.5);
    run(r, 15); // calm again, but held back
    expect(r.scale, 0.5);
    run(r, 10); // the hold expires
    expect(r.scale, greaterThan(0.5));
  });

  test('ignores pauses and a little noise', () {
    final r = AdaptiveResolution()..start(1e6);
    r.record(2.0); // a hidden tab
    run(r, 10, missEvery: 20); // 5% missed: neither up nor down
    expect(r.scale, 1.0);
  });
}
