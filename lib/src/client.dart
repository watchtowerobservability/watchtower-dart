import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'options.dart';
import 'otlp.dart';

Future<int> _httpTransport(Uri url, Map<String, String> headers, String body) async =>
    (await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: 10))).statusCode;

class Watchtower {
  Watchtower._(this.options, Transport transport) : _exporter = Exporter(options, transport);

  /// The client created by [init], once there is one.
  static Watchtower? instance;

  final WatchtowerOptions options;
  final Exporter _exporter;
  final _spans = <Span>[];
  Timer? _timer;
  FlutterExceptionHandler? _prevFlutter;
  bool Function(Object, StackTrace)? _prevPlatform;
  bool _hooked = false;

  /// Name of the route shown now (set by [WatchtowerNavigatorObserver]); attached to errors.
  String? currentRoute;

  /// Creates the client and, with [installHooks], chains `FlutterError.onError` and
  /// `PlatformDispatcher.onError` (existing handlers still run).
  static Watchtower init(WatchtowerOptions options, {Transport? transport, bool installHooks = true}) {
    instance?.shutdown();
    final w = Watchtower._(options, transport ?? _httpTransport);
    w._timer = Timer.periodic(options.flushInterval, (_) => w.flush());
    if (installHooks) w._install();
    return instance = w;
  }

  /// Zone-guarded entry point: initialises, then runs [body] so uncaught async errors are captured.
  /// Call `WidgetsFlutterBinding.ensureInitialized()` and `runApp` inside [body], in the same zone.
  static void runGuarded(WatchtowerOptions options, void Function() body, {Transport? transport}) {
    final w = init(options, transport: transport);
    runZonedGuarded(body, (e, s) => w.captureException(e, stack: s, handled: false, mechanism: 'zone'));
  }

  void _install() {
    _hooked = true;
    _prevFlutter = FlutterError.onError;
    FlutterError.onError = (d) {
      captureException(d.exception, stack: d.stack, handled: false, mechanism: 'FlutterError.onError',
          attributes: {if (d.library != null) 'flutter.library': d.library});
      _prevFlutter?.call(d);
    };
    _prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (e, s) {
      captureException(e, stack: s, handled: false, mechanism: 'PlatformDispatcher.onError');
      return _prevPlatform?.call(e, s) ?? true;
    };
  }

  /// Stops the timer and restores the handlers that were there before [init].
  void shutdown() {
    _timer?.cancel();
    if (_hooked) {
      FlutterError.onError = _prevFlutter;
      PlatformDispatcher.instance.onError = _prevPlatform;
      _hooked = false;
    }
    if (identical(instance, this)) instance = null;
  }

  Span startSpan(String name, {Map<String, Object?>? attributes, Span? parent}) =>
      Span(name, parent: parent ?? currentSpan, attributes: attributes, onEnd: (s) {
        _spans.add(s);
        if (_spans.length >= 50) flush();
      });

  /// Runs [body] inside a new span that becomes the current span of its zone.
  Future<T> trace<T>(String name, Future<T> Function() body, {Map<String, Object?>? attributes}) =>
      startSpan(name, attributes: attributes).run(body);

  /// Sends an error log record carrying the active trace and span ids.
  Future<void> captureException(Object error,
      {StackTrace? stack, bool handled = true, String? mechanism, Map<String, Object?>? attributes}) {
    final span = currentSpan;
    final log = LogEntry(
      error.toString(),
      17,
      {
        'exception.type': error.runtimeType.toString(),
        'exception.message': error.toString(),
        if (stack != null) 'exception.stacktrace': stack.toString(),
        'exception.handled': handled,
        if (mechanism != null) 'exception.mechanism': mechanism,
        if (currentRoute != null) 'flutter.route': currentRoute,
        ...?attributes,
      },
      traceId: span?.traceId,
      spanId: span?.spanId,
    );
    span?.recordError(error);
    return _exporter.send('/v1/logs', encodeLogs(options, [log]));
  }

  Future<void> captureMessage(String message, {Map<String, Object?>? attributes}) {
    final span = currentSpan;
    return _exporter.send('/v1/logs',
        encodeLogs(options, [LogEntry(message, 9, {...?attributes}, traceId: span?.traceId, spanId: span?.spanId)]));
  }

  /// Exports finished spans and retries anything that failed earlier.
  Future<void> flush() async {
    if (_spans.isNotEmpty) {
      final batch = List<Span>.of(_spans);
      _spans.clear();
      await _exporter.send('/v1/traces', encodeSpans(options, batch));
    } else {
      await _exporter.flush();
    }
  }
}
