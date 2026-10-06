import 'package:f1_scene/src/race/location_timeline.dart';
import 'package:f1_scene/src/race/openf1_client.dart';
import 'package:f1_scene/src/race/race_repository.dart';
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
    test('interpolates between samples', () {
      final timeline = LocationTimeline(start: 0, end: 600, chunkSeconds: 300)
        ..addChunk(0, batch(0, 300));
      final (x, y) = timeline.positionAt(1, 10.1)!;
      expect(x, closeTo(101, 1e-9));
      expect(y, closeTo(-10.1, 1e-9));
    });

    test('splices chunks that arrive out of order', () {
      final timeline = LocationTimeline(start: 0, end: 900, chunkSeconds: 300)
        ..addChunk(2, batch(600, 900))
        ..addChunk(0, batch(0, 300))
        ..addChunk(1, batch(300, 600));
      for (final t in [5.0, 299.9, 300.1, 650.0, 899.0]) {
        expect(timeline.positionAt(1, t)!.$1, closeTo(10 * t, 1e-9));
      }
    });

    test('reports no position across gaps or missing chunks', () {
      final timeline = LocationTimeline(start: 0, end: 900, chunkSeconds: 300)
        ..addChunk(0, batch(0, 100))
        ..addChunk(0, batch(200, 300));
      expect(timeline.positionAt(1, 150), isNull, reason: 'data gap');
      expect(timeline.positionAt(1, 450), isNull, reason: 'chunk not loaded');
      expect(timeline.positionAt(2, 50), isNull, reason: 'unknown driver');
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

  test('OpenF1 filters keep comparison operators in the key', () {
    expect(OpenF1Client.filterText('session_key', '9472'), 'session_key=9472');
    expect(
      OpenF1Client.filterText('date>=', '2024-03-02T15:20:00'),
      'date%3E=2024-03-02T15%3A20%3A00',
    );
    expect(OpenF1Client.filterText('date<', '2024'), 'date%3C2024');
  });
}
