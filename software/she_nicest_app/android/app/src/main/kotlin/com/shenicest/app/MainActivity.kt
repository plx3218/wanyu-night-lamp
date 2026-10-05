package com.shenicest.app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.shenicest.app/usage_monitor_lab"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasUsageAccess" -> result.success(hasUsageAccess())
                    "openUsageAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "queryUsage" -> {
                        if (!hasUsageAccess()) {
                            result.error("usage_access_required", "尚未开启使用情况访问权限", null)
                        } else {
                            val sinceMs = call.argument<Number>("sinceMs")?.toLong()
                                ?: (System.currentTimeMillis() - 30 * 60 * 1000)
                            result.success(queryForegroundDurations(sinceMs))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * 汇总给定时间点之后，各包处于前台的累计时长。
     * 这是 AfterHack 的能力实验，不是正式监测引擎；数据只返回 Flutter 本地页面。
     */
    private fun queryForegroundDurations(sinceMs: Long): List<Map<String, Any>> {
        val now = System.currentTimeMillis()
        val usageStatsManager =
            getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = usageStatsManager.queryEvents(sinceMs, now)
        val event = UsageEvents.Event()
        val activeSince = mutableMapOf<String, Long>()
        val durations = mutableMapOf<String, Long>()

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val packageName = event.packageName ?: continue
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED,
                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    activeSince[packageName] = event.timeStamp
                }
                UsageEvents.Event.ACTIVITY_PAUSED,
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    val startedAt = activeSince.remove(packageName) ?: continue
                    durations[packageName] =
                        (durations[packageName] ?: 0L) + (event.timeStamp - startedAt).coerceAtLeast(0L)
                }
            }
        }

        activeSince.forEach { (packageName, startedAt) ->
            durations[packageName] =
                (durations[packageName] ?: 0L) + (now - startedAt).coerceAtLeast(0L)
        }

        return durations.entries
            .filter { it.value > 0L }
            .sortedByDescending { it.value }
            .map { mapOf("packageName" to it.key, "durationMs" to it.value) }
    }
}
