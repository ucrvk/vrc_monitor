package top.wenwen12305.monitor

import android.content.Intent
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "top.wenwen12305.monitor/update_installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val apkPath = call.argument<String>("apkPath")?.trim().orEmpty()
                        if (apkPath.isEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(installApk(apkPath))
                    }
                    "getAbi" -> {
                        result.success(resolveAbi())
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    private fun installApk(apkPath: String): Boolean {
        return try {
            val apkFile = File(apkPath)
            if (!apkFile.exists()) return false

            val authority = "${applicationContext.packageName}.fileprovider"
            val apkUri = FileProvider.getUriForFile(applicationContext, authority, apkFile)

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun resolveAbi(): String? {
        val supported = Build.SUPPORTED_ABIS ?: return null
        val allowed = setOf("arm64-v8a", "armeabi-v7a", "x86_64")
        return supported.firstOrNull { allowed.contains(it) }
    }
}
