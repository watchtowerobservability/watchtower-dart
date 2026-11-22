import 'package:flutter/widgets.dart';

import 'client.dart';
import 'otlp.dart';

/// Add to `MaterialApp.navigatorObservers`: one span per visible route, and the route name on errors.
class WatchtowerNavigatorObserver extends NavigatorObserver {
  final _spans = <Route<dynamic>, Span>{};
  DateTime? _since;

  void _enter(Route<dynamic>? route) {
    final wt = Watchtower.instance;
    final name = route?.settings.name;
    if (wt == null || route == null || name == null) return;
    final from = wt.currentRoute;
    wt.currentRoute = name;
    final now = DateTime.now();
    wt.recordRum('view', name, attrs: viewAttrs(name, from, _since == null ? null : now.difference(_since!).inMilliseconds));
    _since = now;
    _spans[route] = wt.startSpan('route $name', attributes: {'flutter.route': name});
  }

  void _leave(Route<dynamic>? route) => _spans.remove(route)?.finish();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _leave(previousRoute);
    _enter(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _leave(route);
    _enter(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _leave(oldRoute);
    _enter(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _leave(route);
}

/// Attributes of a RUM `view` event, in the shape of the native and browser SDKs.
Map<String, Object?> viewAttrs(String route, String? previous, int? previousMs) => {
      'route': route,
      'url': 'app://flutter/$route',
      if (previous != null && previous != route) 'previous_route': previous,
      if (previous != null && previousMs != null) 'previous_duration_ms': previousMs,
    };
