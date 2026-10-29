# watchtower (Flutter and Dart)

Errors, traces and logs from Flutter apps to Watchtower over OTLP/HTTP, plus a debug-symbol upload tool.

## Install

```yaml
dependencies:
  watchtower:
    git:
      url: https://github.com/watchtowerobservability/watchtower-dart
      ref: v0.1.0
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
