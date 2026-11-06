import '../models/modeles.dart';

/// « Tu te mets combien ? », à la façon de TTMC : avant le tirage, le joueur
/// annonce un niveau de 1 à 10. Plus il vise haut, plus les films sont
/// difficiles (peu connus, anciens, lointains, longs), et plus le billet
/// rapporte de cases. Comme à TTMC, viser haut a un prix : à partir de 9,
/// abandonner le film fait reculer.
abstract final class Niveau {
  static const min = 1;
  static const max = 10;

  /// Les cases gagnées une fois le film vu : 1 à 3 : 1, 4 à 6 : 2, 7 à 9 : 3,
  /// 10 : 4 (le seul moyen de dépasser le plafond du jour).
  static int cases(int n) => n <= 3 ? 1 : (n <= 6 ? 2 : (n <= 9 ? 3 : 4));

  /// Le plafond de cases du jour pour un billet de ce niveau.
  static int plafond(int? n) => n == 10 ? 4 : 3;

  /// Ce que coûte un film abandonné : 1 case à 9, 2 cases à 10.
  static int recul(int? n) => n == 10 ? 2 : (n == 9 ? 1 : 0);

  /// Les points d'audace d'un billet : son niveau, doublé à 9 et 10 (l'étoile
  /// d'audace). Ils départagent les égalités et rechargent les pouvoirs.
  static int audace(int n) => n >= 9 ? 2 * n : n;

  /// Le risque du niveau, en une ligne pour l'écran.
  static String risque(int n) => switch (n) {
        <= 6 => 'Aucun risque.',
        <= 8 => 'Si tu abandonnes le film : rien.',
        9 => 'Si tu abandonnes le film : tu recules d\'une case.',
        _ => 'Si tu abandonnes le film : tu recules de deux cases.',
      };

  static String nom(int n) => switch (n) {
        <= 3 => 'Tranquille',
        <= 6 => 'Curieux',
        <= 9 => 'Audacieux',
        _ => 'Coup d\'audace',
      };

  /// Ce que le niveau promet, en une ligne pour l'écran.
  static String promesse(int n) => switch (n) {
        <= 3 => 'Des films connus et faciles à regarder.',
        <= 6 => 'Un peu de dépaysement : moins connu, plus ancien ou plus lointain.',
        <= 9 => 'Des films rares, anciens ou venus de loin. Sous-titres probables.',
        _ => 'Le plus difficile que j\'aie en stock. Un trophée si tu vas au bout.',
      };

  static const _paysFamiliers = {'france', 'états-unis', 'etats-unis', 'usa', 'united states of america', 'united states', 'royaume-uni', 'united kingdom', 'belgique', 'canada'};

  /// La difficulté d'un film, de 0 (tout le monde l'a vu) à 1 (pépite rare).
  /// Notoriété (nombre d'avis), âge, pays et durée.
  static double difficulte(Film f) {
    final v = f.nombreVotes;
    final notoriete = v == null ? .3 : (v >= 20000 ? 0.0 : v >= 5000 ? .3 : v >= 1000 ? .65 : 1.0);
    final a = f.annee;
    final age = a == null ? .3 : (a < 1960 ? 1.0 : a < 1980 ? .7 : a < 2000 ? .4 : a < 2010 ? .2 : 0.0);
    final lointain = f.pays.isEmpty ? .3 : (f.pays.any((p) => _paysFamiliers.contains(p.toLowerCase())) ? 0.0 : 1.0);
    final d = f.dureeMinutes;
    final longueur = d == null ? 0.0 : (d > 150 ? 1.0 : d > 120 ? .5 : 0.0);
    return .35 * notoriete + .3 * age + .2 * lointain + .15 * longueur;
  }

  /// Le niveau d'un film, de 1 à 10.
  static int de(Film f) => (1 + (difficulte(f) * 9).round()).clamp(min, max);

  /// Les films les plus proches du niveau annoncé : l'écart toléré s'élargit
  /// jusqu'à en avoir au moins [assez].
  static List<Film> proches(List<Film> films, int n, {int assez = 9}) {
    for (var ecart = 1; ecart < max; ecart++) {
      final pris = films.where((f) => (de(f) - n).abs() <= ecart).toList();
      if (pris.length >= assez || ecart == max - 1) return pris;
    }
    return films;
  }

  /// Le niveau qu'Aura propose ce soir, d'après les dernières séances : la
  /// moyenne des cinq derniers niveaux réussis, un cran de plus après deux
  /// réussites à ce niveau ou au-dessus, un cran de moins après un abandon
  /// à ce niveau. Au tout début : 3. Les listes vont du plus récent au plus
  /// ancien.
  static int propose({required List<int> reussis, List<int> abandonnes = const []}) {
    if (reussis.isEmpty) return abandonnes.isEmpty ? 3 : (abandonnes.first - 1).clamp(min, 3);
    final recents = reussis.take(5).toList();
    var n = (recents.reduce((a, b) => a + b) / recents.length).round();
    if (reussis.length >= 2 && reussis.take(2).every((r) => r >= n)) n++;
    if (abandonnes.isNotEmpty && abandonnes.first >= n) n--;
    return n.clamp(min, max);
  }
}
