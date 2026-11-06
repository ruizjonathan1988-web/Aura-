import 'deck.dart' show ContexteAtout, Deck;

/// Le Festival de la semaine (R50), comme les Boss de Balatro : chaque
/// semaine, Pop annonce une règle qui change la partie. Le même festival pour
/// tout le monde la même semaine, pour en parler en ligue. La règle ne retire
/// jamais rien : elle donne une case, fait reculer Pop, double l'audace des
/// atouts ou offre un booster. Le plafond de 3 cases par jour tient toujours.
enum EffetFestival { caseEnPlus, popRecule, audaceDouble, booster }

class Festival {
  const Festival(this.id, this.nom, this.annonce, this.regle, this.effet, this.condition);

  final String id;
  final String nom;

  /// Ce que Pop dit le lundi.
  final String annonce;

  /// La règle, en une phrase.
  final String regle;
  final EffetFestival effet;
  final bool Function(ContexteAtout c) condition;
}

abstract final class Festivals {
  static final tous = <Festival>[
    Festival('noir_blanc', 'Semaine du noir et blanc', 'Cette semaine, on enlève la couleur. Oui, c\'est voulu.', 'Un film d\'avant 1960 : +1 case.',
        EffetFestival.caseEnPlus, (c) => (c.billet.annee ?? 3000) < 1960),
    Festival('sans_comedie', 'Pop interdit les comédies', 'J\'interdis les comédies cette semaine. Je suis sérieux. Très sérieux.',
        'Regarde une comédie quand même : Pop recule d\'une case.', EffetFestival.popRecule, (c) => c.genre(const ['Comedy', 'Comédie'])),
    Festival('tour_du_monde', 'Semaine du tour du monde', 'Passeport obligatoire. Les films de chez nous et d\'Hollywood restent à la douane.',
        'Un film ni français ni américain : +1 case.', EffetFestival.caseEnPlus,
        (c) => c.billet.pays.isNotEmpty && !c.billet.pays.any((p) => p == 'France' || p == 'États-Unis' || p == 'United States of America')),
    Festival('atouts', 'Semaine des atouts', 'Sortez vos cartes. Je veux voir des combos.', 'Chaque atout déclenché rapporte le double d\'audace.',
        EffetFestival.audaceDouble, (c) => true),
    Festival('boosters', 'Semaine des boosters', 'J\'ai trouvé un carton de boosters. Je partage. Un peu.', 'Chaque film vu : un booster de plus (deux en réserve au plus).',
        EffetFestival.booster, (c) => true),
    Festival('court', 'Semaine du format court', 'Cette semaine, on va droit au but. Comme moi.', 'Un film de moins d\'1 h 40 : +1 case.', EffetFestival.caseEnPlus,
        (c) => c.dureeMinutes != null && c.dureeMinutes! < 100),
    Festival('devins', 'Semaine des devins', 'Prédis ta note. Si tu tombes juste, je recule. Je n\'ai pas peur.', 'Ta note tombe pile sur ton pronostic : Pop recule d\'une case.',
        EffetFestival.popRecule, (c) => c.billet.note != null && c.billet.note == c.billet.pronostic),
    Festival('jumeaux', 'Semaine des jumeaux', 'Deux films du même pays d\'affilée, c\'est le jackpot.', 'Le même pays que ton film d\'avant : +1 case.', EffetFestival.caseEnPlus,
        (c) => c.avant.isNotEmpty && c.billet.pays.any(c.avant.first.pays.contains)),
    Festival('frousse', 'Semaine de la frousse', 'Laisse la lumière allumée. Ou pas.', 'Un film d\'horreur ou un thriller : +1 case.', EffetFestival.caseEnPlus,
        (c) => c.genre([...Deck.horreur, 'Thriller'])),
    Festival('vhs', 'Semaine de la VHS', 'Rembobine. On revient dans les années 80 et 90.', 'Un film de 1980 à 1999 : +1 case.', EffetFestival.caseEnPlus,
        (c) => (c.billet.annee ?? 0) >= 1980 && (c.billet.annee ?? 0) < 2000),
  ];

  /// Le lundi de la semaine.
  static DateTime lundi(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  /// Le festival de la semaine : le même pour tout le monde, et jamais deux
  /// semaines de suite le même.
  static Festival de(DateTime d) {
    final l = lundi(d);
    final semaines = DateTime.utc(l.year, l.month, l.day).difference(DateTime.utc(2026, 1, 5)).inDays ~/ 7;
    return tous[semaines % tous.length];
  }

  static Festival? parId(String id) => tous.where((f) => f.id == id).firstOrNull;
}
