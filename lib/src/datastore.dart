import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show RootIsolateToken;

import 'client.dart';
import 'otlp.dart';

final _op = RegExp(r'^\s*(?:with\b[\s\S]*?\)\s*)?([a-z]+)', caseSensitive: false);
final _target = RegExp(r'''\b(?:from|into|update|join|table)\s+((?:"[^"]+"|`[^`]+`|\[[^\]]+\]|[\w$]+)(?:\.(?:"[^"]+"|[\w$]+))?)''',
    caseSensitive: false);

/// Client storage instrumentation for sqflite, drift, Hive, Isar and other embedded stores. Only
/// slow or failed operations are exported, as spans with OTel `db.*` attributes; statement text,
/// values and error messages are never recorded (sqflite errors quote the SQL and its arguments).
///
/// Synchronous work on the UI (root) isolate blocks frames: [measureSync] judges it against one
/// frame (16 ms) and flags `db.main_thread`. sqflite runs SQL on a native thread, so its awaited
/// calls go through [measure]; Hive and Isar `*Sync` calls and drift without a background isolate
/// are the usual jank sources.
///
/// ```dart
/// final rows = await WatchtowerDb.sql('sqlite', 'SELECT * FROM todos', () => db.rawQuery('SELECT * FROM todos'));
/// final v = WatchtowerDb.measureSync('hive', 'get', () => box.get('k'), collection: box.name);
/// ```
/// drift: call [sql] from a `QueryInterceptor` (`runSelect`, `runInsert`, `runUpdate`, `runDelete`,
/// `runCustom`) installed with `executor.interceptWith(...)`.
class WatchtowerDb {
  WatchtowerDb._();

  /// Async operations at or over this many ms are exported (default 100).
  static double slowMs = 100;
  static const frameMs = 16.0;

  /// True on the root (UI) isolate; on the web everything shares the UI thread. Tests replace it.
  static bool Function() isMainIsolate = () => kIsWeb || RootIsolateToken.instance != null;

  /// `SELECT users`-style parts (same rules as the other SDKs): never values or the statement text.
  static ({String operation, String? collection}) querySummary(String? sql) {
    final s = sql ?? '';
    final t = _target.firstMatch(s)?.group(1)?.replaceAll(RegExp(r'["`\[\]]'), '');
    return (operation: _op.firstMatch(s)?.group(1)?.toUpperCase() ?? 'QUERY', collection: t);
  }

  static Span? _start(String system, String operation, String? collection, String? namespace, bool main) {
    final w = Watchtower.instance;
    if (w == null) return null;
    final summary = [operation, if (collection != null) collection].join(' ');
    // started now so its times are right; only finished (and so exported) when slow or failed
    return w.startSpan(summary, attributes: {
      'db.system.name': system,
      'db.operation.name': operation,
      'db.query.summary': summary,
      if (collection != null) 'db.collection.name': collection,
      if (namespace != null) 'db.namespace': namespace,
      if (main) 'db.main_thread': true,
    });
  }

  static void _end(Span? span, Stopwatch sw, bool main, Object? error) {
    if (span == null) return;
    final limit = main ? (slowMs < frameMs ? slowMs : frameMs) : slowMs;
    if (error == null && sw.elapsedMicroseconds < limit * 1000) return;
    if (error != null) {
      span.error = true;
      span.attributes['error.type'] = error.runtimeType.toString();
    }
    span.finish();
  }

  /// Times an async [body]; its duration includes waiting, so it is never judged as UI-thread work.
  static Future<T> measure<T>(String system, String operation, Future<T> Function() body,
      {String? collection, String? namespace}) async {
    final span = _start(system, operation, collection, namespace, false);
    final sw = Stopwatch()..start();
    try {
      final r = await body();
      _end(span, sw, false, null);
      return r;
    } catch (e) {
      _end(span, sw, false, e);
      rethrow;
    }
  }

  /// Times a synchronous [body] (Hive, Isar `*Sync`, drift on the UI isolate).
  static T measureSync<T>(String system, String operation, T Function() body, {String? collection, String? namespace}) {
    final main = isMainIsolate();
    final span = _start(system, operation, collection, namespace, main);
    final sw = Stopwatch()..start();
    try {
      final r = body();
      _end(span, sw, main, null);
      return r;
    } catch (e) {
      _end(span, sw, main, e);
      rethrow;
    }
  }

  /// [measure] with the operation and first table taken from [sql] (the text itself is not kept).
  static Future<T> sql<T>(String system, String sql, Future<T> Function() body, {String? namespace}) {
    final q = querySummary(sql);
    return measure(system, q.operation, body, collection: q.collection, namespace: namespace);
  }

  /// A store's on-disk size (e.g. `File(path).lengthSync()`), sent as one log record with
  /// `event.name: wt.embedded.file_size`. Call it at launch, not per operation.
  static Future<void> recordStoreSize(String system, int bytes, {String? namespace, int? walBytes}) async {
    await Watchtower.instance?.captureMessage('wt.embedded.file_size', attributes: {
      'event.name': 'wt.embedded.file_size',
      'db.system.name': system,
      if (namespace != null) 'db.namespace': namespace,
      'db.file.size': bytes,
      if (walBytes != null) 'db.wal.size': walBytes,
    });
  }
}
