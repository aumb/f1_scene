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
- **Look.** A dark slab, an extruded ribbon in one light colour that stands
  out against the scenery, ACES tone mapping, bloom and ambient occlusion.
  The HUD docks a rail on the left (race picker, timing tower, followed
  driver) and gives the map everything else.
- **Race data.** OpenF1 positions (~3.7 Hz per car) arrive in OpenF1's own
  circuit frame. One clean lap is fitted onto the centerline with a trimmed,
  scaled ICP (rotation, scale, translation, mirroring), which lands within
  2–5 m RMS on every venue from 2023 to 2025 (`dart run
  tool/check_alignment.dart 2024`). Positions stream in 5-minute chunks around
  the playhead, within OpenF1's free rate limits, and playback waits while a
  chunk loads.
- **Car motion.** OpenF1 stamps each batch of positions with when it
  arrived, up to ~0.1 s off when it was taken, and every car shares the
  error; the median disagreement between each moving car and its own
  smooth motion recovers it. Each sample is then expressed along the
  circuit (or the pit lane) and the motion fitted there with a local
  quadratic over ±1.3 s, so cars follow corners instead of cutting the
  chords between samples ~20 m apart, hold a steady speed and stay inside
  the track edges despite alignment error (`dart run tool/check_motion.dart
  2024 azerbaijan` measures it). The pit lane is traced from one typical pit
  stop's positions.
- **Traffic.** OpenF1 puts every car on one shared line around the lap (cars
  at the same spot differ by ~4 cm sideways), so the data never says who is
  beside whom. Cars within reach of each other step apart across the track,
  sooner the faster they close, always in the same order so none passes
  through another, and back onto the line once clear. In the orbit view,
  where cars are drawn enlarged, each shrinks toward real size as another
  comes close, so a battle never merges into one blob.
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
  instanced in woodland. The Terrain toggle falls back to the plain slab.
- **Cars and cameras.** The car is a low-poly 2026-proportioned model built
  in code, painted in an approximation of its team's colours with its number
  on the nose and rear wing (no sponsor artwork, which is trademarked).
  Besides the Overview, the Follow camera turns with the followed car,
  Onboard rides on its airbox, and TV cuts between trackside posts on
  the outside of corners, zooming to keep the car framed. With scenery, each
  post is placed where sight lines to the approach it films clear the
  buildings and terrain, and the camera only cuts to posts that can see the
  car.

## Controls

The orbit camera behaves like a map: the ground follows the pointer and
zooming heads for whatever is under the cursor.

| | Rotate | Pan | Zoom |
|---|---|---|---|
| Mouse | left drag | right or middle drag, shift + drag | wheel |
| Trackpad | click + drag (twist in desktop builds) | two-finger swipe | pinch |
| Touch | one finger | two fingers | pinch |

Add `?stats` to the URL (or press **F**) for an FPS and frame-time overlay.

The 3D view's cost is mostly per pixel, so on a large or high-density screen
it renders below full resolution: it starts within a pixel budget for the
window and then adapts, dropping resolution while frames miss the display's
refresh and climbing back once they don't. `?scale=0.75` (or any value up
to 1) fixes the scale instead.

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
runtime by each visitor's browser, never committed to this repo.

OpenF1's free tier allows 30 requests a minute per visitor, so data that
can no longer change is cached on the visitor's device: races finished more
than a day ago, past seasons' calendars and the pinned scenery files (the
browser's Cache Storage on the web, the temporary directory elsewhere).
Revisiting or reloading a race costs no requests. Car positions are stored
in a compact binary form, ~220 KB per five minutes instead of ~3 MB of
JSON.

## License

MIT for the code. Vendored data keeps its upstream licenses, see
[NOTICE.md](NOTICE.md).
