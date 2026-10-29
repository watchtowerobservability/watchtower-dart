import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Converts a Flutter `--save-obfuscation-map` JSON file ([original, obfuscated, ...]) into
/// ProGuard-style class lines (`original -> obfuscated:`), the format the symbol store parses.
String obfuscationMapToProguard(String json) {
  final list = jsonDecode(json);
  if (list is! List || list.length.isOdd) throw FormatException('not a Dart obfuscation map');
  final b = StringBuffer();
  for (var i = 0; i < list.length; i += 2) {
    b.writeln('${list[i]} -> ${list[i + 1]}:');
  }
  return b.toString();
}

class Artifact {
  Artifact(this.kind, this.name, this.bytes);
  final String kind;
  final String name;
  final List<int> bytes;
}

/// `*.symbols` files from `flutter build --split-debug-info=<dir>` (ELF, all platforms) plus the
/// optional obfuscation map.
List<Artifact> collect(String symbolsDir, String? obfuscationMap) {
  final out = <Artifact>[];
  final dir = Directory(symbolsDir);
  if (dir.existsSync()) {
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.symbols')) {
        out.add(Artifact('elf', f.uri.pathSegments.last, f.readAsBytesSync()));
      }
    }
  }
  if (obfuscationMap != null) {
    out.add(Artifact('proguard', 'obfuscation.map', utf8.encode(obfuscationMapToProguard(File(obfuscationMap).readAsStringSync()))));
  }
  return out;
}

/// Uploads one artifact the same way `wtctl` and the browser plugins do. Returns the HTTP status.
Future<int> uploadArtifact(http.Client c, String api, String project, String key, String? release, Artifact a) async {
  final q = {'kind': a.kind, 'name': a.name, if (release != null && release.isNotEmpty) 'release': release};
  final base = Uri.parse('${api.replaceAll(RegExp(r'/+$'), '')}/v1/projects/${Uri.encodeComponent(project)}/artifacts');
  final res = await c.post(
    base.replace(queryParameters: q),
    headers: {'Authorization': 'Bearer $key', 'Content-Type': 'application/octet-stream', 'Content-Encoding': 'gzip'},
    body: gzip.encode(a.bytes),
  );
  return res.statusCode;
}

const usage = '''
dart run watchtower:upload_symbols --project <id> [options]

  --api <url>              Watchtower API (default \$WT_API_URL, else \$WT_OTLP_ENDPOINT)
  --project <id>           project id (default \$WT_PROJECT_ID)
  --release <version>      release the symbols belong to (default \$WT_RELEASE)
  --symbols-dir <dir>      --split-debug-info output (default build/symbols)
  --obfuscation-map <file> --extra-gen-snapshot-options=--save-obfuscation-map=<file> output
  --dry-run                list what would be uploaded
Secret API key from \$WT_API_KEY (publishable wtp_ keys are refused).
''';

/// CLI body; returns the process exit code.
Future<int> run(List<String> args, Map<String, String> env, {http.Client? client, StringSink? out}) async {
  out ??= stdout;
  final o = <String, String>{};
  var dry = false;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--dry-run') {
      dry = true;
    } else if (a.startsWith('--') && i + 1 < args.length) {
      o[a.substring(2)] = args[++i];
    } else {
      out.writeln(usage);
      return 2;
    }
  }
  final api = o['api'] ?? env['WT_API_URL'] ?? env['WT_OTLP_ENDPOINT'];
  final project = o['project'] ?? env['WT_PROJECT_ID'];
  final key = env['WT_API_KEY'] ?? '';
  if (api == null || project == null) {
    out.writeln(usage);
    return 2;
  }
  if (!dry && key.isEmpty) {
    out.writeln('WT_API_KEY (secret API key) is required');
    return 2;
  }
  if (key.startsWith('wtp_')) {
    out.writeln('refusing to upload with a publishable key; use a secret API key');
    return 2;
  }
  final List<Artifact> items;
  try {
    items = collect(o['symbols-dir'] ?? 'build/symbols', o['obfuscation-map']);
  } on FormatException catch (e) {
    out.writeln('error: ${e.message}');
    return 1;
  }
  if (items.isEmpty) {
    out.writeln('nothing to upload (no .symbols files or obfuscation map found)');
    return 1;
  }
  final c = client ?? http.Client();
  var failed = 0;
  for (final a in items) {
    if (dry) {
      out.writeln('would upload ${a.kind} ${a.name} (${a.bytes.length} bytes)');
      continue;
    }
    final code = await uploadArtifact(c, api, project, key, o['release'] ?? env['WT_RELEASE'], a);
    final ok = code >= 200 && code < 300;
    if (!ok) failed++;
    out.writeln('${ok ? 'uploaded' : 'FAILED ($code)'} ${a.kind} ${a.name}');
  }
  return failed == 0 ? 0 : 1;
}
