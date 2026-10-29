import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchtower/src/tool/upload.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('wt_dart');
    File('${dir.path}/app.android-arm64.symbols').writeAsBytesSync([1, 2, 3]);
    File('${dir.path}/readme.txt').writeAsStringSync('skip');
    File('${dir.path}/map.json').writeAsStringSync('["MyWidget","aB","build","cD"]');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('converts the obfuscation map to proguard class lines', () {
    expect(obfuscationMapToProguard('["MyWidget","aB"]'), 'MyWidget -> aB:\n');
    expect(() => obfuscationMapToProguard('["odd"]'), throwsFormatException);
  });

  test('uploads symbols and map with release, gzip and bearer key', () async {
    final reqs = <http.Request>[];
    final out = StringBuffer();
    final code = await run(
      ['--api', 'https://api.example/', '--project', 'p1', '--release', '1.0', '--symbols-dir', dir.path, '--obfuscation-map', '${dir.path}/map.json'],
      {'WT_API_KEY': 'wtk_abc'},
      client: MockClient((r) async {
        reqs.add(r);
        return http.Response('{}', 201);
      }),
      out: out,
    );
    expect(code, 0);
    expect(reqs, hasLength(2));
    final sym = reqs.firstWhere((r) => r.url.queryParameters['kind'] == 'elf');
    expect(sym.url.path, '/v1/projects/p1/artifacts');
    expect(sym.url.queryParameters, {'kind': 'elf', 'name': 'app.android-arm64.symbols', 'release': '1.0'});
    expect(sym.headers['Authorization'], 'Bearer wtk_abc');
    expect(gzip.decode(sym.bodyBytes), [1, 2, 3]);
    final map = reqs.firstWhere((r) => r.url.queryParameters['kind'] == 'proguard');
    expect(utf8.decode(gzip.decode(map.bodyBytes)), contains('MyWidget -> aB:'));
    expect(out.toString(), isNot(contains('wtk_abc')));
  });

  test('refuses publishable keys and reports server failures', () async {
    final out = StringBuffer();
    expect(await run(['--api', 'https://a', '--project', 'p', '--symbols-dir', dir.path], {'WT_API_KEY': 'wtp_x'}, out: out), 2);
    final code = await run(['--api', 'https://a', '--project', 'p', '--symbols-dir', dir.path], {'WT_API_KEY': 'wtk_x'},
        client: MockClient((r) async => http.Response('', 500)), out: out);
    expect(code, 1);
  });

  test('dry run sends nothing', () async {
    final out = StringBuffer();
    final code = await run(['--api', 'https://a', '--project', 'p', '--symbols-dir', dir.path, '--dry-run'], {},
        client: MockClient((r) async => fail('no request expected')), out: out);
    expect(code, 0);
    expect(out.toString(), contains('would upload elf app.android-arm64.symbols'));
  });
}
