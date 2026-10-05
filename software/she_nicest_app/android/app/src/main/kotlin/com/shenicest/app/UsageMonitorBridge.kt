package com.shenicest.app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Process
import android.provider.Settings

class UsageMonitorBridge(private val context: Context) {
    fun hasUsageAccess(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun openUsageAccessSettings() {
        context.startActivity(
            Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    fun queryForegroundSegments(
        sinceMs: Long,
        nowMs: Long = System.currentTimeMillis(),
    ): List<Map<String, Any>> {
        if (nowMs <= sinceMs) return emptyList()

        val usageStatsManager =
            context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = usageStatsManager.queryEvents(sinceMs, nowMs)
        val event = UsageEvents.Event()
        val activeSince = mutableMapOf<String, Long>()
        val segments = mutableListOf<Map<String, Any>>()

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val packageName = event.packageName ?: continue
            val timestamp = event.timeStamp.coerceIn(sinceMs, nowMs)
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED,
                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    activeSince.putIfAbsent(packageName, timestamp)
                }

                UsageEvents.Event.ACTIVITY_PAUSED,
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    val startedAt = activeSince.remove(packageName) ?: continue
                    if (timestamp > startedAt) {
                        segments += segment(packageName, startedAt, timestamp)
                    }
                }
            }
        }

        activeSince.forEach { (packageName, startedAt) ->
            if (nowMs > startedAt) {
                segments += segment(packageName, startedAt, nowMs)
            }
        }
        return segments.sortedBy { it["startedAtMs"] as Long }
    }

    fun queryForegroundDurations(
        sinceMs: Long,
        nowMs: Long = System.currentTimeMillis(),
    ): List<Map<String, Any>> {
        val durations = mutableMapOf<String, Long>()
        queryForegroundSegments(sinceMs, nowMs).forEach { segment ->
            val packageName = segment["packageName"] as String
            val startedAt = segment["startedAtMs"] as Long
            val endedAt = segment["endedAtMs"] as Long
            durations[packageName] =
                (durations[packageName] ?: 0L) + (endedAt - startedAt)
        }
        return durations.entries
            .filter { it.value > 0L }
            .sortedByDescending { it.value }
            .map { mapOf("packageName" to it.key, "durationMs" to it.value) }
    }

    private fun segment(
        packageName: String,
        startedAtMs: Long,
        endedAtMs: Long,
    ): Map<String, Any> = mapOf(
        "packageName" to packageName,
        "startedAtMs" to startedAtMs,
        "endedAtMs" to endedAtMs,
    )
}
