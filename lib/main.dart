import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'services/etat.dart';

/// Les clés Supabase arrivent à la compilation :
///   flutter build apk --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…
/// Sans elles, Aura tourne en solo, sans compte.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseCle = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isNotEmpty && _supabaseCle.isNotEmpty) {
    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseCle);
  }
  final etat = await EtatJeu.ouvrir();
  runApp(AuraApp(etat: etat));
}
