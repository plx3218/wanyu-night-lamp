package com.shenicest.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.shenicest.app/usage_monitor_lab"
    private lateinit var usageMonitorBridge: UsageMonitorBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        usageMonitorBridge = UsageMonitorBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasUsageAccess" -> result.success(usageMonitorBridge.hasUsageAccess())
                    "openUsageAccessSettings" -> {
                        usageMonitorBridge.openUsageAccessSettings()
                        result.success(null)
                    }

                    "queryUsage" -> {
                        if (!usageMonitorBridge.hasUsageAccess()) {
                            result.error(
                                "usage_access_required",
                                "Usage access permission is required",
                                null,
                            )
                        } else {
                            val sinceMs = call.argument<Number>("sinceMs")?.toLong()
                                ?: (System.currentTimeMillis() - 30 * 60 * 1000)
                            result.success(usageMonitorBridge.queryForegroundDurations(sinceMs))
                        }
                    }

                    "queryUsageSegments" -> {
                        if (!usageMonitorBridge.hasUsageAccess()) {
                            result.error(
                                "usage_access_required",
                                "Usage access permission is required",
                                null,
                            )
                        } else {
                            val sampledAtMs = System.currentTimeMillis()
                            val sinceMs = call.argument<Number>("sinceMs")?.toLong()
                                ?: (sampledAtMs - 30 * 60 * 1000)
                            result.success(
                                mapOf(
                                    "permissionGranted" to true,
                                    "sampledAtMs" to sampledAtMs,
                                    "segments" to usageMonitorBridge.queryForegroundSegments(
                                        sinceMs,
                                        sampledAtMs,
                                    ),
                                ),
                            )
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
