import 'package:flutter/material.dart';

import '../race/race_models.dart';
import '../scene/track_scene.dart';

/// Camera mode and which driver the chase and TV cameras film.
class CameraBar extends StatelessWidget {
  const CameraBar({
    super.key,
    required this.mode,
    required this.drivers,
    required this.followed,
    required this.onMode,
    required this.onFollow,
  });

  final CameraMode mode;

  /// Empty before a race loads, which disables the driver cameras.
  final List<RaceDriver> drivers;
  final int? followed;
  final ValueChanged<CameraMode> onMode;
  final ValueChanged<int> onFollow;

  @override
  Widget build(BuildContext context) {
    final hasRace = drivers.isNotEmpty;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<CameraMode>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(
              value: CameraMode.orbit,
              icon: Icon(Icons.threed_rotation),
              tooltip: 'Orbit the circuit',
            ),
            ButtonSegment(
              value: CameraMode.chase,
              icon: const Icon(Icons.directions_car_outlined),
              tooltip: 'Chase camera',
              enabled: hasRace,
            ),
            ButtonSegment(
              value: CameraMode.tv,
              icon: const Icon(Icons.videocam_outlined),
              tooltip: 'TV cameras',
              enabled: hasRace,
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) => onMode(s.first),
        ),
        DropdownMenu<int>(
          key: ValueKey('follow $followed ${drivers.length}'),
          initialSelection: followed,
          enabled: hasRace,
          width: 220,
          menuHeight: 420,
          label: const Text('Driver'),
          leadingIcon: _TeamDot(_colourOf(followed)),
          dropdownMenuEntries: [
            for (final d in drivers)
              DropdownMenuEntry(
                value: d.number,
                label: '${d.acronym}  ${d.teamName}',
                leadingIcon: _TeamDot(d.teamColour),
              ),
          ],
          onSelected: (n) {
            if (n != null) onFollow(n);
          },
        ),
      ],
    );
  }

  int? _colourOf(int? number) {
    for (final d in drivers) {
      if (d.number == number) return d.teamColour;
    }
    return null;
  }
}

class _TeamDot extends StatelessWidget {
  const _TeamDot(this.colour);

  final int? colour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colour == null ? Colors.grey : Color(0xFF000000 | colour!),
        ),
      ),
    );
  }
}
