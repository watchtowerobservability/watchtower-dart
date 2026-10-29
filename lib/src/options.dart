const sdkVersion = '0.1.0';

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
    Map<String, Object?>? resource,
  })  : endpoint = (endpoint ?? 'http://localhost:4318').replaceAll(RegExp(r'/+$'), ''),
        resource = safeAttributes(resource) {
    if (publishableKey.isEmpty) throw ArgumentError('publishableKey is required');
    // Secret keys must never ship inside an app binary.
    if (RegExp(r'^wt[iks]_').hasMatch(publishableKey)) {
      throw ArgumentError('Use a publishable key (wtp_) in app code, never a secret key');
    }
  }

  /// Reads WT_PUBLISHABLE_KEY, WT_OTLP_ENDPOINT, WT_SERVICE, WT_ENVIRONMENT, WT_RELEASE.
  factory WatchtowerOptions.fromEnvironment({RedactHook? redact}) => WatchtowerOptions(
        publishableKey: const String.fromEnvironment('WT_PUBLISHABLE_KEY'),
        endpoint: _nonEmpty(const String.fromEnvironment('WT_OTLP_ENDPOINT')),
        service: const String.fromEnvironment('WT_SERVICE', defaultValue: 'flutter-app'),
        environment: _nonEmpty(const String.fromEnvironment('WT_ENVIRONMENT')),
        release: _nonEmpty(const String.fromEnvironment('WT_RELEASE')),
        redact: redact,
      );

  final String publishableKey;
  final String endpoint;
  final String service;
  final String? environment;
  final String? release;

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
