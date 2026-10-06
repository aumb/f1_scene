import 'package:f1_scene/src/race/location_batch.dart';
import 'package:f1_scene/src/race/location_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// A chunk of samples every 0.25 s with x = 10 * t, y = -t.
LocationBatch batch(double from, double to, {int driver = 1}) {
  final b = LocationBatch(DateTime.utc(2024));
  for (var t = from; t < to; t += 0.25) {
    b.add(driver, t, 10 * t, -t);
  }
  return b;
}

void main() {
  group('LocationTimeline', () {
    test('finds the samples around a time', () {
      final timeline = LocationTimeline(start: 0, end: 600, chunkSeconds: 300)
        ..addChunk(0, batch(0, 300));
      final w = timeline.windowAt(1, 10.1, reach: 0.5)!;
      expect(w.t[w.bracket], 10.0);
      expect(w.t[w.bracket + 1], 10.25);
      expect(w.x[w.bracket], closeTo(100, 1e-9));
      // Every sample within the reach (9.6 to 10.6 s) either side.
      expect(w.t.first, 9.75);
      expect(w.t.last, 10.5);
    });

    test('splices chunks that arrive out of order', () {
      final timeline = LocationTimeline(start: 0, end: 900, chunkSeconds: 300)
        ..addChunk(2, batch(600, 900))
        ..addChunk(0, batch(0, 300))
        ..addChunk(1, batch(300, 600));
      for (final t in [5.0, 299.9, 300.1, 650.0, 899.0]) {
        final w = timeline.windowAt(1, t)!;
        final before = w.t[w.bracket], after = w.t[w.bracket + 1];
        expect(before, lessThanOrEqualTo(t));
        expect(after, greaterThan(t));
        expect(w.x[w.bracket], closeTo(10 * before, 1e-9));
      }
    });

    test('has no samples across gaps or missing chunks', () {
      final timeline = LocationTimeline(start: 0, end: 900, chunkSeconds: 300)
        ..addChunk(0, batch(0, 100))
        ..addChunk(0, batch(200, 300));
      expect(timeline.windowAt(1, 150), isNull, reason: 'data gap');
      expect(timeline.windowAt(1, 450), isNull, reason: 'chunk not loaded');
      expect(timeline.windowAt(2, 50), isNull, reason: 'unknown driver');
    });

    test('is ready only once the chunk, and the next near its end, load', () {
      final timeline = LocationTimeline(start: 0, end: 900, chunkSeconds: 300);
      expect(timeline.isReady(10), isFalse);
      expect(timeline.wanted(10, ahead: 1), [0, 1]);

      timeline
        ..markLoading(1)
        ..addChunk(0, batch(0, 300));
      expect(timeline.isReady(10), isTrue);
      expect(timeline.isReady(298), isFalse, reason: 'needs chunk 1 to cross');
      expect(timeline.wanted(10, ahead: 1), isEmpty, reason: '1 is loading');

      timeline.markFailed(1);
      expect(timeline.wanted(10, ahead: 1), [1], reason: 'retry failures');
    });
  });
}
