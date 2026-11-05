/// Les genres et les pays tels que Jellyfin ou TMDB les donnent (souvent en
/// anglais), traduits pour l'écran. Ce qu'on ne connaît pas reste tel quel.
abstract final class Traduction {
  static const _genres = {
    'action': 'action',
    'adventure': 'aventure',
    'animation': 'animation',
    'comedy': 'comédie',
    'crime': 'policier',
    'documentary': 'documentaire',
    'drama': 'drame',
    'family': 'familial',
    'fantasy': 'fantastique',
    'history': 'historique',
    'horror': 'horreur',
    'music': 'musical',
    'musical': 'comédie musicale',
    'mystery': 'mystère',
    'romance': 'romance',
    'science fiction': 'science-fiction',
    'sci-fi': 'science-fiction',
    'thriller': 'thriller',
    'war': 'guerre',
    'western': 'western',
  };

  static const _pays = {
    'united states of america': 'États-Unis',
    'united states': 'États-Unis',
    'usa': 'États-Unis',
    'united kingdom': 'Royaume-Uni',
    'france': 'France',
    'germany': 'Allemagne',
    'italy': 'Italie',
    'spain': 'Espagne',
    'japan': 'Japon',
    'south korea': 'Corée du Sud',
    'korea, republic of': 'Corée du Sud',
    'china': 'Chine',
    'hong kong': 'Hong Kong',
    'india': 'Inde',
    'iran': 'Iran',
    'iran, islamic republic of': 'Iran',
    'mexico': 'Mexique',
    'brazil': 'Brésil',
    'argentina': 'Argentine',
    'canada': 'Canada',
    'australia': 'Australie',
    'new zealand': 'Nouvelle-Zélande',
    'belgium': 'Belgique',
    'switzerland': 'Suisse',
    'denmark': 'Danemark',
    'sweden': 'Suède',
    'norway': 'Norvège',
    'russia': 'Russie',
    'poland': 'Pologne',
    'ireland': 'Irlande',
    'taiwan': 'Taïwan',
  };

  /// « Crime » devient « policier ».
  static String genre(String g) => _genres[g.toLowerCase()] ?? g.toLowerCase();

  /// « United States of America » devient « États-Unis ».
  static String pays(String p) => _pays[p.toLowerCase()] ?? p;

  /// « 105 » devient « 1 h 45 ».
  static String duree(int minutes) =>
      minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
}
