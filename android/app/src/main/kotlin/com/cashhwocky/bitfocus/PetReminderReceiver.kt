package com.cashhwocky.bitfocus

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.Calendar

class PetReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("enabled", false)) return
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED && action != ACTION_REMIND) return

        val hours = prefs.getInt("hours", 6)
        val name = prefs.getString("name", "your friend") ?: "your friend"

        if (action == ACTION_REMIND) {
            val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
            // quiet hours: only nudge between 9am and 10pm
            if (hour in 9..21) post(context, name)
        }
        schedule(context, hours)
    }

    companion object {
        const val PREFS = "bitfocus_pet"
        const val ACTION_REMIND = "com.cashhwocky.bitfocus.PET_REMIND"
        private const val CHANNEL_ID = "pet_reminders"

        private val MESSAGES = arrayOf(
            "%s is thinking about you",
            "%s saved you a spot. no pressure.",
            "%s would love a visit",
            "come say hi to %s",
            "%s is glad you exist",
            "%s thinks you're doing okay. come say hi."
        )

        private fun pending(context: Context): PendingIntent {
            val i = Intent(context, PetReminderReceiver::class.java).setAction(ACTION_REMIND)
            return PendingIntent.getBroadcast(
                context, 7, i,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }

        fun schedule(context: Context, hours: Int) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val trigger = System.currentTimeMillis() + hours * 3600_000L
            am.setAndAllowWhileIdle(AlarmManager.RTC, trigger, pending(context))
        }

        fun cancel(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(pending(context))
        }

        private fun post(context: Context, name: String) {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "friend reminders", NotificationManager.IMPORTANCE_DEFAULT)
            )
            val open = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pi = PendingIntent.getActivity(
                context, 0, open,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val text = String.format(MESSAGES.random(), name)
            val n = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_launcher_foreground)
                .setContentTitle(name)
                .setContentText(text)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build()
            try {
                nm.notify(1001, n)
            } catch (e: Exception) {
            }
        }
    }
}
