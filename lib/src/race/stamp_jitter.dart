import 'dart:math' as math;
import 'dart:typed_data';

import 'local_fit.dart';
import 'location_batch.dart';

/// Removes the timing jitter OpenF1 position samples share.
///
/// Positions come in batches, one sample per car, and each batch is stamped
/// with when it arrived rather than when the positions were taken: stamps
/// run up to ~0.1 s early or late while the positions themselves are steady.
/// Followed literally, a car at a constant 200 km/h appears to swing between
/// 150 and 350 km/h several times a second.
///
/// Every car in a batch shares its stamp's error, which makes the error
/// measurable: a car further along than its own smooth motion predicts was
/// really sampled later. Each stamp moves by the median such estimate over
/// the cars moving at speed, which agree with each other to ~10 ms.
Future<LocationBatch> correctStampJitter(LocationBatch batch) async {
  // This runs as each chunk of ~22k samples arrives, on the thread that
  // draws frames, so it works on flat arrays indexed by stamp rather than
  // maps keyed by time, and lets a frame through between passes.
  // A car needs a few samples for its own motion to be fitted at all.
  final cars = batch.samples.values.where((s) => s.t.length >= 5).toList();
  if (cars.length < _minCars) return batch;

  // Every stamp of every car, merged from each car's (sorted) stamps, and
  // each car's samples as indices into it.
  var stamps = Float64List(0);
  for (final s in batch.samples.values) {
    stamps = _union(stamps, s.t);
  }
  final tracks = [
    for (final s in cars) _Track(_indices(s.t, stamps), _distances(s.x, s.y)),
  ];
  final m = stamps.length;
  final corrected = Float64List.fromList(stamps);
  final estimates = Float64List(m * cars.length);
  final counts = Int32List(m);
  final scratch = Float64List(cars.length);
  final times = Float64List(tracks.map((c) => c.stamp.length).reduce(math.max));

  // Each car's fit leans on its neighbours' stamps, themselves jittered, so
  // refine a few times, each pass fitting on the stamps corrected so far.
  var changed = false;
  for (var pass = 0; pass < _passes; pass++) {
    await yieldToFrames();
    counts.fillRange(0, m, 0);
    for (final car in tracks) {
      for (var i = 0; i < car.stamp.length; i++) {
        times[i] = corrected[car.stamp[i]];
      }
      _estimate(car, times, (k, e) {
        // At most one estimate per car per stamp, so the slab can't overflow.
        if (counts[k] < cars.length) {
          estimates[k * cars.length + counts[k]++] = e;
        }
      });
    }
    for (var k = 0; k < m; k++) {
      final count = counts[k];
      if (count < _minCars) continue;
      for (var j = 0; j < count; j++) {
        scratch[j] = estimates[k * cars.length + j];
      }
      // Each stamp stays within halfway to its neighbours, and the chunk's
      // first and last never move outwards: every car's samples stay in
      // order, within the chunk and against the chunks either side.
      final lo = k == 0 ? stamps[k] : (stamps[k - 1] + stamps[k]) / 2 + _gap;
      final hi = k == m - 1
          ? stamps[k]
          : (stamps[k] + stamps[k + 1]) / 2 - _gap;
      corrected[k] = (corrected[k] + _median(scratch, count))
          .clamp(stamps[k] - _maxCorrection, stamps[k] + _maxCorrection)
          .clamp(lo, math.max(lo, hi));
      changed = true;
    }
  }
  if (!changed) return batch;
  await yieldToFrames();

  // Positions are unchanged; only each sample's time moves.
  final out = LocationBatch(batch.epoch);
  for (final MapEntry(key: driver, value: s) in batch.samples.entries) {
    final index = _indices(s.t, stamps);
    out.samples[driver] = (
      t: [for (final k in index) corrected[k]],
      x: s.x,
      y: s.y,
    );
  }
  return out;
}

