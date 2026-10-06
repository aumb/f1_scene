import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';

import '../scene/adaptive_resolution.dart';
import 'frame_stats.dart';

/// Times each frame's work and keeps the render resolution where the GPU
/// holds the frame rate.
///
/// Two URL options help when measuring: `?stats` shows the timings from the
/// start (the F key toggles them), and `?scale=0.75` fixes the resolution.
class FramePacer {
  /// Frame timings, for [FrameStatsView].
  final stats = FrameStats();

  /// Whether the timings show; also logs resolution changes.
  bool showStats = Uri.base.queryParameters.containsKey('stats');

  final _resolution = AdaptiveResolution();
  final double? _fixedScale = double.tryParse(
    Uri.base.queryParameters['scale'] ?? '',
  );
  bool _started = false;
  final _watch = Stopwatch();

  /// Runs [work] for a frame [dt] seconds after the last, then adapts
  /// [scene]'s resolution: [pixels] is the device pixels it covers at full
  /// scale, 0 until it is laid out.
  void tick(
    Scene scene,
    double dt, {
    required void Function(double dt) work,
    required double pixels,
  }) {
    _watch
      ..reset()
      ..start();
    work(dt);
    _watch.stop();
    stats.record(dt, _watch.elapsedMicroseconds / 1e6);

    final fixed = _fixedScale;
    if (fixed != null) {
      scene.renderScale = fixed.clamp(0.25, 1.0);
    } else if (!_started) {
      // Start within a pixel budget for this viewport, then adapt.
      if (pixels <= 0) return;
      _resolution.start(pixels);
      scene.renderScale = _resolution.scale;
      _started = true;
      if (showStats) debugPrint('Render scale ${_resolution.scale} to start');
    } else if (_resolution.record(dt)) {
      scene.renderScale = _resolution.scale;
      if (showStats) debugPrint('Render scale ${_resolution.scale}');
    }
    stats.renderScale = scene.renderScale;
  }
}
