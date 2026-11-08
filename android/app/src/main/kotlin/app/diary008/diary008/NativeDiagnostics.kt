package app.diary008.diary008

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

internal object NativeDiagnostics {
    const val CHANNEL = "app.diary008/diagnostics"

    private const val LOG_DIRECTORY = "diagnostics"
    private const val LOG_FILE = "diagnostics.log"
    private const val ROTATED_FILE_COUNT = 2
    private const val MAX_FILE_BYTES = 256 * 1024L
    private const val MAX_ENTRY_BYTES = 8 * 1024
    private const val MAX_EVENT_CHARS = 160
    private const val MAX_DETAILS_CHARS = 1_500

    private val io = Executors.newSingleThreadExecutor { task ->
        Thread(task, "native-diagnostics-io").apply { isDaemon = true }
    }
    private val exportIo = Executors.newSingleThreadExecutor { task ->
        Thread(task, "native-diagnostics-export-io").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private var cachedDeviceHeader: String? = null

    fun bind(
        engine: FlutterEngine,
        context: Context,
        export: ((MethodChannel.Result) -> Unit)? = null,
    ): MethodChannel {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        val appContext = context.applicationContext ?: context
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "record" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val event = arguments?.get("event") as? String
                    val details = arguments?.get("details") as? String
                    if (event == null || details == null) {
                        result.error(
                            "invalid_diagnostics_record",
                            "A diagnostic event and details string are required",
                            null,
                        )
                    } else {
                        record(appContext, event, details) { failure ->
                            if (failure == null) result.success(null)
                            else result.error(
                                "diagnostics_io_error",
                                "Unable to record diagnostic event",
                                failureDetails(failure),
                            )
                        }
                    }
                }
                "clear" -> clear(appContext) { failure ->
                    if (failure == null) result.success(null)
                    else result.error(
                        "diagnostics_io_error",
                        "Unable to clear diagnostic logs",
                        failureDetails(failure),
                    )
                }
                "export" -> {
                    if (export == null) {
                        result.error(
                            "diagnostics_activity_unavailable",
                            "Diagnostics export requires the foreground activity",
                            null,
                        )
                    } else {
                        export(result)
                    }
                }
                else -> result.notImplemented()
            }
        }
        return channel
    }

    fun recordBestEffort(context: Context, event: String, details: String = "") {
        val appContext = try {
            context.applicationContext ?: context
        } catch (_: Throwable) {
            context
        }
        try {
            io.execute {
                try {
                    append(appContext, event, details)
                } catch (_: Throwable) {
                    // Diagnostics must never become a failure path for the app or its jobs.
                }
            }
        } catch (_: Throwable) {
            // The executor is process-lived, but a rejected task must still be harmless.
        }
    }

    fun record(
        context: Context,
        event: String,
        details: String,
        complete: (Throwable?) -> Unit,
    ) {
        submit(complete) { append(context, event, details) }
    }

    fun clear(context: Context, complete: (Throwable?) -> Unit) {
        submit(complete) {
            val directory = logDirectory(context)
            val files = directory.listFiles()
                ?: throw IOException("Could not enumerate diagnostic logs")
            for (file in files) {
                if ((file.name == LOG_FILE || file.name.startsWith("$LOG_FILE.")) && file.isFile) {
                    if (!file.delete()) throw IOException("Could not remove diagnostic log")
                }
            }
        }
    }

    fun snapshot(context: Context, complete: (ByteArray?, Throwable?) -> Unit) {
        var snapshot: ByteArray? = null
        submit({ failure -> complete(snapshot, failure) }) {
            snapshot = readSnapshot(context)
        }
    }

    fun writeSnapshot(
        context: Context,
        uri: Uri,
        snapshot: ByteArray,
        complete: (Throwable?) -> Unit,
    ) {
        submitOn(exportIo, complete) {
            val resolver: ContentResolver = context.contentResolver
            val output = resolver.openOutputStream(uri, "w")
                ?: throw IOException("Document provider returned no output stream")
            output.use { it.write(snapshot) }
        }
    }

    fun failureDetails(failure: Throwable): String = buildString {
        append(failure.javaClass.name)
        for (frame in failure.stackTrace) {
            append('\n')
            append(frame.toString())
        }
    }

    private fun submit(complete: (Throwable?) -> Unit, operation: () -> Unit) {
        submitOn(io, complete, operation)
    }

    private fun submitOn(
        executor: ExecutorService,
        complete: (Throwable?) -> Unit,
        operation: () -> Unit,
    ) {
        val finishOnMain: (Throwable?) -> Unit = { failure ->
            mainHandler.post {
                try {
                    complete(failure)
                } catch (_: Throwable) {
                    // A destroyed engine/activity may no longer accept its channel reply.
                }
            }
        }
        try {
            executor.execute {
                val failure = try {
                    operation()
                    null
                } catch (failure: Throwable) {
                    failure
                }
                finishOnMain(failure)
            }
        } catch (failure: Throwable) {
            finishOnMain(failure)
        }
    }

    private fun append(context: Context, event: String, details: String) {
        val directory = logDirectory(context)
        val current = File(directory, LOG_FILE)
        val line = formatLine(context, event, details)
        if (current.exists() && current.length() + line.size > MAX_FILE_BYTES) {
            rotate(directory, current)
        }
        FileOutputStream(current, true).use { it.write(line) }
    }

    private fun formatLine(context: Context, event: String, details: String): ByteArray {
        val timestamp = Instant.ofEpochMilli(System.currentTimeMillis()).toString()
        val safeEvent = singleLine(event, MAX_EVENT_CHARS)
        val safeDetails = singleLine(details, MAX_DETAILS_CHARS)
        val line = "$timestamp\t${deviceHeader(context)}\t$safeEvent\t$safeDetails\n"
            .toByteArray(StandardCharsets.UTF_8)
        if (line.size > MAX_ENTRY_BYTES) throw IOException("Diagnostic entry exceeded its size limit")
        return line
    }

    private fun deviceHeader(context: Context): String {
        cachedDeviceHeader?.let { return it }
        val model = singleLine(Build.MODEL ?: "unknown", 48)
        val appVersion = try {
            val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
            singleLine(packageInfo.versionName ?: packageInfo.versionCode.toString(), 48)
        } catch (_: Throwable) {
            "unknown"
        }
        val header = "sdk=${Build.VERSION.SDK_INT} model=$model app=$appVersion"
        cachedDeviceHeader = header
        return header
    }

    private fun singleLine(value: String, maxChars: Int): String {
        val output = StringBuilder(minOf(value.length, maxChars))
        for (character in value) {
            when (character) {
                '\n' -> {
                    if (output.length + 2 > maxChars) break
                    output.append("\\n")
                }
                '\r' -> {
                    if (output.length + 2 > maxChars) break
                    output.append("\\r")
                }
                '\t' -> {
                    if (output.length + 1 > maxChars) break
                    output.append(' ')
                }
                else -> if (!Character.isISOControl(character)) {
                    if (output.length + 1 > maxChars) break
                    output.append(character)
                }
            }
        }
        return output.toString()
    }

    private fun rotate(directory: File, current: File) {
        for (index in ROTATED_FILE_COUNT downTo 1) {
            val source = if (index == 1) current else rotatedFile(directory, index - 1)
            val destination = rotatedFile(directory, index)
            if (!source.exists()) continue
            if (destination.exists() && !destination.delete()) {
                throw IOException("Could not rotate diagnostic log")
            }
            if (!source.renameTo(destination)) {
                throw IOException("Could not rotate diagnostic log")
            }
        }
    }

    private fun readSnapshot(context: Context): ByteArray {
        val directory = logDirectory(context)
        val output = ByteArrayOutputStream()
        for (index in ROTATED_FILE_COUNT downTo 1) {
            val file = rotatedFile(directory, index)
            if (file.isFile) file.inputStream().use { it.copyTo(output) }
        }
        val current = File(directory, LOG_FILE)
        if (current.isFile) current.inputStream().use { it.copyTo(output) }
        return output.toByteArray()
    }

    private fun logDirectory(context: Context): File {
        val directory = File(context.applicationContext.noBackupFilesDir, LOG_DIRECTORY)
        if (!directory.isDirectory && !directory.mkdirs() && !directory.isDirectory) {
            throw IOException("Could not create diagnostic log directory")
        }
        return directory
    }


    private fun rotatedFile(directory: File, index: Int): File =
        File(directory, "$LOG_FILE.$index")
}
