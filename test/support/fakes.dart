import 'dart:convert';
import 'dart:typed_data';

import 'package:f1_scene/src/data/device_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A device store in memory, standing in for the browser's or the disk.
class FakeStore implements DeviceStore {
  final entries = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, Uint8List bytes) async => entries[key] = bytes;
}

/// OpenF1 in memory: one Bahrain race ending at [raceEnd], a few position
/// samples, and one driver for anything else. Records what was asked.
class FakeOpenF1 {
  FakeOpenF1({DateTime? raceEnd})
    : raceEnd = raceEnd ?? DateTime.utc(2024, 3, 2, 17);

  final DateTime raceEnd;

  /// Every request sent, in order.
  final sent = <Uri>[];

  late final http.Client client = MockClient((request) async {
    sent.add(request.url);
    final rows = switch (request.url.pathSegments.last) {
      'sessions' => [
        {
          'session_key': 9,
          'meeting_key': 1,
          'circuit_key': 3,
          'year': raceEnd.year,
          'country_name': 'Bahrain',
          'date_start': raceEnd
              .subtract(const Duration(hours: 2))
              .toIso8601String(),
          'date_end': raceEnd.toIso8601String(),
        },
      ],
      'meetings' => [
        {'meeting_key': 1, 'meeting_name': 'Bahrain Grand Prix'},
      ],
      'location' => [
        for (var i = 0; i < 4; i++)
          {
            'driver_number': 1 + i % 2,
            'date': '2024-03-02T15:20:0$i.250000+00:00',
            'x': 100 + i,
            'y': -50 - i,
          },
      ],
      _ => [
        {'driver_number': 1, 'name_acronym': 'VER'},
      ],
    };
    return http.Response(jsonEncode(rows), 200);
  });
}
