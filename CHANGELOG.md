# Changelog

## 0.1.0

- Errors from `FlutterError.onError`, `PlatformDispatcher.onError` and a guarded zone, as OTLP logs with trace and span ids.
- Spans with zone-propagated context, `WatchtowerHttpClient`, `WatchtowerNavigatorObserver`.
- OTLP/HTTP JSON export with a bounded in-memory retry buffer and a redaction hook.
- `dart run watchtower:upload_symbols` uploads `--split-debug-info` symbols and the obfuscation map.
