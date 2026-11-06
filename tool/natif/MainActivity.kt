package PAQUET

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MiseAJour.brancher(this, flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        if (MiseAJour.reponse(this, intent)) return
        super.onNewIntent(intent)
    }
}
