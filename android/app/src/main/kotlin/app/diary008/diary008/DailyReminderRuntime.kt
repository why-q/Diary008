package app.diary008.diary008

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

internal object DailyReminderRuntime {
    internal const val ACTION_DAILY_REMINDER = "app.diary008.action.DAILY_REMINDER"
    internal const val EXTRA_SCHEDULED_AT = "scheduled_at"

    private const val PREFERENCES_NAME = "daily_reminder_runtime"
    private const val KEY_NEXT_AT = "next_at"
    private const val KEY_DUE_AT = "due_at"
    private const val REQUEST_CODE = 1_000_000_000

    @Synchronized
    fun schedule(context: Context, at: Long) {
        val appContext = context.applicationContext
        val preferences = preferences(appContext)
        val previousAt = readLong(preferences, KEY_NEXT_AT)
        if (previousAt == at && existingPendingIntent(appContext) != null) return

        val alarmManager = requireNotNull(appContext.getSystemService(AlarmManager::class.java))
        try {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                at,
                pendingIntent(appContext, at),
            )
            check(preferences.edit().putLong(KEY_NEXT_AT, at).commit()) {
                "Could not persist the scheduled daily reminder"
            }
        } catch (failure: Throwable) {
            try {
                if (previousAt == null) {
                    existingPendingIntent(appContext)?.let { pending ->
                        alarmManager.cancel(pending)
                        pending.cancel()
                    }
                    check(preferences.edit().remove(KEY_NEXT_AT).commit()) {
                        "Could not clear the failed daily reminder schedule"
                    }
                } else {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        previousAt,
                        pendingIntent(appContext, previousAt),
                    )
                    check(preferences.edit().putLong(KEY_NEXT_AT, previousAt).commit()) {
                        "Could not restore the previous daily reminder schedule"
                    }
                }
            } catch (rollbackFailure: Throwable) {
                failure.addSuppressed(rollbackFailure)
            }
            throw failure
        }
    }

    @Synchronized
    fun cancel(context: Context) {
        val appContext = context.applicationContext
        val alarmManager = requireNotNull(appContext.getSystemService(AlarmManager::class.java))
        existingPendingIntent(appContext)?.let { pending ->
            alarmManager.cancel(pending)
            pending.cancel()
        }
        check(
            preferences(appContext).edit()
                .remove(KEY_NEXT_AT)
                .remove(KEY_DUE_AT)
                .commit(),
        ) {
            "Could not clear daily reminder state"
        }
    }


    @Synchronized
    fun complete(context: Context, at: Long): Boolean {
        val preferences = preferences(context.applicationContext)
        if (readLong(preferences, KEY_DUE_AT) != at) return false
        check(preferences.edit().remove(KEY_DUE_AT).commit()) {
            "Could not clear the completed daily reminder"
        }
        return true
    }

    @Synchronized
    fun state(context: Context): Map<String, Any?> {
        val preferences = preferences(context.applicationContext)
        val at = readLong(preferences, KEY_NEXT_AT)
        return mapOf(
            "scheduled" to (at != null && existingPendingIntent(context.applicationContext) != null),
            "at" to at,
            "dueAt" to readLong(preferences, KEY_DUE_AT),
        )
    }

    @Synchronized
    internal fun consumeAlarm(context: Context, at: Long): Boolean {
        val preferences = preferences(context.applicationContext)
        if (readLong(preferences, KEY_NEXT_AT) != at) return false
        check(
            preferences.edit()
                .putLong(KEY_DUE_AT, at)
                .remove(KEY_NEXT_AT)
                .commit(),
        ) {
            "Could not persist the due daily reminder"
        }
        return true
    }

    private fun pendingIntent(context: Context, at: Long): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            alarmIntent(context).putExtra(EXTRA_SCHEDULED_AT, at),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun alarmIntent(context: Context): Intent =
        Intent(context, DailyReminderReceiver::class.java).setAction(ACTION_DAILY_REMINDER)

    private fun existingPendingIntent(context: Context): PendingIntent? =
        PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            alarmIntent(context),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    private fun readLong(
        preferences: android.content.SharedPreferences,
        key: String,
    ): Long? = if (preferences.contains(key)) preferences.getLong(key, 0L) else null
}

class DailyReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DailyReminderRuntime.ACTION_DAILY_REMINDER) return
        val at = intent.getLongExtra(DailyReminderRuntime.EXTRA_SCHEDULED_AT, Long.MIN_VALUE)
        if (at == Long.MIN_VALUE) return

        try {
            if (DailyReminderRuntime.consumeAlarm(context, at)) {
                ReminderRuntime.requestRefresh(context, "daily-alarm")
            }
        } catch (failure: Throwable) {
            NativeDiagnostics.recordBestEffort(
                context,
                "reminder.daily_alarm.failed",
                NativeDiagnostics.failureDetails(failure),
            )
            Log.e("DiaryReminders", "Could not process daily alarm", failure)
            ReminderRuntime.requestRefresh(context, "daily-alarm-recovery")
        }
    }
}
