import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'services/config.dart';
import 'services/etat.dart';
import 'services/ligues.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ServiceLigues? ligues;
  if (Config.serveur) {
    try {
      await Supabase.initialize(url: Config.supabaseUrl, anonKey: Config.supabaseCle);
      ligues = ServiceLigues(Supabase.instance.client);
    } catch (_) {
      // Serveur injoignable au démarrage : on joue en solo.
    }
  }
  final etat = await EtatJeu.ouvrir(ligues: ligues);
  runApp(AuraApp(etat: etat));
}
