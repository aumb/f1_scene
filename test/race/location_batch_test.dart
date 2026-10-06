import 'dart:typed_data';

import 'package:f1_scene/src/race/location_batch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('position batches survive the binary form', () {
    final epoch = DateTime.utc(2024, 3, 2, 15);
    final batch = LocationBatch(epoch)
      ..add(1, 10.125, 1498, -412)
      ..add(44, 10.375, -2003.5, 77)
      ..add(1, 10.5, 1500, -411);
    // Read back against an epoch a minute later.
    final later = epoch.add(const Duration(minutes: 1));
    final back = LocationBatch.fromBytes(batch.toBytes(), later)!;
    expect(back.samples[1]!.t, [closeTo(-49.875, 1e-9), closeTo(-49.5, 1e-9)]);
    expect(back.samples[1]!.x, [1498, 1500]);
    expect(back.samples[44]!.x, [-2003.5]);
    expect(back.samples[44]!.y, [77]);
    expect(LocationBatch.fromBytes(Uint8List(24), epoch), isNull);
  });

  test('reads OpenF1 timestamps like DateTime.parse does', () {
    for (final text in [
      '2024-03-02T15:20:00.138000+00:00',
      '2024-03-02T15:20:00+00:00',
      '2026-12-31T23:59:59.999999+00:00',
      '2024-02-29T00:00:00.5Z',
      '2023-01-01T00:00:00.000000+02:00',
    ]) {
      expect(
        isoSeconds(text),
        closeTo(DateTime.parse(text).microsecondsSinceEpoch / 1e6, 1e-6),
        reason: text,
      );
    }
  });
}
