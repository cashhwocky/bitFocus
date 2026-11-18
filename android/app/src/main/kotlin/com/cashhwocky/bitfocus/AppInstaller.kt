package com.cashhwocky.bitfocus

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInstaller
import android.os.Build
import java.io.File

object AppInstaller {
    const val ACTION = "com.cashhwocky.bitfocus.INSTALL_RESULT"

    // True when running as a system / platform-signed app (uid 1000 or FLAG_SYSTEM)
    fun isSystem(ctx: Context): Boolean =
        (ctx.applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
            android.os.Process.myUid() == 1000

    // Streams the APK into a PackageInstaller session.
    // Platform-signed: installs with no prompt. Otherwise Android shows its normal confirm screen.
    fun install(ctx: Context, path: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val installer = ctx.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            params.setAppPackageName(ctx.packageName)
            if (Build.VERSION.SDK_INT >= 31) {
                params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
            val id = installer.createSession(params)
            installer.openSession(id).use { session ->
                file.inputStream().use { input ->
                    session.openWrite("bitfocus.apk", 0, file.length()).use { out ->
                        input.copyTo(out)
                        session.fsync(out)
                    }
                }
                val intent = Intent(ctx, InstallResultReceiver::class.java).setAction(ACTION)
                val pending = PendingIntent.getBroadcast(
                    ctx, id, intent,
                    PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                session.commit(pending.intentSender)
            }
            true
        } catch (e: Exception) {
            false
        }
    }
}

class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            @Suppress("DEPRECATION")
            val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            if (confirm != null) {
                confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                ctx.startActivity(confirm)
            }
        }
    }
}
