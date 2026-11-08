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
  /// code Quick Connect. Elle n'est pas écrite ici (le code est public) : la
  /// CI la donne depuis le secret GitHub VJOD_SERVEUR. Vide sans lui.
  static const serveurVjod = String.fromEnvironment('VJOD_SERVEUR');

  /// Clé d'API TMDB (v3), pour les affiches, tout le cinéma et savoir où voir
  /// chaque film en France (données JustWatch). Pas écrite ici (le code est
  /// public) : la CI la donne depuis le secret GitHub TMDB_CLE. Vide sans lui,
  /// et alors Aura se contente de la bibliothèque et de sa sélection.
  static const tmdbCle = String.fromEnvironment('TMDB_CLE');

  static bool get serveur => supabaseUrl.isNotEmpty && supabaseCle.isNotEmpty;
}
