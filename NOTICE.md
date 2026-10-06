# Third-party data and notices

The f1_scene source code is MIT-licensed (see [LICENSE](LICENSE)). The circuit
data under [`assets/circuits/`](assets/circuits) is vendored from the projects
below by [`tool/fetch_circuits.dart`](tool/fetch_circuits.dart), at the commits
recorded in [`assets/circuits/index.json`](assets/circuits/index.json). Each
folder keeps its upstream license.

| Folder | Content | Source | License |
| --- | --- | --- | --- |
| `layouts/` | Circuit centerlines (GeoJSON) | [bacinger/f1-circuits](https://github.com/bacinger/f1-circuits) | MIT |
| `elevations/` | Elevation per centerline point | [Makakashan/F1TrackViewer](https://github.com/Makakashan/F1TrackViewer), generated from [OpenTopoData](https://www.opentopodata.org/) (Mapzen dataset) and [Open-Meteo](https://open-meteo.com/en/docs/elevation-api) | MIT; underlying elevation data CC-BY 4.0 |
| `markers/` | Start/finish and sector splits | [Makakashan/F1TrackViewer](https://github.com/Makakashan/F1TrackViewer), derived from session telemetry via [FastF1](https://github.com/theOehrly/Fast-F1) | MIT |
| `widths/` | Track width profiles | [Makakashan/F1TrackViewer](https://github.com/Makakashan/F1TrackViewer), derived from [TUMFTM/racetrack-database](https://github.com/TUMFTM/racetrack-database) | [LGPL-3.0](https://www.gnu.org/licenses/lgpl-3.0.html) |
| `index.json` | Circuit names and countries | [Makakashan/F1TrackViewer](https://github.com/Makakashan/F1TrackViewer) | MIT |

## Race data

Race timing and car positions are fetched at runtime from
[OpenF1](https://openf1.org) (CC BY-NC-SA 4.0) and are not redistributed in
this repository.

## Trademarks

f1_scene is an unofficial fan project. It is not affiliated with, endorsed by,
or sponsored by Formula 1, Formula One Licensing B.V., the FIA, or any team.
F1, FORMULA ONE and related marks are trademarks of Formula One Licensing B.V.,
used here only to identify the subject matter.
