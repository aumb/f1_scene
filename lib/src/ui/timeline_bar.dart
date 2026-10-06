import 'package:flutter/material.dart';

import '../race/race_replay.dart';
import 'hud.dart';

/// Playback controls for a [RaceReplay], or its loading / error state.
class TimelineBar extends StatelessWidget {
  const TimelineBar({
    super.key,
    required this.replay,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final RaceReplay? replay;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  static const _speeds = [1.0, 4.0, 16.0, 64.0];

  @override
  Widget build(BuildContext context) {
    final replay = this.replay;
    final theme = Theme.of(context);
    if (replay == null) {
      return Panel(
        padding: 12,
        child: Row(
          children: [
            if (loading) ...[
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              const Text('Loading race data…'),
            ] else if (error != null) ...[
              Icon(Icons.cloud_off, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Expanded(child: Text(error!)),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      );
    }

    return Panel(
      padding: 8,
      child: ListenableBuilder(
        listenable: replay,
        builder: (context, _) => ValueListenableBuilder<double>(
          valueListenable: replay.time,
          builder: (context, t, _) {
            final lap = replay.lapAt(t);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: replay.playing ? 'Pause' : 'Play',
                      onPressed: replay.playing ? replay.pause : replay.play,
                      icon: Icon(
                        replay.playing ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final i = _speeds.indexOf(replay.speed);
                        replay.speed = _speeds[(i + 1) % _speeds.length];
                      },
                      child: Text('${replay.speed.toStringAsFixed(0)}×'),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      lap == 0 ? 'Formation' : 'Lap $lap/${replay.lapCount}',
                      style: theme.textTheme.titleSmall,
                    ),
                    const Spacer(),
                    if (replay.buffering)
                      const Padding(
                        padding: EdgeInsets.only(right: 10),
                        child: SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    Text(
                      _raceClock(t - replay.raceStart),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
                Slider(
                  min: replay.timeline.start,
                  max: replay.timeline.end,
                  value: t.clamp(replay.timeline.start, replay.timeline.end),
                  onChanged: replay.seek,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Race time relative to lights out, e.g. `-0:15`, `23:41`, `1:02:09`.
  static String _raceClock(double seconds) {
    final sign = seconds < 0 ? '-' : '';
    final total = seconds.abs().floor();
    final h = total ~/ 3600, m = (total ~/ 60) % 60, s = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$sign$h:${two(m)}:${two(s)}' : '$sign$m:${two(s)}';
  }
}
