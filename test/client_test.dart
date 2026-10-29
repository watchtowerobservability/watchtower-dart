import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchtower/watchtower.dart';

class Sent {
  Sent(this.url, this.headers, this.body);
  final Uri url;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
}

WatchtowerOptions opts({RedactHook? redact}) => WatchtowerOptions(
    publishableKey: 'wtp_secretvalue123', endpoint: 'https://ingest.example/', service: 'app', release: '1.2.3', redact: redact);

void main() {
  late List<Sent> sent;
  late int status;
  Future<int> transport(Uri u, Map<String, String> h, String b) async {
    sent.add(Sent(u, h, jsonDecode(b) as Map<String, dynamic>));
    return status;
  }

  setUp(() {
    sent = [];
    status = 200;
  });
  tearDown(() => Watchtower.instance?.shutdown());

  test('options mask the key and refuse secret keys', () {
    expect(opts().toString(), isNot(contains('secretvalue')));
    expect(opts().toString(), contains('wtp_****'));
    expect(() => WatchtowerOptions(publishableKey: 'wti_abc12345'), throwsArgumentError);
    expect(() => WatchtowerOptions(publishableKey: ''), throwsArgumentError);
    expect(opts().endpoint, 'https://ingest.example');
  });

  test('captureException posts a log with bearer key, trace ids and no wt.* attributes', () async {
    final w = Watchtower.init(opts(), transport: transport, installHooks: false);
    await w.trace('work', () async {
      await w.captureException(StateError('boom'), stack: StackTrace.current, attributes: {'wt.tenant': 'x', 'k': 'v'});
    });
    final s = sent.single;
    expect(s.url.toString(), 'https://ingest.example/v1/logs');
    expect(s.headers['Authorization'], 'Bearer wtp_secretvalue123');
    final rec = s.body['resourceLogs'][0]['scopeLogs'][0]['logRecords'][0] as Map<String, dynamic>;
    expect(rec['traceId'], hasLength(32));
    expect(rec['spanId'], hasLength(16));
    final keys = (rec['attributes'] as List).map((a) => a['key']).toList();
    expect(keys, containsAll(['exception.type', 'exception.stacktrace', 'k']));
    expect(keys.any((k) => k.toString().startsWith('wt.')), isFalse);
  });

  test('FlutterError.onError is captured and the previous handler still runs', () async {
    var prevCalled = false;
    final original = FlutterError.onError;
    FlutterError.onError = (_) => prevCalled = true;
    final w = Watchtower.init(opts(), transport: transport);
    FlutterError.onError!(FlutterErrorDetails(exception: Exception('widget'), library: 'widgets'));
    await Future<void>.delayed(Duration.zero);
    expect(prevCalled, isTrue);
    expect(sent.single.url.path, '/v1/logs');
    w.shutdown();
    FlutterError.onError = original;
  });

  test('redact hook can drop and rewrite attributes', () async {
    final w = Watchtower.init(opts(redact: (k, v) => k == 'email' ? null : (k == 'card' ? '***' : v)),
        transport: transport, installHooks: false);
    await w.captureMessage('hi', attributes: {'email': 'a@b.c', 'card': '4242'});
    final attrs = sent.single.body['resourceLogs'][0]['scopeLogs'][0]['logRecords'][0]['attributes'] as List;
    expect(attrs.map((a) => a['key']), ['card']);
    expect(attrs.single['value']['stringValue'], '***');
  });

  test('failed batches are kept and retried on flush', () async {
    final w = Watchtower.init(opts(), transport: transport, installHooks: false);
    status = 503;
    await w.captureMessage('one');
    expect(sent, hasLength(1));
    status = 200;
    await w.flush();
    expect(sent, hasLength(2));
    await w.flush();
    expect(sent, hasLength(2), reason: 'delivered batch is not resent');
  });

  test('buffer is bounded', () async {
    final w = Watchtower.init(
        WatchtowerOptions(publishableKey: 'wtp_secretvalue123', maxBatches: 2), transport: transport, installHooks: false);
    status = 503;
    for (var i = 0; i < 5; i++) {
      await w.captureMessage('m$i');
    }
    sent.clear();
    status = 200;
    await w.flush();
    expect(sent, hasLength(2));
  });

  test('http client traces requests and propagates traceparent only to listed hosts', () async {
    final w = Watchtower.init(opts(), transport: transport, installHooks: false);
    final seen = <http.BaseRequest>[];
    final c = WatchtowerHttpClient(MockClient((r) async {
      seen.add(r);
      return http.Response('', r.url.host == 'api.example' ? 500 : 200);
    }), ['api.example']);
    await c.get(Uri.parse('https://api.example/x?token=secret'));
    await c.get(Uri.parse('https://other.example/y'));
    expect(seen[0].headers['traceparent'], matches(RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-01$')));
    expect(seen[1].headers.containsKey('traceparent'), isFalse);
    await w.flush();
    final spans = sent.single.body['resourceSpans'][0]['scopeSpans'][0]['spans'] as List;
    expect(spans, hasLength(2));
    expect(jsonEncode(spans), isNot(contains('secret')));
    expect(spans[0]['status']['code'], 2);
  });

  test('child spans share the parent trace id', () async {
    final w = Watchtower.init(opts(), transport: transport, installHooks: false);
    await w.trace('parent', () async {
      await w.trace('child', () async {});
    });
    await w.flush();
    final spans = sent.single.body['resourceSpans'][0]['scopeSpans'][0]['spans'] as List;
    expect(spans[0]['traceId'], spans[1]['traceId']);
    expect(spans[0]['parentSpanId'], spans[1]['spanId']);
  });
}
