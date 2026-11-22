import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchtower/watchtower.dart';

void main() {
  late List<Map<String, dynamic>> sent;
  Future<int> transport(Uri u, Map<String, String> h, String b) async {
    sent.add({'path': u.path, ...jsonDecode(b) as Map<String, dynamic>});
    return 200;
  }

  List spans() => [
        for (final b in sent.where((b) => b['path'] == '/v1/traces')) ...b['resourceSpans'][0]['scopeSpans'][0]['spans'] as List
      ];
  Map<String, Object?> attrs(Map s) => {
        for (final a in s['attributes'] as List) a['key'] as String: (a['value'] as Map).values.first,
      };

  setUp(() {
    sent = [];
    WatchtowerDb.slowMs = 100;
    WatchtowerDb.isMainIsolate = () => true;
    Watchtower.init(WatchtowerOptions(publishableKey: 'wtp_test_12345678', endpoint: 'https://ingest.example', service: 'app', nativeCrashes: false),
        transport: transport, installHooks: false);
  });
  tearDown(() => Watchtower.instance?.shutdown());

  test('summary keeps operation and table only', () {
    final q = WatchtowerDb.querySummary("SELECT * FROM \"todos\" WHERE title = 'secret'");
    expect(q.operation, 'SELECT');
    expect(q.collection, 'todos');
    expect(WatchtowerDb.querySummary(null).operation, 'QUERY');
  });

  test('fast ops are dropped; slow, failed and UI-isolate ones are exported without text or messages', () async {
    await WatchtowerDb.sql('sqlite', 'SELECT * FROM todos', () async => 1);
    WatchtowerDb.slowMs = 0;
    await WatchtowerDb.sql('sqlite', "INSERT INTO todos VALUES ('secret')", () async => 1, namespace: 'app.db');
    await expectLater(
        WatchtowerDb.measure('sqlite', 'DELETE', () async => throw StateError("sql 'DELETE' args [secret]"), collection: 'todos'),
        throwsStateError);
    WatchtowerDb.slowMs = 100;
    expect(WatchtowerDb.measureSync('hive', 'get', () {
      final sw = Stopwatch()..start();
      while (sw.elapsedMilliseconds < 20) {}
      return 7;
    }, collection: 'prefs'), 7);
    await Watchtower.instance!.flush();
    final s = spans();
    expect(s.map((x) => x['name']), ['INSERT todos', 'DELETE todos', 'get prefs']);
    expect(attrs(s[0]), containsPair('db.namespace', 'app.db'));
    expect(attrs(s[1]), containsPair('error.type', 'StateError'));
    expect(s[1]['status']['code'], 2);
    expect(attrs(s[2]), containsPair('db.main_thread', true));
    expect(jsonEncode(s), isNot(contains('secret')));
  });

  test('store size goes out as a log record', () async {
    await WatchtowerDb.recordStoreSize('isar', 4096, namespace: 'default.isar');
    final logs = sent.where((b) => b['path'] == '/v1/logs').toList();
    expect(jsonEncode(logs), allOf(contains('wt.embedded.file_size'), contains('default.isar'), contains('4096')));
  });
}
