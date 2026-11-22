import 'package:http/http.dart' as http;

import 'client.dart';

/// Wraps an `http.Client`: one client span per request, `traceparent` propagated to [propagateTo]
/// hosts only (default none), query strings stripped from the recorded URL, and
/// requests to the Watchtower endpoint itself are not traced.
class WatchtowerHttpClient extends http.BaseClient {
  WatchtowerHttpClient([http.Client? inner, this.propagateTo = const []]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  /// Hosts that receive the `traceparent` header.
  final List<String> propagateTo;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final wt = Watchtower.instance;
    if (wt == null || request.url.toString().startsWith(wt.options.endpoint)) return _inner.send(request);
    final u = request.url;
    final span = wt.startSpan('HTTP ${request.method}', attributes: {
      'http.request.method': request.method,
      'url.full': Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null, path: u.path).toString(),
      'server.address': u.host,
    });
    if (propagateTo.contains(u.host)) request.headers['traceparent'] = span.traceparent;
    final started = DateTime.now();
    try {
      final res = await _inner.send(request);
      wt.recordRum('resource', 'native',
          value: DateTime.now().difference(started).inMilliseconds.toDouble(),
          attrs: resourceAttrs(u, request.method, res.statusCode, res.contentLength),
          traceId: span.traceId,
          spanId: span.spanId);
      span.attributes['http.response.status_code'] = res.statusCode;
      if (res.statusCode >= 500) span.error = true;
      return res;
    } catch (e) {
      wt.recordRum('resource', 'native',
          value: DateTime.now().difference(started).inMilliseconds.toDouble(),
          attrs: resourceAttrs(u, request.method, null, null),
          traceId: span.traceId,
          spanId: span.spanId);
      span.recordError(e);
      rethrow;
    } finally {
      span.finish();
    }
  }

  @override
  void close() => _inner.close();
}

/// Attributes of a RUM `resource` event: URL without query or fragment (both can carry tokens).
Map<String, Object?> resourceAttrs(Uri u, String method, int? status, int? bytes) => {
      'url': Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null, path: u.path).toString(),
      'method': method.toUpperCase(),
      'initiator_type': 'native',
      if (status != null) 'status': status,
      if (bytes != null && bytes >= 0) 'transfer_size': bytes,
      if (status == null || status >= 400) 'failed': true,
    };
