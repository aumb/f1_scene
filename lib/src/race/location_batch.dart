import 'dart:math' as math;
import 'dart:typed_data';

/// Raw position samples for one time window, all drivers, as parallel lists.
///
/// Coordinates are in OpenF1's circuit frame (decimeters, arbitrary rotation),
/// times in seconds since [epoch].
class LocationBatch {
  LocationBatch(this.epoch);

  final DateTime epoch;
  final samples = <int, ({List<double> t, List<double> x, List<double> y})>{};

  void add(int driver, double t, double x, double y) {
    final series = samples[driver] ??= (
      t: <double>[],
      x: <double>[],
      y: <double>[],
    );
    series.t.add(t);
    series.x.add(x);
    series.y.add(y);
  }

  static const _magic = 0x46314c42; // "F1LB"
  static const _version = 1;

  /// A compact binary form for the cache: ~16 bytes a sample against ~140
  /// as OpenF1's JSON, and far quicker to read back.
  Uint8List toBytes() {
    final drivers = samples.entries.toList();
    final count = drivers.fold(0, (n, d) => n + d.value.t.length);
    final data = ByteData(20 + drivers.length * 8 + count * 16);
    var at = 0;
    void u32(int v) => data.setUint32((at += 4) - 4, v, Endian.little);
    u32(_magic);
    u32(_version);
    data.setFloat64(at, epoch.microsecondsSinceEpoch / 1e6, Endian.little);
    at += 8;
    u32(drivers.length);
    for (final MapEntry(key: driver, value: s) in drivers) {
      u32(driver);
      u32(s.t.length);
    }
    for (final MapEntry(value: s) in drivers) {
      for (var i = 0; i < s.t.length; i++) {
        data
          ..setFloat64(at, s.t[i], Endian.little)
          ..setFloat32(at + 8, s.x[i], Endian.little)
          ..setFloat32(at + 12, s.y[i], Endian.little);
        at += 16;
      }
    }
    return data.buffer.asUint8List();
  }

  /// Reads [toBytes] back with times relative to [epoch], or null when
  /// [bytes] are not in that form.
  static LocationBatch? fromBytes(Uint8List bytes, DateTime epoch) {
    if (bytes.length < 20) return null;
    final data = ByteData.sublistView(bytes);
    var at = 0;
    int u32() => data.getUint32((at += 4) - 4, Endian.little);
    if (u32() != _magic || u32() != _version) return null;
    final shift =
        data.getFloat64(at, Endian.little) - epoch.microsecondsSinceEpoch / 1e6;
    at += 8;
    final drivers = [for (var n = u32(), i = 0; i < n; i++) (u32(), u32())];
    final batch = LocationBatch(epoch);
    for (final (driver, count) in drivers) {
      final t = List<double>.filled(count, 0), x = [...t], y = [...t];
      for (var i = 0; i < count; i++) {
        t[i] = data.getFloat64(at, Endian.little) + shift;
        x[i] = data.getFloat32(at + 8, Endian.little);
        y[i] = data.getFloat32(at + 12, Endian.little);
        at += 16;
      }
      batch.samples[driver] = (t: t, x: x, y: y);
    }
    return batch;
  }
}

/// Lets the event loop run, so a frame can be drawn, before continuing a
/// long piece of work.
Future<void> yieldToFrames() => Future<void>.delayed(Duration.zero);

/// Seconds since the Unix epoch of an OpenF1 timestamp such as
/// `2024-03-02T15:20:00.138000+00:00`.
///
/// A position chunk carries ~22k of these; reading the fixed layout directly
/// is several times faster than `DateTime.parse` on the web. Anything not
/// in that layout (an offset other than UTC) falls back to it.
double isoSeconds(String s) {
  final plusZero = s.length >= 25 && s.endsWith('+00:00');
  if (!plusZero && !s.endsWith('Z')) {
    return DateTime.parse(s).microsecondsSinceEpoch / 1e6;
  }
  int digits(int from, int to) {
    var v = 0;
    for (var i = from; i < to; i++) {
      v = v * 10 + s.codeUnitAt(i) - 48;
    }
    return v;
  }

  final year = digits(0, 4), month = digits(5, 7), day = digits(8, 10);
  final seconds = digits(11, 13) * 3600 + digits(14, 16) * 60 + digits(17, 19);
  var fraction = 0.0;
  final end = plusZero ? s.length - 6 : s.length - 1;
  if (end > 20 && s.codeUnitAt(19) == 46) {
    fraction = digits(20, end) / math.pow(10, end - 20);
  }
  return _daysFromCivil(year, month, day) * 86400.0 + seconds + fraction;
}

/// Days since 1970-01-01 of a proleptic Gregorian date (H. Hinnant).
int _daysFromCivil(int y, int m, int d) {
  final yy = m <= 2 ? y - 1 : y;
  final era = (yy >= 0 ? yy : yy - 399) ~/ 400;
  final yoe = yy - era * 400;
  final doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) ~/ 5 + d - 1;
  final doe = yoe * 365 + yoe ~/ 4 - yoe ~/ 100 + doy;
  return era * 146097 + doe - 719468;
}
