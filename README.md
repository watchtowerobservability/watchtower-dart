# watchtower (Flutter and Dart)

Errors, traces and logs from Flutter apps to Watchtower over OTLP/HTTP, plus a debug-symbol upload tool.

## Install

```yaml
dependencies:
  watchtower:
    git:
      url: https://github.com/watchtowerobservability/watchtower-dart
      ref: v0.1.1
```

## Quick start

```dart
void main() => Watchtower.runGuarded(WatchtowerOptions.fromEnvironment(), () {
      WidgetsFlutterBinding.ensureInitialized();
      runApp(MaterialApp(navigatorObservers: [WatchtowerNavigatorObserver()], home: const Home()));
    });
// flutter run --dart-define=WT_PUBLISHABLE_KEY=wtp_... --dart-define=WT_RELEASE=1.0.0
```

Use the publishable key (`wtp_`) in the app. Secret keys are refused. The key is masked in `toString` and never logged.

## Integrations

| Integration | What it does |
| --- | --- |
| `FlutterError.onError` | framework errors; the previous handler still runs |
| `PlatformDispatcher.onError` | uncaught async and platform errors |
| `Watchtower.runGuarded` | `runZonedGuarded` entry point |
| `WatchtowerNavigatorObserver` | one span per route; route name on errors |
| `WatchtowerHttpClient` | client span per request, `traceparent` to the hosts you list, query strings dropped |
| `WatchtowerDb.sql` / `measure` / `measureSync` | sqflite, drift (`QueryInterceptor`), Hive, Isar: slow or failed ops as spans (operation and table, never SQL text); sync work on the UI isolate flagged `db.main_thread` |
| `Watchtower.trace` / `startSpan` | your own spans, zone-propagated |
| `captureException` / `captureMessage` | manual capture; carries the active trace and span ids |

## Configuration

| Name (`--dart-define`) | Option | Default |
| --- | --- | --- |
| `WT_PUBLISHABLE_KEY` | `publishableKey` | required |
| `WT_OTLP_ENDPOINT` | `endpoint` | `http://localhost:4318` |
| `WT_SERVICE` | `service` | `flutter-app` |
| `WT_ENVIRONMENT` | `environment` | none |
| `WT_RELEASE` | `release` | none |

Also: `redact(key, value)` hook (return null to drop), `maxBatches` (in-memory retry buffer), caller `wt.*` attributes are removed.
Keys go out as `Authorization: Bearer <key>`.

## App id

The SDK sends the app id as `X-Watchtower-App-Id`: the `appId` option (or `--dart-define=WT_APP_ID=...`), else the bundle id / package name the iOS / Android plugin reports, so a Flutter app needs no setup for it (requests wait for the plugin's answer; on desktop and web without the plugin, set `appId`). An app sends no `Origin`, so add the iOS bundle id and the Android package name to the publishable key's **app ids** (Settings, Browser keys) or feedback and logs sent with the key are refused with 403 `app_id_not_allowed`.

## User feedback

```dart
final ok = await Watchtower.instance!.feedback('The checkout button does nothing', name: 'Ann', email: 'ann@example.com');
```

Posts to the edge's `/v1/rum/feedback` with the publishable key; `ok` is false when it was not
accepted (it never throws). Name and email become pseudonyms at the edge. Errors are sent as OTLP
logs whose ids are assigned on the server, so pass `eventId:` yourself to link feedback to one.

Native crashes and the crash-loop guard: on iOS and Android the plugin starts the Watchtower
native SDK under this client (`nativeCrashes: true`, the default), which catches native crashes,
hangs and ANRs and counts launches that crash within 5 s. Read the guard to enter a safe mode
(threshold: `crashLoopThreshold`, default 2):

```dart
final loop = await Watchtower.instance!.crashLoop();
if (loop.isCrashLooping) { /* skip the risky start-up work, offer a reset */ }
```

The native SDK must be available to the app build: `dev.watchtower:watchtower-android` on Android,
the `Watchtower` pod on iOS.

## Symbols and obfuscation maps

```sh
flutter build apk --obfuscate --split-debug-info=build/symbols \
  --extra-gen-snapshot-options=--save-obfuscation-map=build/obfuscation.map.json
WT_API_KEY=wtk_... dart run watchtower:upload_symbols --api https://api.example --project <id> \
  --release 1.0.0 --obfuscation-map build/obfuscation.map.json
```

`--dry-run` lists the files. A publishable key (`wtp_`) is refused.

## Provenance

`gh attestation verify <file> --repo watchtowerobservability/watchtower-dart`

## License

Apache-2.0. Source of truth is the Watchtower monorepo; this repository is a published mirror.

## iOS (CocoaPods)

The plugin's pod is `watchtower` (Flutter names it after the package) and depends on the native SDK pod
`WatchtowerSDK` (`sdks/ios/WatchtowerSDK.podspec`). The native pod is not called `Watchtower`, because
CocoaPods and the case-insensitive macOS file system would treat the two as one.
