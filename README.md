# f1_scene

Replays of Formula 1 races (2023 onward) on 3D circuit dioramas, built with
[flutter_scene](https://pub.dev/packages/flutter_scene) as a playground for
exploring it. Runs on the web, macOS, iOS and Android.

> Unofficial fan project, not affiliated with Formula 1. See [NOTICE.md](NOTICE.md).

## Status

| Milestone | Scope | |
| --- | --- | --- |
| 1 | Circuit dioramas: real width and elevation, sectors, orbit camera | done |
| 2 | Races from [OpenF1](https://openf1.org), cars moving on a scrubbable timeline | done |
| 3 | Cars riding the track, pit lane, car model, chase and TV cameras | done |
| 4 | Timing tower, driver card with sectors, DRS zones, kerbs | done |
| 5 | Terrain, buildings, roads, water and trees; GitHub Pages build | done |

31 circuits are included, covering every venue on the 2023–2025 calendars.
Of 2026's new or returning venues, Madrid and Sepang are not selectable yet:
their layouts exist upstream but without start/finish and sector markers.

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
  geometry/   Map projection, arc-length spline, track mesh, alignment (pure Dart)
  race/       OpenF1 client, race data, position timeline, playback
  scene/      flutter_scene setup: diorama, cars, lights, camera
  ui/         The screen and its overlay
tool/         Data vendoring and alignment check scripts
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
- **Race data.** OpenF1 positions (~3.7 Hz per car) arrive in OpenF1's own
  circuit frame. One clean lap is fitted onto the centerline with a trimmed,
  scaled ICP (rotation, scale, translation, mirroring), which lands within
  2–5 m RMS on every venue from 2023 to 2025 (`dart run
  tool/check_alignment.dart 2024`). Positions stream in 5-minute chunks around
  the playhead, within OpenF1's free rate limits, and playback waits while a
  chunk loads.
- **Car motion.** Each position sample is expressed along the circuit (or the
  pit lane) and interpolated there with a monotone Hermite curve, so cars
  follow corners instead of cutting the chords between samples ~20 m apart,
  keep a steady speed, and stay inside the track edges despite alignment
  error. The pit lane is traced from one typical pit stop's positions.
- **Timing.** The tower and driver card replay OpenF1's positions, intervals,
  stints and lap/sector times at the playhead; sectors are rated purple
  (fastest of anyone), green (personal best) or yellow against the bests set
  so far.
- **Track details.** Kerbs follow curvature (inside every corner, outside
  the exit of tight ones). DRS zones are derived from where cars had DRS open
  over a few mid-race minutes (none in 2026, which replaced DRS).
- **Scenery.** Terrain, buildings, roads, water and woods come from
  OpenStreetMap via F1TrackViewer's generated environments, fetched at
  runtime. The terrain is cut down and built up around the track so the
  ribbon always sits on it, buildings are extruded footprints, and trees are
  instanced in woodland. The landscape button falls back to the plain slab.
- **Cars and cameras.** The car is a low-poly 2026-proportioned model built
  in code (body in the team colour). Besides the orbit view, a chase camera
  turns with the followed car, and a TV mode cuts between trackside posts on
  the outside of corners, zooming to keep the car framed.

## Deploying

[`.github/workflows/pages.yml`](.github/workflows/pages.yml) analyzes,
tests, builds the web app and publishes it to GitHub Pages on every push to
`main`. One-time setup in the repository: **Settings → Pages → Build and
deployment → Source: GitHub Actions**. The site is served under
`/<repository>/`, which the build's `--base-href` matches.

## Data

Circuit data is vendored under `assets/circuits/` from pinned upstream commits.
To refresh it:

```sh
dart run tool/fetch_circuits.dart
```

Sources and licenses are listed in [NOTICE.md](NOTICE.md). Race data
(OpenF1) and scenery (OpenStreetMap, via F1TrackViewer) are fetched at
runtime and held in memory, never committed to this repo.

## License

MIT for the code. Vendored data keeps its upstream licenses, see
[NOTICE.md](NOTICE.md).
