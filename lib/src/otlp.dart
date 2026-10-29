import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'options.dart';

/// Sends one OTLP/HTTP JSON request and returns the status code. Injectable for tests.
typedef Transport = Future<int> Function(Uri url, Map<String, String> headers, String body);

final _rng = Random.secure();
String randomHex(int bytes) =>
    List.generate(bytes, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

const _spanKey = #wtSpan;

/// The span active in the current zone, if any.
Span? get currentSpan => Zone.current[_spanKey] as Span?;

class Span {
  Span(this.name, {this.parent, Map<String, Object?>? attributes, this.onEnd})
      : traceId = parent?.traceId ?? randomHex(16),
        spanId = randomHex(8),
        start = DateTime.now().toUtc(),
        attributes = {...?attributes};

  final String name;
  final Span? parent;
  final String traceId;
  final String spanId;
  final DateTime start;
  final Map<String, Object?> attributes;
  final void Function(Span)? onEnd;
  DateTime? end;
  bool error = false;

  String get traceparent => '00-$traceId-$spanId-01';

  void recordError(Object e) {
    error = true;
    attributes['exception.type'] = e.runtimeType.toString();
    attributes['exception.message'] = e.toString();
  }

  void finish() {
    if (end != null) return;
    end = DateTime.now().toUtc();
    onEnd?.call(this);
  }

  /// Runs [body] with this span current; ends it afterwards and records thrown errors.
  Future<T> run<T>(Future<T> Function() body) async {
    try {
      return await Zone.current.fork(zoneValues: {_spanKey: this}).run(body);
    } catch (e) {
      recordError(e);
      rethrow;
    } finally {
      finish();
    }
  }
}

String _nano(DateTime t) => (t.microsecondsSinceEpoch * 1000).toString();

Map<String, Object?> _value(Object v) {
  if (v is bool) return {'boolValue': v};
  if (v is int) return {'intValue': v.toString()};
  if (v is double) return {'doubleValue': v};
  return {'stringValue': v.toString()};
}

List<Map<String, Object?>> encodeAttrs(Map<String, Object?> attrs, [RedactHook? redact]) {
  final out = <Map<String, Object?>>[];
  for (final e in safeAttributes(attrs).entries) {
    final v = redact == null ? e.value : redact(e.key, e.value);
    if (v != null) out.add({'key': e.key, 'value': _value(v)});
  }
  return out;
}

Map<String, Object?> _envelope(
        String root, String scopeKey, String itemsKey, WatchtowerOptions o, List<Object?> items) =>
    {
      root: [
        {
          'resource': {
            'attributes': encodeAttrs({
              'service.name': o.service,
              'telemetry.sdk.name': 'watchtower-dart',
              'telemetry.sdk.version': sdkVersion,
              if (o.environment != null) 'deployment.environment.name': o.environment,
              if (o.release != null) 'service.version': o.release,
              ...o.resource,
            }),
          },
          scopeKey: [
            {
              'scope': {'name': 'watchtower-dart', 'version': sdkVersion},
              itemsKey: items,
            }
          ],
        }
      ],
    };

Map<String, Object?> encodeSpans(WatchtowerOptions o, List<Span> spans) =>
    _envelope('resourceSpans', 'scopeSpans', 'spans', o, [
      for (final s in spans)
        {
          'traceId': s.traceId,
          'spanId': s.spanId,
          if (s.parent != null) 'parentSpanId': s.parent!.spanId,
          'name': s.name,
          'kind': 1,
          'startTimeUnixNano': _nano(s.start),
          'endTimeUnixNano': _nano(s.end ?? s.start),
          'attributes': encodeAttrs(s.attributes, o.redact),
          if (s.error) 'status': {'code': 2, 'message': s.attributes['exception.message']?.toString() ?? ''},
        }
    ]);

class LogEntry {
  LogEntry(this.body, this.severity, this.attributes, {this.traceId, this.spanId})
      : time = DateTime.now().toUtc();
  final String body;
  final int severity;
  final Map<String, Object?> attributes;
  final String? traceId;
  final String? spanId;
  final DateTime time;
}

Map<String, Object?> encodeLogs(WatchtowerOptions o, List<LogEntry> logs) =>
    _envelope('resourceLogs', 'scopeLogs', 'logRecords', o, [
      for (final l in logs)
        {
          'timeUnixNano': _nano(l.time),
          'severityNumber': l.severity,
          'severityText': l.severity >= 17 ? 'ERROR' : 'INFO',
          'body': {'stringValue': l.body},
          'attributes': encodeAttrs(l.attributes, o.redact),
          if (l.traceId != null) 'traceId': l.traceId,
          if (l.spanId != null) 'spanId': l.spanId,
        }
    ]);

/// Posts batches; a batch that fails transiently stays queued (bounded) and is retried on the next flush.
class Exporter {
  Exporter(this.options, this.transport);
  final WatchtowerOptions options;
  final Transport transport;
  final _pending = <(String, String)>[]; // (path, body)
  bool _flushing = false;

  int get pending => _pending.length;

  Future<void> send(String path, Map<String, Object?> payload) {
    _pending.add((path, jsonEncode(payload)));
    while (_pending.length > options.maxBatches) {
      _pending.removeAt(0);
    }
    return flush();
  }

  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      while (_pending.isNotEmpty) {
        final (path, body) = _pending.first;
        try {
          final code = await transport(
            Uri.parse('${options.endpoint}$path'),
            {'Authorization': 'Bearer ${options.publishableKey}', 'Content-Type': 'application/json'},
            body,
          );
          // Other 4xx will never succeed: drop rather than retry forever.
          if (code >= 500 || code == 408 || code == 429) return;
        } catch (_) {
          return;
        }
        if (_pending.isNotEmpty) _pending.removeAt(0);
      }
    } finally {
      _flushing = false;
    }
  }
}
