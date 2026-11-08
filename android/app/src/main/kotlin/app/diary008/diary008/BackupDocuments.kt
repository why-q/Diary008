package app.diary008.diary008

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors

internal class BackupDocuments(private val activity: Activity, engine: FlutterEngine) {
    private data class Pending(
        val result: MethodChannel.Result,
        val snapshot: String?,
    )

    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "app.diary008/backup")
    private val io = Executors.newSingleThreadExecutor { task ->
        Thread(task, "notebook-backup-io").apply { isDaemon = true }
    }
    private var pending: Pending? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "export" -> {
                    val snapshot = call.argument<String>("contents")
                    if (snapshot == null) {
                        result.error("backup_missing_contents", "Backup contents are required", null)
                    } else {
                        launch(result, snapshot)
                    }
                }
                "import" -> launch(result, null)
                else -> result.notImplemented()
            }
        }
    }

    private fun launch(result: MethodChannel.Result, snapshot: String?) {
        if (pending != null || activity.isFinishing || activity.isDestroyed) {
            result.error("backup_unavailable", "Backup picker is unavailable or busy", null)
            return
        }
        val operation = Pending(result, snapshot)
        pending = operation
        try {
            val intent = if (snapshot != null) {
                Intent(Intent.ACTION_CREATE_DOCUMENT)
                    .setType("application/json")
                    .putExtra(Intent.EXTRA_TITLE, "Diary008-backup-${System.currentTimeMillis()}.json")
            } else {
                Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*")
            }
            intent.addCategory(Intent.CATEGORY_OPENABLE)
            activity.startActivityForResult(intent, REQUEST)
        } catch (failure: Exception) {
            fail(operation, "backup_picker_failed")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        val operation = pending ?: return true
        if (resultCode != Activity.RESULT_OK) {
            complete(operation, if (operation.snapshot != null) false else null)
            return true
        }
        val uri = data?.data
        if (uri == null) {
            fail(operation, "backup_document_missing")
            return true
        }
        io.execute {
            try {
                val value: Any = if (operation.snapshot != null) {
                    val stream = activity.contentResolver.openOutputStream(uri, "wt")
                        ?: throw java.io.IOException("Cannot open output")
                    stream.use { it.write(operation.snapshot.toByteArray(StandardCharsets.UTF_8)) }
                    true
                } else {
                    val stream = activity.contentResolver.openInputStream(uri)
                        ?: throw java.io.IOException("Cannot open input")
                    val bytes = stream.use { it.readBytes() }
                    StandardCharsets.UTF_8.newDecoder()
                        .onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT)
                        .decode(ByteBuffer.wrap(bytes)).toString().removePrefix("\uFEFF")
                }
                activity.runOnUiThread { complete(operation, value) }
            } catch (failure: Exception) {
                activity.runOnUiThread { fail(operation, "backup_document_io_failed") }
            }
        }
        return true
    }

    private fun complete(operation: Pending, value: Any?) {
        if (pending !== operation) return
        pending = null
        operation.result.success(value)
    }

    private fun fail(operation: Pending, code: String) {
        if (pending !== operation) return
        pending = null
        operation.result.error(code, "Backup operation did not complete", null)
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pending?.let { fail(it, "backup_activity_destroyed") }
        io.shutdown()
    }

    companion object {
        private const val REQUEST = 8082
    }
}
