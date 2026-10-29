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
    try {
      final res = await _inner.send(request);
      span.attributes['http.response.status_code'] = res.statusCode;
      if (res.statusCode >= 500) span.error = true;
      return res;
    } catch (e) {
      span.recordError(e);
      rethrow;
    } finally {
      span.finish();
    }
  }

  @override
  void close() => _inner.close();
}
