package PAQUET

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

/// La mise à jour d'Aura, comme celle de VJOD : l'APK téléchargé par l'appli
/// est donné à l'installeur d'Android, sans navigateur ni Downloader.
object MiseAJour {
    private const val CANAL = "fr.vjod.aura/mise_a_jour"
    private const val ETAT = "fr.vjod.aura.MISE_A_JOUR"

    private var canal: MethodChannel? = null

    fun brancher(activite: Activity, moteur: FlutterEngine) {
        val c = MethodChannel(moteur.dartExecutor.binaryMessenger, CANAL)
        canal = c
        c.setMethodCallHandler { appel, resultat ->
            when (appel.method) {
                "installeeLe" -> resultat.success(installeeLe(activite))
                "dossier" -> resultat.success(activite.cacheDir.absolutePath)
                "peutInstaller" -> resultat.success(peutInstaller(activite))
                "ouvrirReglages" -> resultat.success(ouvrirReglages(activite))
                "installer" -> {
                    val chemin = appel.argument<String>("chemin")
                    if (chemin == null) resultat.error("sans_chemin", "chemin manquant", null)
                    else installer(activite, chemin, resultat)
                }
                else -> resultat.notImplemented()
            }
        }
    }

    /// Quand cette copie a été installée ou mise à jour, en millisecondes.
    private fun installeeLe(activite: Activity): Long = try {
        @Suppress("DEPRECATION")
        activite.packageManager.getPackageInfo(activite.packageName, 0).lastUpdateTime
    } catch (e: Exception) {
        0L
    }

    private fun peutInstaller(activite: Activity): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                activite.packageManager.canRequestPackageInstalls()
            } catch (e: Exception) {
                true
            }
        } else {
            true
        }

    /// La page « Installer des applis inconnues » d'Aura, sinon les options
    /// pour les développeurs (où Fire OS la range), sinon les réglages.
    private fun ouvrirReglages(activite: Activity): Boolean {
        val cibles = mutableListOf<Intent>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            cibles.add(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + activite.packageName)))
        }
        cibles.add(Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS))
        cibles.add(Intent(Settings.ACTION_SETTINGS))
        for (intent in cibles) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                activite.startActivity(intent)
                return true
            } catch (e: Exception) {
            }
        }
        return false
    }

    private fun installer(activite: Activity, chemin: String, resultat: MethodChannel.Result) {
        thread(name = "aura-mise-a-jour") {
            try {
                val installeur = activite.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                // Android 12+ : Aura se met à jour sans redemander, une fois qu'il
                // s'est installé lui-même ; ailleurs, Android demande comme d'habitude.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
                }
                val id = installeur.createSession(params)
                val session = installeur.openSession(id)
                try {
                    File(chemin).inputStream().use { entree ->
                        session.openWrite("aura.apk", 0, -1).use { sortie ->
                            entree.copyTo(sortie)
                            session.fsync(sortie)
                        }
                    }
                    val etat = Intent(activite, activite.javaClass).setAction(ETAT)
                    val drapeaux = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }
                    session.commit(PendingIntent.getActivity(activite, id, etat, drapeaux).intentSender)
                } finally {
                    session.close()
                }
                activite.runOnUiThread { resultat.success(true) }
            } catch (e: Exception) {
                activite.runOnUiThread { resultat.error("installation", e.message, null) }
            }
        }
    }

    /// La réponse de l'installeur revient à l'activité. S'il faut confirmer,
    /// elle porte l'écran à montrer.
    fun reponse(activite: Activity, intent: Intent?): Boolean {
        if (intent?.action != ETAT) return false
        val statut = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        if (statut != PackageInstaller.STATUS_PENDING_USER_ACTION && statut != PackageInstaller.STATUS_SUCCESS) {
            // L'installation a échoué : on le dit à l'appli, avec la raison d'Android.
            val raison = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: ""
            try {
                canal?.invokeMethod("echec", mapOf("statut" to statut, "raison" to raison))
            } catch (e: Exception) {
            }
        }
        if (statut == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val confirmer: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_INTENT)
            }
            if (confirmer != null) {
                confirmer.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    activite.startActivity(confirmer)
                } catch (e: Exception) {
                }
            }
        }
        return true
    }
}
