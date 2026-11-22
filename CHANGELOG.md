# Changelog

## 0.1.1

- Sync with the monorepo: launch profiling and client storage instrumentation.

- Client storage (`WatchtowerDb`): `measure`, `measureSync` and `sql` time sqflite, drift (from a `QueryInterceptor`), Hive and Isar calls; only slow or failed ops are exported as spans, sync work on the UI isolate is flagged `db.main_thread`; `recordStoreSize` as a log record. No new dependencies.
- iOS and Android plugin layers start the native SDK (native crashes, hangs, ANRs); `crashLoop()` reads its crash-loop guard (`nativeCrashes`, `crashLoopThreshold` options).
- `appId` option (`WT_APP_ID`), sent as `X-Watchtower-App-Id` on every request; defaults to the bundle id / package name the plugin reports.
- The iOS plugin depends on the native pod `WatchtowerSDK` (was `Watchtower`, which clashed with the plugin's `watchtower` pod).
- `Watchtower.feedback(message, name:, email:, eventId:)` posts user feedback to `/v1/rum/feedback`.

## 0.1.0

- Errors from `FlutterError.onError`, `PlatformDispatcher.onError` and a guarded zone, as OTLP logs with trace and span ids.
- Spans with zone-propagated context, `WatchtowerHttpClient`, `WatchtowerNavigatorObserver`.
- OTLP/HTTP JSON export with a bounded in-memory retry buffer and a redaction hook.
- `dart run watchtower:upload_symbols` uploads `--split-debug-info` symbols and the obfuscation map.
