import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  test('feedbackBody trims, cuts and links only a valid event id', () {
    expect(feedbackBody('  broken  ', name: ' Ann ', email: '', eventId: '0A1B2C3D-0000-4000-8000-00000000000F'),
        {'message': 'broken', 'event_id': '0a1b2c3d00004000800000000000000f', 'name': 'Ann'});
    expect(feedbackBody('   '), isNull);
    expect(feedbackBody('x', eventId: 'nope')!.containsKey('event_id'), isFalse);
    expect(feedbackBody('a' * 5000)!['message'], hasLength(4096));
  });

  test('feedback posts JSON with the key and reports the outcome', () async {
    final w = Watchtower.init(opts(), transport: transport, installHooks: false);
    status = 202;
    expect(await w.feedback('it broke', email: 'a@b.example'), isTrue);
    expect(sent.single.url.toString(), 'https://ingest.example/v1/rum/feedback');
    expect(sent.single.headers['Authorization'], 'Bearer wtp_secretvalue123');
    expect(sent.single.body, {'message': 'it broke', 'email': 'a@b.example'});
    expect(await w.feedback('  '), isFalse);
    status = 429;
    expect(await w.feedback('again'), isFalse);
  });

  test('an app id rides on every request so the edge accepts the key without an Origin', () async {
    final o = WatchtowerOptions(publishableKey: 'wtp_secretvalue123', endpoint: 'https://ingest.example', appId: 'com.example.app');
    final w = Watchtower.init(o, transport: transport, installHooks: false);
    status = 202;
    expect(await w.feedback('hi'), isTrue);
    expect(sent.single.headers['X-Watchtower-App-Id'], 'com.example.app');
    expect(sent.single.headers.containsKey('Origin'), isFalse);
    expect(opts().headers.containsKey('X-Watchtower-App-Id'), isFalse);
  });

  test('the native crash-loop guard comes from the plugin, started with the client', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('dev.watchtower/native');
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      return {'launchCrashCount': 3, 'isCrashLooping': true};
    });
    final w = Watchtower.init(
        WatchtowerOptions(publishableKey: 'wtp_secretvalue123', service: 'app', crashLoopThreshold: 3),
        transport: transport, installHooks: false);
    final st = await w.crashLoop();
    expect(st.launchCrashCount, 3);
    expect(st.isCrashLooping, isTrue);
    final args = calls.single.arguments as Map;
    expect(calls.single.method, 'start');
    expect(args['crashLoopThreshold'], 3);
    expect(args['key'], 'wtp_secretvalue123');
    // without the plugin (or with it turned off) there is no loop and nothing throws
    messenger.setMockMethodCallHandler(channel, null);
    expect((await Watchtower.init(opts(), transport: transport, installHooks: false).crashLoop()).isCrashLooping, isFalse);
    final off = WatchtowerOptions(publishableKey: 'wtp_secretvalue123', nativeCrashes: false);
    expect((await Watchtower.init(off, transport: transport, installHooks: false).crashLoop()).launchCrashCount, 0);
    expect(calls, hasLength(1));
  });

  test('the app id defaults to what the plugin reports, and early sends wait for it', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('dev.watchtower/native');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (c) async {
      await Future<void>.delayed(const Duration(milliseconds: 20)); // answers after the first send
      return {'launchCrashCount': 0, 'isCrashLooping': false, 'appId': 'com.example.shop'};
    });
    final w = Watchtower.init(opts(), transport: transport, installHooks: false);
    await w.captureMessage('early');
    expect(sent.single.headers['X-Watchtower-App-Id'], 'com.example.shop');
    status = 202;
    expect(await w.feedback('hi'), isTrue);
    expect(sent.last.headers['X-Watchtower-App-Id'], 'com.example.shop');
    // an explicit appId wins over the plugin's
    final o = WatchtowerOptions(publishableKey: 'wtp_secretvalue123', endpoint: 'https://ingest.example', appId: 'com.override');
    await Watchtower.init(o, transport: transport, installHooks: false).captureMessage('x');
    expect(sent.last.headers['X-Watchtower-App-Id'], 'com.override');
    messenger.setMockMethodCallHandler(channel, null);
  });
}
