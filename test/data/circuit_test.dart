import 'package:flutter_test/flutter_test.dart';

import '../support/circuits.dart';

void main() {
  final circuit = loadCircuit('bh-2002');

  test('lap distance counts from the start/finish line', () {
    expect(circuit.sAtLapDistance(0), closeTo(circuit.startFinishS, 1e-9));
    // The vendored centerline differs a little in length from the official
    // lap; the start/finish straight is straight enough to measure on.
    final scale = circuit.centerline.length / circuit.lapLength;
    final line = circuit.centerline;
    expect(
      line
          .pointAt(circuit.sAtLapDistance(0))
          .distanceTo(line.pointAt(circuit.sAtLapDistance(50))),
      closeTo(50 * scale, 1),
    );
  });
}
