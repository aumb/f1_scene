import 'package:f1_scene/src/data/data_cache.dart';
import 'package:f1_scene/src/race/openf1_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  test('asks once, however often or at once something is asked for', () async {
    final api = FakeOpenF1();
    final client = OpenF1Client(
      httpClient: api.client,
      cache: DataCache(),
      rateLimits: const [],
    );
    await client.get('drivers', {'session_key': 9});
    await client.get('drivers', {'session_key': 9});
    await Future.wait([
      client.get('laps', {'session_key': 9}),
      client.get('laps', {'session_key': 9}),
    ]);
    expect(api.sent, hasLength(2));
    await client.get('stints', {'session_key': 9}, keep: Keep.nothing);
    await client.get('stints', {'session_key': 9}, keep: Keep.nothing);
    expect(api.sent, hasLength(4));
  });

  test('filters keep comparison operators in the key', () {
    expect(OpenF1Client.filterText('session_key', '9472'), 'session_key=9472');
    expect(
      OpenF1Client.filterText('date>=', '2024-03-02T15:20:00'),
      'date%3E=2024-03-02T15%3A20%3A00',
    );
    expect(OpenF1Client.filterText('date<', '2024'), 'date%3C2024');
  });
}
