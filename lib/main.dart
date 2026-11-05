import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'services/config.dart';
import 'services/etat.dart';
import 'services/ligues.dart';
import 'services/mesures.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ServiceLigues? ligues;
  SupabaseClient? client;
  if (Config.serveur) {
    try {
      await Supabase.initialize(url: Config.supabaseUrl, anonKey: Config.supabaseCle);
      client = Supabase.instance.client;
      ligues = ServiceLigues(client);
    } catch (_) {
      // Serveur injoignable au démarrage : on joue en solo.
    }
  }
  final etat = await EtatJeu.ouvrir(ligues: ligues);
  if (client != null) {
    etat.mesures = ServiceMesures(client, await SharedPreferences.getInstance())..ouverture();
  }
  runApp(AuraApp(etat: etat));
}
