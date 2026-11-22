const sdkVersion = '0.1.1';

typedef RedactHook = Object? Function(String key, Object? value);

/// Drops caller-supplied `wt.*` keys: tenant identity comes only from the key.
Map<String, Object?> safeAttributes(Map<String, Object?>? attrs) => {
      for (final e in (attrs ?? const <String, Object?>{}).entries)
        if (!e.key.startsWith('wt.')) e.key: e.value,
    };

String? _nonEmpty(String s) => s.isEmpty ? null : s;

/// Client SDK options. Build-time values come from `--dart-define=WT_...=...`.
class WatchtowerOptions {
  WatchtowerOptions({
    required this.publishableKey,
    String? endpoint,
    this.service = 'flutter-app',
    this.environment,
    this.release,
    this.redact,
    this.maxBatches = 20,
    this.flushInterval = const Duration(seconds: 5),
    this.appId,
    this.nativeCrashes = true,
    this.crashLoopThreshold = 2,
    this.trackViews = true,
    this.hangThresholdMs = 5000,
    this.propagateTo = const [],
    this.profileLaunch = false,
    this.buildId,
    Map<String, Object?>? resource,
  })  : endpoint = (endpoint ?? 'http://localhost:4318').replaceAll(RegExp(r'/+$'), ''),
        resource = safeAttributes(resource) {
    if (publishableKey.isEmpty) throw ArgumentError('publishableKey is required');
    // Secret keys must never ship inside an app binary.
    if (RegExp(r'^wt[iks]_').hasMatch(publishableKey)) {
      throw ArgumentError('Use a publishable key (wtp_) in app code, never a secret key');
    }
  }

  /// Reads WT_PUBLISHABLE_KEY, WT_OTLP_ENDPOINT, WT_SERVICE, WT_ENVIRONMENT, WT_RELEASE, WT_APP_ID.
  factory WatchtowerOptions.fromEnvironment({RedactHook? redact}) => WatchtowerOptions(
        publishableKey: const String.fromEnvironment('WT_PUBLISHABLE_KEY'),
        endpoint: _nonEmpty(const String.fromEnvironment('WT_OTLP_ENDPOINT')),
        service: const String.fromEnvironment('WT_SERVICE', defaultValue: 'flutter-app'),
        environment: _nonEmpty(const String.fromEnvironment('WT_ENVIRONMENT')),
        release: _nonEmpty(const String.fromEnvironment('WT_RELEASE')),
        appId: _nonEmpty(const String.fromEnvironment('WT_APP_ID')),
        redact: redact,
      );

  final String publishableKey;
  final String endpoint;
  final String service;
  final String? environment;
  final String? release;

  /// The app's bundle id / package name (e.g. `com.example.app`). An app sends no Origin, so the
  /// publishable key is accepted only with this id on its app id list (`X-Watchtower-App-Id`).
  /// Null (the default) uses the id the iOS / Android plugin reports; set it only to override.
  final String? appId;

  /// Start the native iOS / Android SDK under this client (native crashes, hangs and ANRs, and
  /// the crash-loop guard read by `Watchtower.crashLoop`). No-op where the plugin is absent.
  final bool nativeCrashes;

  /// `CrashLoopState.isCrashLooping` is true from this many consecutive launch crashes.
  final int crashLoopThreshold;

  /// Native screen views (one RUM `view` per resumed activity / view controller). Flutter routes
  /// come from [WatchtowerNavigatorObserver]; turn this off when it covers every screen.
  final bool trackViews;

  /// The main thread counts as hung (an ANR on Android, an app hang on iOS) after this many ms.
  final int hangThresholdMs;

  /// URL prefixes the native SDKs add a W3C `traceparent` header to.
  final List<String> propagateTo;

  /// Sample the main thread's stack until the first frame of a cold launch (`app_launch_profile`).
  final bool profileLaunch;

  /// The debug-file build id (dSYM UUID, ProGuard mapping id) added to every native error.
  final String? buildId;

  /// Headers of every request to Watchtower.
  Map<String, String> get headers => {
        'Authorization': 'Bearer $publishableKey',
        'Content-Type': 'application/json',
        if (appId != null) 'X-Watchtower-App-Id': appId!,
      };

  /// Runs over every attribute before export; return the value to send (null drops it).
  final RedactHook? redact;

  /// Unsent batches kept in memory for retry; the oldest are dropped past this.
  final int maxBatches;
  final Duration flushInterval;
  final Map<String, Object?> resource;

  String get maskedKey => publishableKey.length < 8 ? '****' : '${publishableKey.substring(0, 4)}****';

  @override
  String toString() => 'WatchtowerOptions(endpoint: $endpoint, service: $service, key: $maskedKey)';
}
