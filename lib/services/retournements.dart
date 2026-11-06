/// Les retournements (R41), d'après les athlètes de Magical Athlete : du
/// rattrapage pour celui qui est derrière, du risque pour celui qui ose, et
/// un journal pour comprendre ce qui s'est passé.
abstract final class Retournements {
  /// Vent dans le dos : une séance vue derrière Pop rapporte de l'audace
  /// (qui recharge les pouvoirs, R39). Comme le Lovable Loser.
  static const ventDansLeDos = 2;

  /// Pari de Sisyphe : 4 cases d'avance tout de suite, mais un film
  /// abandonné dans le mois renvoie à la case 1. Proposé la première semaine.
  static const avanceSisyphe = 4;
  static const joursSisyphe = 7;

  /// Le journal garde les 12 derniers faits du mois.
  static const tailleJournal = 12;
}
