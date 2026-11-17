package com.cashhwocky.bitfocus

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.provider.Settings
import android.text.TextUtils
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.cashhwocky.bitfocus/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(isNotificationServiceEnabled())
                "openPermissionSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }
                "getNowPlaying" -> result.success(fetchActiveMedia())
                "mediaAction" -> {
                    val action = call.argument<String>("action") ?: ""
                    performMediaAction(action)
                    result.success(true)
                }
                "loadState" -> {
                    val prefs = getSharedPreferences("bitfocus_state", Context.MODE_PRIVATE)
                    result.success(prefs.getString("json", null))
                }
                "saveState" -> {
                    val json = call.argument<String>("json") ?: ""
                    val prefs = getSharedPreferences("bitfocus_state", Context.MODE_PRIVATE)
                    prefs.edit().putString("json", json).apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val pkgName = packageName
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        if (!TextUtils.isEmpty(flat)) {
            val names = flat.split(":")
            for (name in names) {
                val cn = ComponentName.unflattenFromString(name)
                if (cn != null && TextUtils.equals(pkgName, cn.packageName)) {
                    return true
                }
            }
        }
        return false
    }

    private fun getActiveController(): MediaController? {
        if (!isNotificationServiceEnabled()) return null
        return try {
            val manager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val component = ComponentName(this, MediaSessionBridgeService::class.java)
            val controllers = manager.getActiveSessions(component)
            controllers.firstOrNull {
                it.playbackState?.state == PlaybackState.STATE_PLAYING
            } ?: controllers.firstOrNull()
        } catch (e: Exception) {
            null
        }
    }

    private fun fetchActiveMedia(): Map<String, Any?> {
        val controller = getActiveController() ?: return mapOf("active" to false)
        val metadata = controller.metadata
        val state = controller.playbackState

        val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "Unknown Track"
        val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
            ?: "Unknown Artist"
        val isPlaying = state?.state == PlaybackState.STATE_PLAYING

        var artBase64: String? = null
        val bmp = metadata?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: metadata?.getBitmap(MediaMetadata.METADATA_KEY_ART)
        if (bmp != null) {
            val scaled = Bitmap.createScaledBitmap(bmp, 140, 140, true)
            val stream = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 80, stream)
            artBase64 = Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
        }

        return mapOf(
            "active" to true,
            "title" to title,
            "artist" to artist,
            "isPlaying" to isPlaying,
            "package" to controller.packageName,
            "art" to artBase64
        )
    }

    private fun performMediaAction(action: String) {
        val controls = getActiveController()?.transportControls ?: return
        when (action) {
            "playPause" -> {
                val state = getActiveController()?.playbackState?.state
                if (state == PlaybackState.STATE_PLAYING) controls.pause() else controls.play()
            }
            "next" -> controls.skipToNext()
            "prev" -> controls.skipToPrevious()
        }
    }
}
