import 'dart:math' as math;

/// Trades render resolution for frame rate as the GPU allows.
///
/// The scene's cost is mostly per pixel (shading, shadows, ambient
/// occlusion, bloom), so on a large or high-density screen it is fill-bound:
/// at 1920x1080 on a 2x display it renders 6 MP a frame and holds ~72 fps
/// where 0.75 scale holds ~100. Fed every frame's interval, this lowers the
/// scale quickly while frames miss the display's refresh and raises it back
/// slowly once they stop, backing off for a while when a raise doesn't fit.
class AdaptiveResolution {
  AdaptiveResolution({this.min = 0.5, this.max = 1.0, this.budget = 2.6e6});

  final double min;
  final double max;

  /// Device pixels a frame to start from; the scale adapts from there.
  final double budget;

  /// The render scale to use now.
  double get scale => _scale;
  double _scale = 1;

  /// Starts from the scale that keeps a viewport of [pixels] device pixels
  /// within [budget].
  void start(double pixels) {
    _scale = pixels <= 0
        ? max
        : math.sqrt(budget / pixels).clamp(min, max).toDouble();
    _round();
  }

  final _intervals = <double>[];
  double _elapsed = 0;
  double _clock = 0;

  /// The display's refresh interval, learned from the fastest frames.
  double? _refresh;
  int _calmSeconds = 0;
  double _raisedAt = double.negativeInfinity;
  double _holdUntil = 0;

  /// Records one frame [interval] in seconds. Returns true when [scale]
  /// changed.
  bool record(double interval) {
    // Pauses (a hidden tab, a debugger) say nothing about the GPU.
    if (interval <= 0 || interval > 0.25) return false;
    _clock += interval;
    _elapsed += interval;
    _intervals.add(interval);
    if (_elapsed < 1) return false;

    // Judge each second of frames.
    final sorted = [..._intervals]..sort();
    _intervals.clear();
    _elapsed = 0;
    // The fastest tenth of frames ran at the refresh rate; remember the
    // fastest seen, so a GPU slow on every frame doesn't pass for a slow
    // display, letting it drift up slowly in case the display changes.
    final fastest = sorted[sorted.length ~/ 10];
    final refresh = _refresh = math.min((_refresh ?? fastest) * 1.01, fastest);
    final missed =
        sorted.where((d) => d > refresh * 1.5).length / sorted.length;

    final before = _scale;
    if (missed > 0.15) {
      // Missing frames soon after a raise: that raise was a step too far,
      // so hold off trying again.
      if (_clock - _raisedAt < 5) _holdUntil = _clock + 20;
      _calmSeconds = 0;
      _scale = math.max(min, _scale - (missed > 0.4 ? 0.1 : 0.05));
    } else if (missed < 0.03) {
      if (++_calmSeconds >= 3 && _clock >= _holdUntil && _scale < max) {
        _scale = math.min(max, _scale + 0.05);
        _raisedAt = _clock;
        _calmSeconds = 0;
      }
    } else {
      _calmSeconds = 0;
    }
    _round();
    return _scale != before;
  }

  void _round() => _scale = (_scale * 100).round() / 100;
}
