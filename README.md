# f1_scene

Formula 1 circuits as 3D dioramas, built with
[flutter_scene](https://pub.dev/packages/flutter_scene). The goal is to replay
historical races (2023 onward) with all cars on track, as a playground for
exploring flutter_scene. Runs on the web, macOS, iOS and Android.

> Unofficial fan project, not affiliated with Formula 1. See [NOTICE.md](NOTICE.md).

## Status

| Milestone | Scope | |
| --- | --- | --- |
| 1 | Circuit dioramas: real width and elevation, sectors, orbit camera | done |
| 2 | Load a race from [OpenF1](https://openf1.org), cars moving on a timeline | next |
| 3 | Cars snapped to the track by lap distance, pit lane, car model, follow and TV cameras | |
| 4 | HUD: timing tower, sectors, DRS zones, kerbs | |
| 5 | Terrain, buildings, GitHub Pages build | |

31 circuits are included, covering every venue on the 2023–2025 calendars.

## Running

Requires Flutter 3.47 or newer (stable).

```sh
flutter pub get
flutter run -d chrome      # web, the primary target
flutter run -d macos       # native; Flutter GPU is enabled in the platform files
```

```sh
flutter test               # geometry tests run against all 31 circuits
```

## How it works

```
lib/src/
  data/       Circuit model and asset loading
  geometry/   Map projection, arc-length spline, track mesh building (pure Dart)
  scene/      flutter_scene setup: diorama, lights, camera
  ui/         The screen and its overlay
tool/         Data vendoring script
```

- **Centerline.** Each circuit's GeoJSON outline is projected to local meters
  and turned into a closed centripetal Catmull-Rom spline, addressed by `s`,
  the fraction of the lap from the first point. Width samples, sector splits
  and, later, car positions all map onto `s`.
- **Track mesh.** The spline is sampled every ~2 m into cross-sections with the
  measured width (12 m where none is published). The coarse source outlines
  over-tighten a few hairpins, so the inside edge of any corner tighter than
  the half-width is pulled in to keep the surface from folding over.
- **Look.** A dark slab, an extruded ribbon tinted by sector, elevation or
  plain asphalt, ACES tone mapping, bloom and ambient occlusion.

## Data

Circuit data is vendored under `assets/circuits/` from pinned upstream commits.
To refresh it:

```sh
dart run tool/fetch_circuits.dart
```

Sources and licenses are listed in [NOTICE.md](NOTICE.md). Race data will be
fetched at runtime and cached on the device, never committed to this repo.

## License

MIT for the code. Vendored data keeps its upstream licenses, see
[NOTICE.md](NOTICE.md).
