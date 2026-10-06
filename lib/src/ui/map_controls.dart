import 'package:flutter/material.dart';

import '../scene/track_scene.dart';
import 'hud_style.dart';

/// The camera choice and the view toggles, top right over the map.
class MapControls extends StatelessWidget {
  const MapControls({
    super.key,
    required this.mode,
    required this.hasRace,
    required this.onMode,
    required this.scenery,
    required this.onScenery,
    required this.onRecenter,
  });

  final CameraMode mode;

  /// The driver cameras need a race to follow.
  final bool hasRace;
  final ValueChanged<CameraMode> onMode;
  final bool scenery;
  final VoidCallback onScenery;
  final VoidCallback onRecenter;

  static const _cameras = [
    (CameraMode.orbit, 'Overview'),
    (CameraMode.chase, 'Follow'),
    (CameraMode.onboard, 'Onboard'),
    (CameraMode.tv, 'TV'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        _Group([
          for (final (value, label) in _cameras)
            _Segment(
              label: label,
              selected: mode == value,
              onTap: value == CameraMode.orbit || hasRace
                  ? () => onMode(value)
                  : null,
            ),
        ]),
        _Group([
          _Segment(label: 'Terrain', selected: scenery, onTap: onScenery),
          _Segment(label: 'Recenter', onTap: onRecenter),
        ]),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Hud.control,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Hud.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, this.selected = false, this.onTap});

  final String label;
  final bool selected;

  /// Null disables it.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Hud.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: onTap == null
                  ? Hud.faint
                  : selected
                  ? Hud.text
                  : Hud.muted,
            ),
          ),
        ),
      ),
    );
  }
}
