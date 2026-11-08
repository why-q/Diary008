package app.diary008.diary008

import android.app.Activity
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

object ReminderRuntime {
    const val CHANNEL = "app.diary008/reminder_runtime"
    var foreground: MethodChannel? = null

    private var destructionOwner: MethodChannel? = null
    private var deferredRefresh = false
    private var activeJobService: ReminderRescheduleJob? = null

    fun bind(
        engine: FlutterEngine,
        context: Context,
        complete: ((Boolean) -> Unit)? = null,
        diagnosticsExport: ((MethodChannel.Result) -> Unit)? = null,
        onDiagnosticsChannelBound: ((MethodChannel) -> Unit)? = null,
    ): MethodChannel {
        val diagnosticsChannel = NativeDiagnostics.bind(engine, context, diagnosticsExport)
        onDiagnosticsChannelBound?.invoke(diagnosticsChannel)
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "timeZone" -> {
                    TimeZone.setDefault(null)
                    result.success(TimeZone.getDefault().id)
                }
                "supportsRuntimeNotificationPermission" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
                )
                "openNotificationSettings" -> result.success(
                    openNotificationSettings(context, call.arguments as? String),
                )
                "complete" -> {
                    result.success(null)
                    complete?.invoke(call.arguments == true)
                }
                "beginDestruction" -> handleDestructionCall(channel, context, result, begin = true)
                "endDestruction" -> handleDestructionCall(channel, context, result, begin = false)
                "scheduleDailyReminder",
                "cancelDailyReminder",
                "completeDailyReminder",
                "dailyReminderState" -> handleDailyReminderCall(call, context, result)
                else -> result.notImplemented()
            }
        }
        return channel
    }

    private fun openNotificationSettings(context: Context, channelId: String?): Boolean {
        val packageName = context.packageName
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (channelId != null) {
                val channelSettings = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    .putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
                if (startSettingsActivity(context, channelSettings)) return true
            }

            val appSettings = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            if (startSettingsActivity(context, appSettings)) return true
        }

        val appDetails = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:$packageName"))
        if (startSettingsActivity(context, appDetails)) return true

        NativeDiagnostics.recordBestEffort(
            context,
            "reminder.permission_settings.failed",
            "channel=${channelId ?: "app"}",
        )
        return false
    }

    private fun startSettingsActivity(context: Context, intent: Intent): Boolean {
        if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun handleDailyReminderCall(
        call: MethodCall,
        context: Context,
        result: MethodChannel.Result,
    ) {
        try {
            when (call.method) {
                "scheduleDailyReminder" -> {
                    val at = (call.arguments as? Map<*, *>)?.get("at") as? Number
                    if (at == null) {
                        result.error("invalid_arguments", "Missing daily reminder epoch", null)
                    } else {
                        DailyReminderRuntime.schedule(context, at.toLong())
                        result.success(null)
                    }
                }
                "cancelDailyReminder" -> {
                    DailyReminderRuntime.cancel(context)
                    result.success(null)
                }
                "completeDailyReminder" -> {
                    val at = call.arguments as? Number
                    if (at == null) {
                        result.error("invalid_arguments", "Missing daily reminder epoch", null)
                    } else {
                        result.success(DailyReminderRuntime.complete(context, at.toLong()))
                    }
                }
                "dailyReminderState" -> result.success(DailyReminderRuntime.state(context))
                else -> result.notImplemented()
            }
        } catch (failure: Throwable) {
            result.error(
                "daily_reminder_failed",
                "Unable to process ${call.method}",
                NativeDiagnostics.failureDetails(failure),
            )
        }
    }

    fun requestRefresh(context: Context, source: String) {
        if (isDestructionInProgress()) {
            deferredRefresh = true
            NativeDiagnostics.recordBestEffort(context, "reminder.schedule.requested", "source=$source")
            NativeDiagnostics.recordBestEffort(context, "reminder.schedule.result", "result=deferred")
            return
        }
        scheduleRefreshJob(context, source)
    }

    fun isDestructionInProgress(): Boolean = destructionOwner != null

    fun registerJobService(service: ReminderRescheduleJob) {
        activeJobService = service
    }

    fun unregisterJobService(service: ReminderRescheduleJob) {
        if (activeJobService === service) activeJobService = null
    }

    fun deferRefreshForBarrier(context: Context) {
        deferredRefresh = true
        NativeDiagnostics.recordBestEffort(context, "reminder.job.deferred", "reason=destruction")
    }

    private fun handleDestructionCall(
        channel: MethodChannel,
        context: Context,
        result: MethodChannel.Result,
        begin: Boolean,
    ) {
        if (foreground !== channel) {
            result.error(
                "destruction_barrier_foreground_only",
                "The destruction barrier is available only to the foreground engine",
                null,
            )
            return
        }
        try {
            if (begin) beginDestruction(context, channel) else endDestruction(context, channel)
            result.success(null)
        } catch (failure: Throwable) {
            result.error(
                "destruction_barrier_failed",
                if (begin) "Unable to begin reminder destruction barrier" else "Unable to end reminder destruction barrier",
                NativeDiagnostics.failureDetails(failure),
            )
        }
    }

    private fun beginDestruction(context: Context, owner: MethodChannel) {
        requireMainThread()
        check(destructionOwner == null) { "A destruction barrier is already active" }

        destructionOwner = owner
        deferredRefresh = true
        NativeDiagnostics.recordBestEffort(context, "reminder.destruction.begin")

        var failure: Throwable? = null
        try {
            activeJobService?.quiesceForDestruction()
        } catch (caught: Throwable) {
            failure = caught
        }
        try {
            context.applicationContext.getSystemService(JobScheduler::class.java).cancel(808)
        } catch (caught: Throwable) {
            if (failure == null) failure = caught
        }
        if (failure != null) {
            destructionOwner = null
            NativeDiagnostics.recordBestEffort(context, "reminder.destruction.begin_failed")
            if (deferredRefresh) scheduleRefreshJob(context, "destruction-begin-failed")
            throw failure
        }
    }

    private fun endDestruction(context: Context, owner: MethodChannel) {
        requireMainThread()
        check(destructionOwner === owner) {
            "The calling engine does not own the destruction barrier"
        }
        destructionOwner = null
        NativeDiagnostics.recordBestEffort(context, "reminder.destruction.end")
        if (deferredRefresh) scheduleRefreshJob(context, "destruction-ended")
    }

    fun releaseDestructionBarrier(owner: MethodChannel?, context: Context) {
        if (owner == null || destructionOwner !== owner) return
        requireMainThread()
        destructionOwner = null
        NativeDiagnostics.recordBestEffort(context, "reminder.destruction.released", "reason=engine_destroyed")
        if (deferredRefresh) scheduleRefreshJob(context, "engine-destroyed")
    }

    private fun scheduleRefreshJob(context: Context, source: String): Boolean {
        NativeDiagnostics.recordBestEffort(context, "reminder.schedule.requested", "source=$source")
        return try {
            val job = JobInfo.Builder(808, ComponentName(context, ReminderRescheduleJob::class.java))
                .setExtras(PersistableBundle().apply {
                    putLong("generation", SystemClock.elapsedRealtimeNanos())
                })
                .setOverrideDeadline(0)
                .build()
            val result = context.getSystemService(JobScheduler::class.java).schedule(job)
            val scheduled = result != JobScheduler.RESULT_FAILURE
            NativeDiagnostics.recordBestEffort(
                context,
                "reminder.schedule.result",
                if (scheduled) "result=success" else "result=failure",
            )
            deferredRefresh = !scheduled
            if (!scheduled) Log.e("DiaryReminders", "Could not schedule timezone refresh")
            scheduled
        } catch (failure: Throwable) {
            deferredRefresh = true
            NativeDiagnostics.recordBestEffort(
                context,
                "reminder.schedule.failed",
                NativeDiagnostics.failureDetails(failure),
            )
            Log.e("DiaryReminders", "Could not schedule timezone refresh")
            false
        }
    }

    private fun requireMainThread() {
        check(Looper.myLooper() == Looper.getMainLooper()) {
            "Destruction barrier operations must run on the main thread"
        }
    }
}

class ReminderTimeChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        NativeDiagnostics.recordBestEffort(
            context,
            "reminder.broadcast.received",
            "action=${intent.action ?: "unknown"}",
        )
        if (intent.action !in setOf(
                Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                "android.intent.action.QUICKBOOT_POWERON", "com.htc.intent.action.QUICKBOOT_POWERON"
            )) {
            NativeDiagnostics.recordBestEffort(context, "reminder.broadcast.ignored")
            return
        }
        ReminderRuntime.requestRefresh(context, "broadcast")
    }
}

class ReminderRescheduleJob : JobService() {
    private val handler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var parameters: JobParameters? = null

    override fun onStartJob(params: JobParameters): Boolean {
        NativeDiagnostics.recordBestEffort(this, "reminder.job.start")
        ReminderRuntime.registerJobService(this)
        if (ReminderRuntime.isDestructionInProgress()) {
            ReminderRuntime.deferRefreshForBarrier(this)
            ReminderRuntime.unregisterJobService(this)
            return false
        }

        parameters = params
        handler.post {
            if (parameters !== params) return@post
            val previous = engine
            engine = null
            previous?.destroy()
            if (ReminderRuntime.isDestructionInProgress()) {
                deferForDestruction(params)
                return@post
            }
            startWork(params)
        }
        return true
    }

