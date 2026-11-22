package com.localpharmacy.app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.Calendar
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

internal object Reminders {
    private const val channelId = "pharmacy_reminders"
    private const val alarmAction = "com.localpharmacy.app.DELIVER_REMINDERS"
    private const val never = Long.MAX_VALUE

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(channelId, "Напоминания аптеки", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences("pharmacy_reminder_queue", Context.MODE_PRIVATE)

    private fun pending(context: Context) = PendingIntent.getBroadcast(
        context, 0, Intent(context, ReminderReceiver::class.java).setAction(alarmAction),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private data class Queue(val enabled: Boolean, val events: JSONArray)

    private fun load(context: Context): Queue {
        val settings = prefs(context)
        val stored = settings.getString("sealed_events", null)
        if (stored == null) {
            return Queue(settings.getBoolean("enabled", false), JSONArray(settings.getString("events", "[]")))
        }
        val sealed = Base64.decode(stored, Base64.NO_WRAP)
        val compressed = SecureData.open(sealed, "pharmacy/reminders")
        val decoded = GZIPInputStream(ByteArrayInputStream(compressed)).bufferedReader(Charsets.UTF_8).use {
            JSONObject(it.readText())
        }
        return Queue(decoded.getBoolean("enabled"), decoded.getJSONArray("events"))
    }

    private fun save(context: Context, enabled: Boolean, events: JSONArray) {
        val settings = prefs(context)
        val migrating = settings.contains("events")
        val output = ByteArrayOutputStream()
        val data = JSONObject().put("enabled", enabled).put("events", events)
        GZIPOutputStream(output).use { it.write(data.toString().toByteArray(Charsets.UTF_8)) }
        val encrypted = Base64.encodeToString(SecureData.seal(output.toByteArray(), "pharmacy/reminders"), Base64.NO_WRAP)
        check(settings.edit().putString("sealed_events", encrypted)
            .remove("enabled").remove("events").commit())
        if (migrating) context.getSystemService(NotificationManager::class.java).cancelAll()
    }

    fun replace(context: Context, enabled: Boolean, raw: String) {
        val queue = load(context)
        val previous = queue.events
        val byId = (0 until previous.length()).associate { index ->
            val event = previous.getJSONObject(index)
            event.getString("id") to event
        }
        val current = JSONArray(raw)
        val now = System.currentTimeMillis()
        for (index in 0 until current.length()) {
            val event = current.getJSONObject(index)
            val old = byId[event.getString("id")]
            if (event.has("hour")) {
                event.put("deliveredDay", old?.optInt("deliveredDay") ?: 0)
                val due = old?.optLong("due", never) ?: never
                event.put("due", if (due != never) due else nextIntake(event, now))
            } else if (old?.optBoolean("finished") == true) {
                event.put("finished", true)
            }
        }
        val preferences = prefs(context)
        val obsolete = byId.keys - (0 until current.length()).map { current.getJSONObject(it).getString("id") }.toSet()
        if (preferences.contains("events") || current.toString() != previous.toString() ||
            enabled != queue.enabled) {
            save(context, enabled, current)
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!enabled) manager.cancelAll()
        else obsolete.forEach { manager.cancel(notificationTag(it), 1) }
        schedule(context, enabled, current)
    }

    private fun nextIntake(event: JSONObject, now: Long): Long {
        val next = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, event.getInt("hour"))
            set(Calendar.MINUTE, event.getInt("minute"))
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= now) add(Calendar.DAY_OF_YEAR, 1)
            if (calendarDay(timeInMillis) == event.optInt("deliveredDay")) add(Calendar.DAY_OF_YEAR, 1)
        }.timeInMillis
        return if (next < event.getLong("until")) next else never
    }

    private fun calendarDay(time: Long): Int = Calendar.getInstance().run {
        timeInMillis = time
        get(Calendar.YEAR) * 1000 + get(Calendar.DAY_OF_YEAR)
    }

    private fun due(event: JSONObject): Long {
        if (event.optBoolean("finished") || event.optBoolean("muted")) return never
        val time = event.getLong("due")
        return if (event.has("until") && time >= event.getLong("until")) never else time
    }

    private fun schedule(context: Context, enabled: Boolean, events: JSONArray) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val alarm = pending(context)
        if (!enabled ||
            !context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()) {
            alarms.cancel(alarm)
            return
        }
        val next = (0 until events.length()).minOfOrNull { due(events.getJSONObject(it)) } ?: never
        if (next == never) {
            alarms.cancel(alarm)
        } else {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, alarm)
        }
    }

    fun reconcile(context: Context, clockChanged: Boolean) {
        val queue = load(context)
        val events = queue.events
        val now = System.currentTimeMillis()
        val enabled = queue.enabled
        val manager = context.getSystemService(NotificationManager::class.java)
        ensureChannel(context)
        val original = events.toString()
        val ready = mutableListOf<JSONObject>()
        for (index in 0 until events.length()) {
            val event = events.getJSONObject(index)
            val daily = event.has("hour")
            if (clockChanged && daily) {
                event.put("due", nextIntake(event, now))
                continue
            }
            val scheduled = due(event)
            if (!enabled || !manager.areNotificationsEnabled() || scheduled > now) continue
            // A delayed alarm must not suggest taking a dose from the previous day.
            if (!daily || (calendarDay(scheduled) == calendarDay(now) &&
                        now - scheduled < 4 * 60 * 60 * 1000L && now < event.getLong("until"))) {
                ready.add(event)
                if (daily) event.put("deliveredDay", calendarDay(now))
            }
            if (daily) event.put("due", nextIntake(event, now))
            else event.put("finished", true)
        }
        if (prefs(context).contains("events") || events.toString() != original) save(context, enabled, events)
        ready.forEach { show(context, manager, it) }
        schedule(context, enabled, events)
    }

    private fun notificationTag(id: String): String =
        Base64.encodeToString(MessageDigest.getInstance("SHA-256").digest(id.toByteArray()), Base64.NO_WRAP)

    private fun show(context: Context, manager: NotificationManager, event: JSONObject) {
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channelId)
            else @Suppress("DEPRECATION") Notification.Builder(context)
        val notification = builder.setSmallIcon(R.drawable.ic_reminder)
            .setContentTitle(event.getString("title"))
            .setContentText("Откройте раздел «Уведомления» в приложении.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        manager.notify(notificationTag(event.getString("id")), 1, notification)
    }

    fun isClockChange(action: String?) =
        action == Intent.ACTION_TIME_CHANGED || action == Intent.ACTION_TIMEZONE_CHANGED
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            Reminders.reconcile(context, Reminders.isClockChange(intent.action))
        } catch (_: Exception) {
            Log.w("PharmacyReminders", "Unable to access encrypted reminders")
        }
    }
}
