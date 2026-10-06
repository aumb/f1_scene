import 'package:flutter/material.dart';

import '../race/race_replay.dart';
import 'hud_style.dart';

/// Play, speed, lap and the scrubber, along the bottom of the map.
class PlaybackBar extends StatelessWidget {
  const PlaybackBar({super.key, required this.replay});

  /// Null before a race loads: the controls show, disabled.
  final RaceReplay? replay;

  static const _speeds = [1.0, 4.0, 16.0, 64.0];

  @override
  Widget build(BuildContext context) {
    final replay = this.replay;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Hud.bar,
        border: Border(top: BorderSide(color: Hud.line)),
      ),
      child: replay == null
          ? const _Controls(
              playing: false,
              speed: 1,
              lap: 0,
              lapCount: 0,
              clock: '–',
              time: 0,
              start: 0,
              end: 1,
            )
          : ListenableBuilder(
              listenable: replay,
              builder: (context, _) => ValueListenableBuilder<double>(
                valueListenable: replay.time,
                builder: (context, t, _) => _Controls(
                  playing: replay.playing,
                  buffering: replay.buffering,
                  speed: replay.speed,
                  lap: replay.lapAt(t),
                  lapCount: replay.lapCount,
                  clock: _raceClock(t - replay.raceStart),
                  time: t,
                  start: replay.timeline.start,
                  end: replay.timeline.end,
                  onPlay: replay.playing ? replay.pause : replay.play,
                  onSpeed: () {
                    final i = _speeds.indexOf(replay.speed);
                    replay.speed = _speeds[(i + 1) % _speeds.length];
                  },
                  onSeek: replay.seek,
                ),
              ),
            ),
    );
  }

  /// Race time from lights out, e.g. `-0:15`, `23:41`, `1:02:09`.
  static String _raceClock(double seconds) {
    final sign = seconds < 0 ? '-' : '';
    final total = seconds.abs().floor();
    final h = total ~/ 3600, m = (total ~/ 60) % 60, s = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$sign$h:${two(m)}:${two(s)}' : '$sign$m:${two(s)}';
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.playing,
    required this.speed,
    required this.lap,
    required this.lapCount,
    required this.clock,
    required this.time,
    required this.start,
    required this.end,
    this.buffering = false,
    this.onPlay,
    this.onSpeed,
    this.onSeek,
  });

  final bool playing;
  final bool buffering;
  final double speed;
  final int lap;
  final int lapCount;
  final String clock;
  final double time;
  final double start;
  final double end;
  final VoidCallback? onPlay;
  final VoidCallback? onSpeed;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Outlined(
          tooltip: playing ? 'Pause' : 'Play',
          onTap: onPlay,
          width: 34,
          child: Icon(
            playing ? Icons.pause : Icons.play_arrow,
            size: 18,
            color: onPlay == null ? Hud.faint : Hud.text,
          ),
        ),
        const SizedBox(width: 8),
        _Outlined(
          tooltip: 'Playback speed',
          onTap: onSpeed,
          child: Text(
            '${speed.toStringAsFixed(0)}×',
            style: Hud.figures(12, color: Hud.muted),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 104,
          child: Text.rich(
            TextSpan(
              children: lap == 0
                  ? [const TextSpan(text: 'FORMATION')]
                  : [
                      const TextSpan(text: 'LAP '),
                      TextSpan(
                        text: '$lap',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: ' / $lapCount',
                        style: const TextStyle(color: Hud.muted),
                      ),
                    ],
            ),
            style: Hud.figures(12.5, weight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: Hud.text,
              inactiveTrackColor: const Color(0xFF2A2C31),
              thumbColor: Hud.text,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              trackShape: const RectangularSliderTrackShape(),
            ),
            child: Slider(
              min: start,
              max: end,
              value: time.clamp(start, end),
              onChanged: onSeek,
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (buffering)
          const Padding(
            padding: EdgeInsets.only(right: 10),
            child: SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
        Text(clock, style: Hud.figures(12.5, color: Hud.muted)),
      ],
    );
  }
}

class _Outlined extends StatelessWidget {
  const _Outlined({
    required this.child,
    required this.onTap,
    required this.tooltip,
    this.width,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String tooltip;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: const BorderSide(color: Hud.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            height: 32,
            width: width,
            padding: width == null
                ? const EdgeInsets.symmetric(horizontal: 10)
                : null,
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}