/// The sorted union of sorted [a] and [b], without repeats.
Float64List _union(Float64List a, List<double> b) {
  final out = Float64List(a.length + b.length);
  var i = 0, j = 0, n = 0;
  while (i < a.length || j < b.length) {
    final double v;
    if (j >= b.length || (i < a.length && a[i] < b[j])) {
      v = a[i++];
    } else if (i >= a.length || b[j] < a[i]) {
      v = b[j++];
    } else {
      v = a[i++];
      j++;
    }
    if (n == 0 || out[n - 1] != v) out[n++] = v;
  }
  return Float64List.sublistView(out, 0, n);
}

/// Where each of sorted [times] sits in sorted [stamps], which holds them
/// all.
Int32List _indices(List<double> times, Float64List stamps) {
  final out = Int32List(times.length);
  var k = 0;
  for (var i = 0; i < times.length; i++) {
    while (stamps[k] < times[i]) {
      k++;
    }
    out[i] = k;
  }
  return out;
}

/// One car's samples: the stamp index of each and the distance driven by
/// then.
class _Track {
  const _Track(this.stamp, this.distance);

  final Int32List stamp;
  final Float64List distance;
}

/// Distance driven by each sample, along the chords between them.
Float64List _distances(List<double> x, List<double> y) {
  final d = Float64List(x.length);
  for (var i = 1; i < x.length; i++) {
    final dx = x[i] - x[i - 1], dy = y[i] - y[i - 1];
    d[i] = d[i - 1] + math.sqrt(dx * dx + dy * dy);
  }
  return d;
}

/// Median of the first [count] values, reordering them.
double _median(Float64List values, int count) {
  // Insertion sort: a stamp has at most one estimate per car.
  for (var i = 1; i < count; i++) {
    final v = values[i];
    var j = i - 1;
    while (j >= 0 && values[j] > v) {
      values[j + 1] = values[j];
      j--;
    }
    values[j + 1] = v;
  }
  return values[count ~/ 2];
}

/// Refinement passes.
const _passes = 3;

/// Cars needed to agree on a stamp's error before it is corrected.
const _minCars = 3;

/// Corrections beyond this are not jitter; leave those stamps alone.
const double _maxCorrection = 0.2;

/// Seconds kept clear between a corrected stamp and its neighbours' bounds.
const double _gap = 1e-4;

/// Only cars faster than this, in OpenF1 units (decimetres) per second,
/// say anything about timing; a stationary car is where it is at any time.
const double _minSpeed = 200;

/// Half-width, in seconds, of the window each car's motion is fitted over.
const double _fitHalfWidth = 1.0;

/// Reports, for each of [car]'s samples (by its stamp index), how much
/// later than its time in [t] its batch was really taken, judging by this
/// car alone.
void _estimate(
  _Track car,
  Float64List t,
  void Function(int stamp, double lateBy) report,
) {
  final n = car.stamp.length;
  final d = car.distance;
  final fit = LocalFit();
  var lo = 0, hi = 0;
  for (var i = 0; i < n; i++) {
    while (t[lo] < t[i] - _fitHalfWidth) {
      lo++;
    }
    while (hi + 1 < n && t[hi + 1] <= t[i] + _fitHalfWidth) {
      hi++;
    }
    // A fit from one side only would guess the motion, not measure it.
    if (i - lo < 2 || hi - i < 2) continue;
    // A stamp this car already reported (a duplicate row) adds nothing.
    if (i > 0 && car.stamp[i] == car.stamp[i - 1]) continue;

    // A line through the neighbours (not the sample itself), centred on
    // this sample's time.
    fit.clear();
    for (var j = lo; j <= hi; j++) {
      if (j == i) continue;
      final u = t[j] - t[i];
      fit.add(u, d[j], tricube(u / _fitHalfWidth));
    }
    final line = fit.lineOrNull();
    if (line == null) continue;
    final (level, speed) = line;
    if (speed < _minSpeed) continue;
    report(car.stamp[i], (d[i] - level) / speed);
  }
}
