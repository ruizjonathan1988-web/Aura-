import 'deck.dart' show ContexteAtout;

/// Le Casse de la Cinémathèque (R56) : la dernière semaine du mois (à la
/// place du Défi de la semaine), l'équipe braque le coffre de Pop. Quatre
/// serrures, chacune un défi ; chacun a les siennes. Le Perceur a la plus
/// dure. Dès trois dans l'équipe, l'un d'eux est la Taupe : sa serrure
/// s'affiche ouverte, mais il peut faire semblant. Avant la révélation,
/// l'équipe vote : si la majorité désigne la Taupe, ses fausses ouvertures
/// sont démasquées et comptent. En solo, l'équipe, ce sont les rivaux
/// robots Bobine et Pellicule… et l'un des deux est la Taupe.
class Serrure {
  const Serrure(this.id, this.texte, this.condition, {this.dure = false});
  final String id;
  final String texte;
  final bool Function(ContexteAtout c) condition;
  final bool dure;
}

class Role {
  const Role({required this.serrures, this.perceur = false, this.taupe = false});
  final List<int> serrures;
  final bool perceur;
  final bool taupe;
}

abstract final class Casse {
  static const nbSerrures = 4;
  static const jours = 7;
  static const audaceReussite = 5;
  static const audaceTaupe = 5;
  static const recul = 2;
  static const robots = ['bobine', 'pellicule'];
  static const nomsRobots = {'bobine': 'Bobine', 'pellicule': 'Pellicule'};

  static const _asie = {'Japon', 'Corée du Sud', 'Chine', 'Hong Kong', 'Inde', 'Iran', 'Taïwan', 'Thaïlande', 'Japan', 'South Korea', 'China', 'India'};

  static final pool = <Serrure>[
    Serrure('long', 'Un film de 2 h 30 ou plus.', (c) => (c.dureeMinutes ?? 0) >= 150, dure: true),
    Serrure('noir_blanc', 'Un film d\'avant 1960.', (c) => (c.billet.annee ?? 3000) < 1960, dure: true),
    Serrure('niveau7', 'Une carte de niveau 7 ou plus.', (c) => (c.billet.niveau ?? 0) >= 7, dure: true),
    Serrure('asie', 'Un film d\'Asie.', (c) => c.billet.pays.any(_asie.contains)),
    Serrure('coup_de_coeur', 'Mettre 5 à un film.', (c) => c.billet.note == 5),
    Serrure('docu_anim', 'Un documentaire ou un film d\'animation.', (c) => c.genre(const ['Documentary', 'Documentaire', 'Animation'])),
    Serrure('frousse', 'Un film d\'horreur ou un thriller.', (c) => c.genre(const ['Horror', 'Horreur', 'Thriller'])),
    Serrure('vhs', 'Un film de 1980 à 1999.', (c) => (c.billet.annee ?? 0) >= 1980 && (c.billet.annee ?? 0) < 2000),
    Serrure('comedie', 'Une comédie.', (c) => c.genre(const ['Comedy', 'Comédie'])),
    Serrure('devin', 'Ta note tombe pile sur ton pronostic.', (c) => c.billet.note != null && c.billet.note == c.billet.pronostic),
  ];

  static String mois(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static int dernierJour(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

  /// La semaine du Casse : les 7 derniers jours du mois.
  static bool enCours(DateTime d) => d.day > dernierJour(d) - jours;

  /// Le jour du Casse (1 à 7), ou 0 hors de la semaine.
  static int jourDuCasse(DateTime d) => enCours(d) ? d.day - (dernierJour(d) - jours) : 0;

  /// La révélation : le dernier jour du mois, à partir de 18 h.
  static bool revelation(DateTime d) => enCours(d) && d.day == dernierJour(d) && d.hour >= 18;

  static int graine(DateTime d) => d.year * 100 + d.month;

  /// Les quatre serrures du mois : la première, celle du Perceur, est dure.
  static List<Serrure> serrures(DateTime d) {
    final g = graine(d);
    final dures = pool.where((s) => s.dure).toList();
    final autres = pool.where((s) => !s.dure).toList();
    final premiere = dures[g % dures.length];
    final reste = <Serrure>[];
    for (var i = 0; reste.length < nbSerrures - 1; i++) {
      final s = autres[(g * 7 + i * 3) % autres.length];
      if (!reste.contains(s)) reste.add(s);
    }
    return [premiere, ...reste];
  }

  /// Les rôles de l'équipe (identifiants triés pour que chacun calcule les
  /// mêmes) : le Perceur prend la serrure 0, les autres serrures tournent ;
  /// dès trois, une Taupe parmi les autres que le Perceur. [graineEquipe]
  /// change d'un mois et d'une équipe à l'autre.
  static Map<String, Role> roles(List<String> equipe, int graineEquipe, {String? forcePerceur}) {
    final ids = [...equipe]..sort();
    if (ids.isEmpty) return const {};
    final n = ids.length;
    final perceur = forcePerceur ?? ids[graineEquipe % n];
    final autres = ids.where((x) => x != perceur).toList();
    final taupe = n >= 3 ? autres[(graineEquipe ~/ n) % autres.length] : null;
    final serrures = <String, List<int>>{for (final id in ids) id: []};
    serrures[perceur]!.add(0);
    final tour = [...autres, perceur];
    for (var s = 1; s < nbSerrures; s++) {
      serrures[tour[(s - 1) % tour.length]]!.add(s);
    }
    return {for (final id in ids) id: Role(serrures: serrures[id]!, perceur: id == perceur, taupe: id == taupe)};
  }

  /// Le jour (1 à 6) où un robot ouvre sa serrure.
  static int jourDuRobot(String robot, DateTime d) => 1 + (graine(d) * (robot == 'bobine' ? 3 : 5)) % 6;

  /// L'issue : chaque serrure est vraiment ouverte, ou ouverte « pour de
  /// faux » par la Taupe ; si la majorité a désigné la Taupe, ses fausses
  /// ouvertures comptent. Le Casse réussit si les quatre serrures tiennent.
  static ({bool reussi, bool taupeDemasquee}) issue({
    required Map<int, bool> ouvertures,
    required String? taupe,
    required Map<String, String> votes,
    required int equipe,
  }) {
    final contre = taupe == null ? 0 : votes.values.where((v) => v == taupe).length;
    final demasquee = taupe != null && contre * 2 > equipe;
    final reussi = List.generate(nbSerrures, (s) => s).every((s) => ouvertures.containsKey(s) && (ouvertures[s]! || demasquee));
    return (reussi: reussi, taupeDemasquee: demasquee);
  }
}