    private fun startWork(params: JobParameters) {
        if (parameters !== params) return
        if (ReminderRuntime.isDestructionInProgress()) {
            deferForDestruction(params)
            return
        }

        val foreground = ReminderRuntime.foreground
        NativeDiagnostics.recordBestEffort(
            this,
            "reminder.job.work.started",
            if (foreground != null) "engine=foreground" else "engine=background",
        )
        try {
            if (foreground != null) {
                foreground.invokeMethod("refresh", null, object : MethodChannel.Result {
                    override fun success(result: Any?) = finish(params, true)
                    override fun error(code: String, message: String?, details: Any?) = finish(params, false)
                    override fun notImplemented() = finish(params, false)
                })
            } else {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationCompleteAsync(applicationContext, null, handler) {
                    try {
                        if (parameters !== params) return@ensureInitializationCompleteAsync
                        if (ReminderRuntime.isDestructionInProgress()) {
                            deferForDestruction(params)
                            return@ensureInitializationCompleteAsync
                        }
                        val background = FlutterEngine(applicationContext)
                        engine = background
                        ReminderRuntime.bind(
                            background,
                            applicationContext,
                            complete = { success -> finish(params, success) },
                        )
                        background.dartExecutor.executeDartEntrypoint(
                            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "reminderBackgroundMain")
                        )
                    } catch (failure: Throwable) {
                        failWork(params, failure)
                    }
                }
            }
        } catch (failure: Throwable) {
            failWork(params, failure)
        }
    }

    private fun deferForDestruction(params: JobParameters) {
        if (parameters !== params) return
        parameters = null
        val runningEngine = engine
        engine = null
        ReminderRuntime.unregisterJobService(this)
        ReminderRuntime.deferRefreshForBarrier(this)
        var failure: Throwable? = null
        try {
            runningEngine?.destroy()
        } catch (caught: Throwable) {
            failure = caught
        }
        try {
            jobFinished(params, false)
        } catch (caught: Throwable) {
            if (failure == null) failure = caught
        }
        if (failure != null) {
            NativeDiagnostics.recordBestEffort(
                this,
                "reminder.job.stop.failed",
                NativeDiagnostics.failureDetails(failure),
            )
        }
    }

    internal fun quiesceForDestruction() {
        val activeParameters = parameters
        parameters = null
        val runningEngine = engine
        engine = null
        ReminderRuntime.unregisterJobService(this)
        NativeDiagnostics.recordBestEffort(this, "reminder.job.stop", "reason=destruction")

        var failure: Throwable? = null
        try {
            runningEngine?.destroy()
        } catch (caught: Throwable) {
            failure = caught
        }
        if (activeParameters != null) {
            try {
                jobFinished(activeParameters, false)
            } catch (caught: Throwable) {
                if (failure == null) failure = caught
            }
        }
        if (failure != null) throw failure
    }

    private fun failWork(params: JobParameters, failure: Throwable) {
        NativeDiagnostics.recordBestEffort(
            this,
            "reminder.job.work.failed",
            NativeDiagnostics.failureDetails(failure),
        )
        finish(params, false)
    }

    private fun finish(params: JobParameters, success: Boolean) {
        handler.post {
            if (parameters !== params) return@post
            if (ReminderRuntime.isDestructionInProgress()) {
                deferForDestruction(params)
                return@post
            }
            NativeDiagnostics.recordBestEffort(
                this,
                "reminder.job.finish",
                if (success) "success=true" else "success=false",
            )
            if (!success) Log.e("DiaryReminders", "Timezone refresh failed; rescheduling with JobScheduler backoff")
            parameters = null
            val completedEngine = engine
            engine = null
            ReminderRuntime.unregisterJobService(this)
            try {
                completedEngine?.destroy()
            } finally {
                jobFinished(params, !success)
            }
        }
    }

    override fun onStopJob(params: JobParameters): Boolean {
        val isActive = parameters?.extras?.getLong("generation") == params.extras.getLong("generation")
        NativeDiagnostics.recordBestEffort(
            this,
            "reminder.job.stop",
            if (isActive) "active=true" else "active=false",
        )
        if (!isActive) return false
        parameters = null
        val stopped = engine
        engine = null
        ReminderRuntime.unregisterJobService(this)
        handler.post { stopped?.destroy() }
        return true
    }
}
