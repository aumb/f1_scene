// Vendors circuit data into assets/circuits/ from pinned upstream commits.
//
//   dart run tool/fetch_circuits.dart
//
// Sources (see NOTICE.md for licenses):
// - bacinger/f1-circuits: centerline GeoJSON (MIT)
// - Makakashan/F1TrackViewer: the circuit list (index.json, from its
//   circuits-index.json), elevation profiles, sector markers (MIT) and
//   per-point track widths derived from TUMFTM/racetrack-database (LGPL-3.0)
import 'dart:convert';
import 'dart:io';

const _circuitsCommit = '394d8fbe70ef2c0b0c8d23ff7bee61fa09606055';
// Keep in step with EnvironmentRepository, which fetches the scenery from
// the same commit at runtime.
const _viewerCommit = '2bb6c9f7019f63c933bad124705053b7984a4a13';

const _circuitsBase =
    'https://raw.githubusercontent.com/bacinger/f1-circuits/$_circuitsCommit';
const _viewerBase =
    'https://raw.githubusercontent.com/Makakashan/F1TrackViewer/$_viewerCommit/public';

final _client = HttpClient();

Future<String?> _get(String url) async {
  final request = await _client.getUrl(Uri.parse(url));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode == 404) return null;
  if (response.statusCode != 200) {
    throw HttpException('${response.statusCode} for $url');
  }
  return body;
}

final _outDir = Directory('assets/circuits');

Future<void> _write(String path, String contents) async {
  final file = File('${_outDir.path}/$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
}

Future<void> main() async {
  final index = jsonDecode(
    (await _get('$_viewerBase/circuits-index.json'))!,
  ) as Map<String, dynamic>;
  final circuits = <Map<String, dynamic>>[];

  for (final entry
      in (index['circuits'] as List).cast<Map<String, dynamic>>()) {
    final id = entry['id'] as String;
    final layout = await _get('$_circuitsBase/circuits/$id.geojson');
    final elevation = await _get('$_viewerBase/elevations/$id.json');
    final markers = await _get('$_viewerBase/track-markers/$id.json');
    final width = await _get('$_viewerBase/track-widths/$id.json');
    if (layout == null || elevation == null || markers == null) {
      stderr.writeln('skip $id: missing layout, elevation or markers');
      continue;
    }

    await _write('layouts/$id.geojson', layout);
    await _write('elevations/$id.json', elevation);
    await _write('markers/$id.json', markers);
    if (width != null) await _write('widths/$id.json', width);

    circuits.add({
      'id': id,
      'name': entry['name'],
      'shortName': entry['shortName'],
      'country': entry['country'],
      'hasWidth': width != null,
    });
    stdout.writeln('ok   $id${width == null ? ' (no width profile)' : ''}');
  }

  circuits.sort(
    (a, b) => (a['shortName'] as String).compareTo(b['shortName'] as String),
  );
  await _write(
    'index.json',
    const JsonEncoder.withIndent('  ').convert({
      'sources': {
        'bacinger/f1-circuits': _circuitsCommit,
        'Makakashan/F1TrackViewer': _viewerCommit,
      },
      'circuits': circuits,
    }),
  );
  _client.close();
  stdout.writeln('${circuits.length} circuits written to ${_outDir.path}');
}
