import 'package:flutter/services.dart';

import 'options.dart';

/// The native crash-loop guard (DX 15): launches that crashed within 5 s in a row, counted by the
/// iOS and Android SDKs. A Dart error does not end the process, so only native crashes count.
class CrashLoopState {
  const CrashLoopState(this.launchCrashCount, this.isCrashLooping);

  static const none = CrashLoopState(0, false);

  final int launchCrashCount;

  /// The app keeps crashing at launch: a cue to enter a safe mode.
  final bool isCrashLooping;

  static CrashLoopState of(Object? m) {
    if (m is! Map) return none;
    final n = m['launchCrashCount'];
    return CrashLoopState(n is int ? n : 0, m['isCrashLooping'] == true);
  }
}

/// The plugin channel (`WatchtowerFlutterPlugin` on iOS and Android).
const nativeChannel = MethodChannel('dev.watchtower/native');

/// The arguments of the plugin's `start` call: the key, endpoint and the native RUM options.
Map<String, Object?> nativeStartArgs(WatchtowerOptions o) => {
      'key': o.publishableKey,
      'service': o.service,
      'endpoint': o.endpoint,
      'release': o.release,
      'environment': o.environment,
      'crashLoopThreshold': o.crashLoopThreshold,
      'trackViews': o.trackViews,
      'hangThresholdMs': o.hangThresholdMs,
      'propagateTo': o.propagateTo,
      'profileLaunch': o.profileLaunch,
      'buildId': o.buildId,
    };

/// Starts the native SDK with [o] and returns its guard and the app's bundle id / package name
/// (the app id the edge checks when there is no Origin); [CrashLoopState.none] and null without
/// the plugin (tests, desktop, web) or on any platform error. Never throws.
Future<(CrashLoopState, String?)> startNative(WatchtowerOptions o) async {
  try {
    final m = await nativeChannel.invokeMethod<Object?>('start', nativeStartArgs(o));
    final id = m is Map ? m['appId'] : null;
    return (CrashLoopState.of(m), id is String && id.isNotEmpty ? id : null);
  } catch (_) {
    return (CrashLoopState.none, null);
  }
}

/// One RUM event in the `RumEventV1` shape, handed to the native SDK's offline buffer and batch
/// (the same one native views, launch and frame vitals use). Returns false without the plugin
/// (tests, desktop, web) or on any platform error. Never throws.
Future<bool> recordNative(String type, String name,
    {double? value, Map<String, Object?> attrs = const {}, String? traceId, String? spanId}) async {
  try {
    await nativeChannel.invokeMethod<void>('record', {
      'type': type,
      'name': name,
      if (value != null) 'value': value,
      'attrs': {for (final e in attrs.entries) if (e.value != null) e.key: e.value},
      if (traceId != null) 'trace_id': traceId,
      if (spanId != null) 'span_id': spanId,
    });
    return true;
  } catch (_) {
    return false;
  }
}
