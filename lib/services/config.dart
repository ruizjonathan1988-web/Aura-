/// Les clés Supabase arrivent à la compilation :
///   flutter build apk --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…
/// Sans elles, Aura tourne en solo, sans compte.
abstract final class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseCle = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get serveur => supabaseUrl.isNotEmpty && supabaseCle.isNotEmpty;
}
