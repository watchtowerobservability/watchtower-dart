package dev.watchtower.flutter

import android.app.Application
import dev.watchtower.Config
import dev.watchtower.DEFAULT_ENDPOINT
import dev.watchtower.Event
import dev.watchtower.Watchtower
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Starts the native Android SDK under the Dart client (native crashes, ANRs) and hands its
 * crash-loop guard (DX 15) and the package name (the app id the edge checks) to Dart over
 * `dev.watchtower/native`.
 */
class WatchtowerFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var app: Application? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        app = binding.applicationContext as? Application
        channel = MethodChannel(binding.binaryMessenger, "dev.watchtower/native").also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val key = call.argument<String>("key")
                val service = call.argument<String>("service")
                val a = app
                if (key != null && service != null && a != null) {
                    val cfg = Config(
                        key = key,
                        service = service,
                        endpoint = call.argument<String>("endpoint") ?: DEFAULT_ENDPOINT,
                        release = call.argument<String>("release"),
                        environment = call.argument<String>("environment"),
                        crashLoopThreshold = (call.argument<Int>("crashLoopThreshold") ?: 2).coerceAtLeast(1),
                        trackViews = call.argument<Boolean>("trackViews") ?: true,
                        anrThresholdMs = (call.argument<Int>("hangThresholdMs") ?: 5000).toLong().coerceAtLeast(1),
                        propagateTo = call.argument<List<String>>("propagateTo") ?: emptyList(),
                        profileLaunch = call.argument<Boolean>("profileLaunch") ?: false,
                        buildId = call.argument<String>("buildId"),
                    )
                    Watchtower.init(a, cfg) // no-op if the app already started it
                }
                result.success(state())
            }
            "crashLoop" -> result.success(state())
            "record" -> {
                val attrs = call.argument<Map<String, Any>>("attrs") ?: emptyMap()
                Watchtower.record(
                    Event(
                        type = call.argument<String>("type") ?: return result.success(null),
                        name = call.argument<String>("name") ?: "",
                        value = call.argument<Double>("value"),
                        attrs = attrs,
                        traceId = call.argument<String>("trace_id"),
                        spanId = call.argument<String>("span_id"),
                    ),
                )
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun state(): Map<String, Any> = mapOf(
        "launchCrashCount" to Watchtower.launchCrashCount,
        "isCrashLooping" to Watchtower.isCrashLooping,
        "appId" to (app?.packageName ?: ""),
    )
}
