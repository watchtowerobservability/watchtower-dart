import Flutter
#if canImport(WatchtowerSDK)
import WatchtowerSDK // the CocoaPods pod (a pod named `Watchtower` would clash with this plugin's `watchtower`)
#else
import Watchtower // Swift Package Manager
#endif

/// Starts the native iOS SDK under the Dart client (native crashes, hangs) and hands its
/// crash-loop guard (DX 15) and the bundle id (the app id the edge checks) to Dart over
/// `dev.watchtower/native`.
public final class WatchtowerFlutterPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "dev.watchtower/native", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(WatchtowerFlutterPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            let a = call.arguments as? [String: Any] ?? [:]
            if let key = a["key"] as? String, let service = a["service"] as? String {
                var c = Config(key: key, service: service)
                if let e = a["endpoint"] as? String { c.endpoint = e }
                c.release = a["release"] as? String
                c.environment = a["environment"] as? String
                if let n = a["crashLoopThreshold"] as? Int { c.crashLoopThreshold = max(1, n) }
                if let v = a["trackViews"] as? Bool { c.trackViews = v }
                if let v = a["hangThresholdMs"] as? Int, v > 0 { c.hangThreshold = Double(v) / 1000 }
                if let v = a["propagateTo"] as? [String] { c.propagateTo = v }
                if let v = a["profileLaunch"] as? Bool { c.profileLaunch = v }
                c.buildId = a["buildId"] as? String
                Watchtower.start(c) // no-op if the app already started it
            }
            result(Self.state())
        case "crashLoop":
            result(Self.state())
        case "record":
            let a = call.arguments as? [String: Any] ?? [:]
            if let type = a["type"] as? String {
                var e = Event(type: type, name: a["name"] as? String ?? "", value: a["value"] as? Double,
                              attrs: a["attrs"] as? [String: Any] ?? [:])
                e.traceId = a["trace_id"] as? String
                e.spanId = a["span_id"] as? String
                Watchtower.shared.record(e)
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func state() -> [String: Any] {
        ["launchCrashCount": Watchtower.shared.launchCrashCount, "isCrashLooping": Watchtower.shared.isCrashLooping,
         "appId": Bundle.main.bundleIdentifier ?? ""]
    }
}
