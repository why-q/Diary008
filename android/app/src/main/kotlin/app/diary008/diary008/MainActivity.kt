package app.diary008.diary008

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.Display
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private data class PendingDiagnosticsExport(
        val result: MethodChannel.Result,
        var snapshot: ByteArray? = null,
    )

    private var pendingDiagnosticsExport: PendingDiagnosticsExport? = null
    private var diagnosticsChannel: MethodChannel? = null
    private var backupDocuments: BackupDocuments? = null

    companion object {
        private const val CREATE_DIAGNOSTICS_DOCUMENT_REQUEST = 8081
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
    }

    private fun requestHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        runCatching {
            val activeMode = display?.mode ?: return
            val higherMode = display.supportedModes
                .asSequence()
                .filter {
                    it.physicalWidth == activeMode.physicalWidth &&
                        it.physicalHeight == activeMode.physicalHeight &&
                        it.refreshRate > activeMode.refreshRate &&
                        it.modeId != activeMode.modeId
                }
                .maxByOrNull(Display.Mode::getRefreshRate) ?: return
            window?.attributes = window.attributes.apply {
                preferredDisplayModeId = higherMode.modeId
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (backupDocuments?.onActivityResult(requestCode, resultCode, data) == true) return
        if (requestCode != CREATE_DIAGNOSTICS_DOCUMENT_REQUEST) return

        val pending = pendingDiagnosticsExport ?: return
        if (resultCode != Activity.RESULT_OK) {
            completeDiagnosticsExport(pending, false)
            return
        }

        val uri: Uri = data?.data ?: run {
            failDiagnosticsExport(
                pending,
                "diagnostics_export_missing_document",
                "Document picker returned no document",
            )
            return
        }
        val snapshot = pending.snapshot ?: ByteArray(0)
        NativeDiagnostics.writeSnapshot(applicationContext, uri, snapshot) { failure ->
            runOnUiThread {
                if (failure == null) {
                    completeDiagnosticsExport(pending, true)
                } else {
                    failDiagnosticsExport(
                        pending,
                        "diagnostics_export_write_failed",
                        "Unable to write diagnostic snapshot",
                        NativeDiagnostics.failureDetails(failure),
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        backupDocuments?.close()
        backupDocuments = null
        ReminderRuntime.releaseDestructionBarrier(reminderChannel, this)
        pendingDiagnosticsExport?.let { pending ->
            failDiagnosticsExport(
                pending,
                "diagnostics_activity_destroyed",
                "Diagnostics export was interrupted because the activity was destroyed",
            )
        }
        super.onDestroy()
    }

    private fun requestDiagnosticsExport(result: MethodChannel.Result) {
        if (isFinishing || isDestroyed) {
            result.error(
                "diagnostics_activity_unavailable",
                "Diagnostics export requires an active foreground activity",
                null,
            )
            return
        }
        if (pendingDiagnosticsExport != null) {
            result.error(
                "diagnostics_export_in_progress",
                "A diagnostics export is already in progress",
                null,
            )
            return
        }

        val pending = PendingDiagnosticsExport(result)
        pendingDiagnosticsExport = pending
        try {
            NativeDiagnostics.snapshot(this) { snapshot, failure ->
                runOnUiThread {
                    if (pendingDiagnosticsExport !== pending) return@runOnUiThread
                    if (failure != null) {
                        failDiagnosticsExport(
                            pending,
                            "diagnostics_export_snapshot_failed",
                            "Unable to prepare diagnostic snapshot",
                            NativeDiagnostics.failureDetails(failure),
                        )
                        return@runOnUiThread
                    }
                    if (isFinishing || isDestroyed) {
                        failDiagnosticsExport(
                            pending,
                            "diagnostics_activity_destroyed",
                            "Diagnostics export was interrupted because the activity was destroyed",
                        )
                        return@runOnUiThread
                    }

                    pending.snapshot = snapshot ?: ByteArray(0)
                    try {
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("text/plain")
                            .putExtra(Intent.EXTRA_TITLE, "Diary008-diagnostics.txt")
                        startActivityForResult(intent, CREATE_DIAGNOSTICS_DOCUMENT_REQUEST)
                    } catch (failure: Throwable) {
                        failDiagnosticsExport(
                            pending,
                            "diagnostics_export_launch_failed",
                            "Unable to open document picker",
                            NativeDiagnostics.failureDetails(failure),
                        )
                    }
                }
            }
        } catch (failure: Throwable) {
            failDiagnosticsExport(
                pending,
                "diagnostics_export_snapshot_failed",
                "Unable to prepare diagnostic snapshot",
                NativeDiagnostics.failureDetails(failure),
            )
        }
    }

    private fun completeDiagnosticsExport(pending: PendingDiagnosticsExport, exported: Boolean) {
        if (pendingDiagnosticsExport !== pending) return
        pendingDiagnosticsExport = null
        pending.result.success(exported)
    }

    private fun failDiagnosticsExport(
        pending: PendingDiagnosticsExport,
        code: String,
        message: String,
        details: String? = null,
    ) {
        if (pendingDiagnosticsExport !== pending) return
        pendingDiagnosticsExport = null
        pending.result.error(code, message, details)
    }

    private var reminderChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backupDocuments = BackupDocuments(this, flutterEngine)
        reminderChannel = ReminderRuntime.bind(
            flutterEngine,
            this,
            diagnosticsExport = ::requestDiagnosticsExport,
            onDiagnosticsChannelBound = { diagnosticsChannel = it },
        )
        ReminderRuntime.foreground = reminderChannel
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        backupDocuments?.close()
        backupDocuments = null
        ReminderRuntime.releaseDestructionBarrier(reminderChannel, this)
        if (ReminderRuntime.foreground === reminderChannel) ReminderRuntime.foreground = null
        reminderChannel?.setMethodCallHandler(null)
        diagnosticsChannel?.setMethodCallHandler(null)
        diagnosticsChannel = null
        reminderChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
