import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchtower/src/http_client.dart' show resourceAttrs;
import 'package:watchtower/src/native.dart' show nativeChannel, nativeStartArgs;
import 'package:watchtower/src/navigator_observer.dart' show viewAttrs;
import 'package:watchtower/watchtower.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<Object?, Object?>> recorded;

  setUp(() {
    recorded = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(nativeChannel, (call) async {
      if (call.method == 'record') recorded.add(Map<Object?, Object?>.from(call.arguments as Map));
      if (call.method == 'start') return {'launchCrashCount': 0, 'isCrashLooping': false, 'appId': 'dev.example'};
      return null;
    });
    Watchtower.init(
      WatchtowerOptions(publishableKey: 'wtp_secretvalue123', endpoint: 'https://ingest.example/', service: 'app'),
      transport: (u, h, b) async => 200,
      installHooks: false,
    );
  });
  tearDown(() {
    Watchtower.instance?.shutdown();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(nativeChannel, null);
  });

  test('view attributes carry the previous route and its duration', () {
    expect(viewAttrs('/a', null, null), {'route': '/a', 'url': 'app://flutter//a'});
    expect(viewAttrs('/b', '/a', 1500)['previous_duration_ms'], 1500);
    expect(viewAttrs('/b', '/b', 5).containsKey('previous_route'), isFalse);
  });

  test('resource attributes drop the query and mark failures', () {
    final a = resourceAttrs(Uri.parse('https://api.example/x?token=1'), 'get', 503, 10);
    expect(a['url'], 'https://api.example/x');
    expect(a['method'], 'GET');
    expect(a['failed'], isTrue);
    expect(resourceAttrs(Uri.parse('https://api.example/x'), 'get', 200, null).containsKey('failed'), isFalse);
  });

  test('the navigator observer sends a view event through the native channel', () async {
    final o = WatchtowerNavigatorObserver();
    o.didPush(MaterialPageRoute<void>(settings: const RouteSettings(name: '/home'), builder: (_) => const SizedBox()), null);
    await Future<void>.delayed(Duration.zero);
    expect(recorded.single['type'], 'view');
    expect(recorded.single['name'], '/home');
  });

  test('the http client sends a resource event carrying the trace ids', () async {
    final c = WatchtowerHttpClient(MockClient((r) async => http.Response('ok', 200)));
    await c.get(Uri.parse('https://api.example/items?x=1'));
    await Future<void>.delayed(Duration.zero);
    final e = recorded.single;
    expect(e['type'], 'resource');
    expect((e['trace_id'] as String).length, 32);
    expect((e['attrs'] as Map)['url'], 'https://api.example/items');
  });

  test('the native start call carries the RUM options', () {
    final a = nativeStartArgs(WatchtowerOptions(
      publishableKey: 'wtp_secretvalue123',
      trackViews: false,
      hangThresholdMs: 3000,
      propagateTo: ['https://api.example'],
      profileLaunch: true,
      buildId: 'b1',
    ));
    expect(a['trackViews'], false);
    expect(a['hangThresholdMs'], 3000);
    expect(a['propagateTo'], ['https://api.example']);
    expect(a['profileLaunch'], true);
    expect(a['buildId'], 'b1');
  });

  test('captured errors also go to the native batch as RUM errors', () async {
    await Watchtower.instance!.captureException(StateError('boom'), handled: false);
    expect(recorded.single['type'], 'error');
    expect((recorded.single['attrs'] as Map)['crash.handled'], false);
  });
}
