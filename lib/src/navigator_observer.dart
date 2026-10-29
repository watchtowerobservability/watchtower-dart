import 'package:flutter/widgets.dart';

import 'client.dart';
import 'otlp.dart';

/// Add to `MaterialApp.navigatorObservers`: one span per visible route, and the route name on errors.
class WatchtowerNavigatorObserver extends NavigatorObserver {
  final _spans = <Route<dynamic>, Span>{};

  void _enter(Route<dynamic>? route) {
    final wt = Watchtower.instance;
    final name = route?.settings.name;
    if (wt == null || route == null || name == null) return;
    wt.currentRoute = name;
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
