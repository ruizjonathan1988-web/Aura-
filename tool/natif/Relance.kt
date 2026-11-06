package PAQUET

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/// Après une mise à jour, Android ferme Aura et ne la rouvre pas. Ce
/// récepteur reçoit « mon paquet vient d'être remplacé » : il rouvre Aura
/// quand Android le permet, et laisse sinon une notification « Aura est à
/// jour, touche pour l'ouvrir ».
class Relance : BroadcastReceiver() {
    override fun onReceive(contexte: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val ouvrir = contexte.packageManager.getLaunchIntentForPackage(contexte.packageName) ?: return
        ouvrir.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        try {
            contexte.startActivity(ouvrir)
        } catch (e: Exception) {
        }
        try {
            val gestionnaire = contexte.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                gestionnaire.createNotificationChannel(NotificationChannel("mise_a_jour", "Mises à jour", NotificationManager.IMPORTANCE_DEFAULT))
            }
            val drapeaux = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_UPDATE_CURRENT
            val toucher = PendingIntent.getActivity(contexte, 7, ouvrir, drapeaux)
            val constructeur = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(contexte, "mise_a_jour") else @Suppress("DEPRECATION") Notification.Builder(contexte)
            val notification = constructeur
                .setSmallIcon(contexte.applicationInfo.icon)
                .setContentTitle("Aura est à jour")
                .setContentText("Touche pour rouvrir le jeu.")
                .setContentIntent(toucher)
                .setAutoCancel(true)
                .build()
            gestionnaire.notify(77, notification)
        } catch (e: Exception) {
        }
    }
}
