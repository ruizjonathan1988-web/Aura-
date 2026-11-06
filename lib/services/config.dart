/// Le serveur des ligues (Supabase).
///
/// L'adresse et la clé « anon » sont publiques par nature : elles finissent
/// dans l'APK et dans la version web. Ce sont les règles de sécurité des
/// tables (RLS, voir supabase/migrations) qui protègent les données.
/// Ne jamais mettre ici la clé « service_role ».
///
/// Des secrets GitHub SUPABASE_URL et SUPABASE_ANON_KEY, s'ils existent,
/// passent avant ces valeurs (--dart-define à la compilation).
abstract final class Config {
  static const _urlCompilee = String.fromEnvironment('SUPABASE_URL');
  static const _cleCompilee = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const supabaseUrl = _urlCompilee != '' ? _urlCompilee : 'https://trjocwmslkxtluuhsvgx.supabase.co';
  static const supabaseCle = _cleCompilee != ''
      ? _cleCompilee
      : 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRyam9jd21zbGt4dGx1dWhzdmd4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM5MTE2MzksImV4cCI6MjEwOTQ4NzYzOX0.dIR1DCJAY9C1tQn_--oPw3m9eebTNMT6M7E6K7OmQOc';

  /// L'adresse du serveur VJOD (Jellyfin) proposée par défaut aux joueurs,
  /// pour qu'ils n'aient qu'à se connecter avec leur identifiant VJOD ou un
  /// code Quick Connect. Remplaçable à la compilation (VJOD_SERVEUR).
  static const _serveurCompile = String.fromEnvironment('VJOD_SERVEUR');
  static const serveurVjod = _serveurCompile != '' ? _serveurCompile : 'https://ava88.zen.usbx.me/jellyfin';

  /// Clé d'API TMDB (v3) de Jon, pour savoir où voir chaque film en France
  /// (données JustWatch). Comme toute clé embarquée dans une appli, elle est
  /// lisible dans l'APK ; TMDB demande un accord pour un usage commercial.
  static const _tmdbCompilee = String.fromEnvironment('TMDB_CLE');
  static const tmdbCle = _tmdbCompilee != '' ? _tmdbCompilee : '023cad9ee7899502258706fa4e93c19d';

  static bool get serveur => supabaseUrl.isNotEmpty && supabaseCle.isNotEmpty;
}
