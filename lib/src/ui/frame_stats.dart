import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Rolling frame timing: how often frames arrive (which catches both UI and
/// raster stalls, since a late frame delays the next tick) and how long the
/// app's own per-frame work takes on the UI thread.
class FrameStats {
  final _intervals = <double>[];
  final _work = <double>[];
  double _sinceReport = 0;

  /// Updated twice a second.
  final summary = ValueNotifier<FrameSummary?>(null);

  /// Records one frame: [interval] since the previous one and [work] spent
  /// in the app's tick, both in seconds.
  void record(double interval, double work) {
    _intervals.add(interval);
    _work.add(work);
    if (_intervals.length > 240) {
      _intervals.removeAt(0);
      _work.removeAt(0);
    }
    _sinceReport += interval;
    if (_sinceReport < 0.5) return;
    _sinceReport = 0;
    final recent = _intervals.sublist(math.max(0, _intervals.length - 120));
    final mean = recent.reduce((a, b) => a + b) / recent.length;
    final sorted = [...recent]..sort();
    summary.value = FrameSummary(
      fps: 1 / mean,
      p95: sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)],
      worst: sorted.last,
      slowFrames: recent.where((i) => i > 1 / 45).length,
      work: _work.reduce((a, b) => a + b) / _work.length,
      workWorst: _work.reduce(math.max),
    );
  }
}

class FrameSummary {
  const FrameSummary({
    required this.fps,
    required this.p95,
    required this.worst,
    required this.slowFrames,
    required this.work,
    required this.workWorst,
  });

  final double fps;
  final double p95;
  final double worst;

  /// Frames over ~22 ms (below 45 fps) among the last 120.
  final int slowFrames;

  /// Mean and worst seconds of app tick work.
  final double work;
  final double workWorst;
}

/// A small readout of [FrameStats].
class FrameStatsView extends StatelessWidget {
  const FrameStatsView({super.key, required this.stats});

  final FrameStats stats;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: Colors.white70,
    );
    String ms(double s) => '${(s * 1000).toStringAsFixed(1)} ms';
    return ValueListenableBuilder<FrameSummary?>(
      valueListenable: stats.summary,
      builder: (context, s, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xCC000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            s == null
                ? 'measuring…'
                : '${s.fps.toStringAsFixed(0)} fps · p95 ${ms(s.p95)} · '
                      'worst ${ms(s.worst)} · slow ${s.slowFrames}/120\n'
                      'tick ${ms(s.work)} · worst ${ms(s.workWorst)}',
            style: style,
          ),
        ),
      ),
    );
  }
}
