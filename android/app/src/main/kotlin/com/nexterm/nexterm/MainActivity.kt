package com.nexterm.nexterm

import android.app.ActivityManager
import android.content.Intent
import android.os.Bundle
import android.os.Process
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        killSiblingNexTermProcesses()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RdpBridge(this, flutterEngine, flutterEngine.renderer).register()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexterm/ota")
            .setMethodCallHandler { call, result ->
                if (call.method == "installApk") {
                    val path = call.argument<String>("path") ?: run {
                        result.error("NO_PATH", "path is null", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        val uri = FileProvider.getUriForFile(
                            this, "${packageName}.fileprovider", file
                        )
                        launchPackageInstaller(uri)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("INSTALL_FAILED", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun launchPackageInstaller(uri: android.net.Uri) {
        try {
            startActivity(buildViewInstallIntent(uri))
        } catch (_: Exception) {
            startActivity(buildInstallIntent(uri))
        }
    }

    private fun buildInstallIntent(uri: android.net.Uri): Intent =
        Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = uri
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_RETURN_RESULT, false)
        }

    private fun buildViewInstallIntent(uri: android.net.Uri): Intent =
        Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

    private fun killSiblingNexTermProcesses() {
        val currentPid = Process.myPid()
        val currentUid = Process.myUid()
        val manager = getSystemService(ACTIVITY_SERVICE) as? ActivityManager ?: return
        val processes = manager.runningAppProcesses ?: return
        for (process in processes) {
            if (process.uid == currentUid && process.pid != currentPid && process.processName.startsWith(packageName)) {
                Process.killProcess(process.pid)
            }
        }
    }

}
