import 'tirage.dart';

/// Les coups du sort et les crasses (R40) : des retournements de situation,
/// drôles, jamais rageants, parce qu'il y a toujours une parade.

/// Ce qui peut arriver sur une case « Coup de théâtre » du plateau.
enum CoupDuSort {
  toboggan('Toboggan', 'Tu glisses de deux cases.', nuisible: true),
  echange('Échange', 'Pop et toi échangez vos places.', nuisible: false),
  vol('Pop te double', 'Pop avance de deux cases en sifflotant.', nuisible: true),
  public('Le public est avec toi', 'Une case de plus, offerte par la salle.', nuisible: false),
  entracte('Entracte', 'Pop mange ton pop-corn. C\'est tout. Il fallait bien une pause.', nuisible: false);

  const CoupDuSort(this.nom, this.effet, {required this.nuisible});

  final String nom;
  final String effet;
  final bool nuisible;
}

/// Ce qu'un coup fait bouger : le pion du joueur, et Pop.
typedef Deplacement = ({int joueur, int pop});

abstract final class CoupsDuSort {
  /// Les cases « Coup de théâtre » du plateau : 4, 14 et 24.
  static bool estCaseCoup(int n) => n % 10 == 4 && n < Regles.taillePlateau;

  /// Le coup qui attend sur cette case ce mois-ci : calculé depuis la date,
  /// le même pour tout le monde, comme les triches de Pop ; les trois cases
  /// d'un même mois ont toujours trois coups différents.
  static CoupDuSort pour(DateTime mois, int numero) =>
      CoupDuSort.values[(mois.year + mois.month * 2 + (numero ~/ 10) * 2) % CoupDuSort.values.length];

  /// Ce que le coup déplace. L'échange n'est nuisible que si on était devant.
  static Deplacement deplacement(CoupDuSort c, {required int joueur, required int pop}) {
    int borne(int n) => n.clamp(1, Regles.taillePlateau);
    return switch (c) {
      CoupDuSort.toboggan => (joueur: borne(joueur - 2) - joueur, pop: 0),
      CoupDuSort.echange => (joueur: pop - joueur, pop: joueur - pop),
      CoupDuSort.vol => (joueur: 0, pop: borne(pop + 2) - pop),
      CoupDuSort.public => (joueur: borne(joueur + 1) - joueur, pop: 0),
      CoupDuSort.entracte => (joueur: 0, pop: 0),
    };
  }

  /// Vrai si le coup fait du tort au joueur à cet instant : il peut alors le parer.
  static bool faitDuTort(CoupDuSort c, {required int joueur, required int pop}) =>
      c.nuisible || (c == CoupDuSort.echange && joueur > pop);
}

/// Les crasses à faire à un ami de sa ligue. Une par semaine ; celui qui la
/// reçoit choisit : l'encaisser, la parer (une charge de pouvoir) ou la
/// renvoyer à l'expéditeur (une fois par mois).
enum Crasse {
  niveauImpose('Niveau imposé', 'Ton prochain tirage se fera au niveau 8. Bon courage.', 'Je lui impose le niveau 8 au prochain tirage'),
  popcorn('Pop-corn renversé', 'Ta prochaine séance rapporte une case de moins.', 'Sa prochaine séance rapporte une case de moins'),
  volDAudace('Vol d\'audace', 'On te pique 5 points d\'audace ce mois-ci.', 'Je lui pique 5 points d\'audace'),
  fauxSpoiler('Faux spoiler', 'Pop jure qu\'à la fin, c\'était le chien depuis le début. (C\'est faux. Probablement.)', 'Pop lui envoie un faux spoiler, sans conséquence');

  const Crasse(this.nom, this.effet, this.promesse);

  final String nom;

  /// Ce que lit celui qui la reçoit.
  final String effet;

  /// Ce que lit celui qui l'envoie.
  final String promesse;

  static Crasse? depuisNom(String? n) {
    for (final c in values) {
      if (c.name == n) return c;
    }
    return null;
  }
}

/// Comment une crasse reçue a été réglée.
enum Reponse { encaissee, paree, renvoyee }

abstract final class Crasses {
  static const niveauImpose = 8;
  static const audaceVolee = 5;

  static DateTime lundiDe(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  /// Une crasse par semaine (les renvois ne comptent pas).
  static bool peutEnvoyer(DateTime maintenant, List<DateTime> envoyees) =>
      !envoyees.any((d) => !lundiDe(d).isBefore(lundiDe(maintenant)));

  /// Un renvoi par mois.
  static bool peutRenvoyer(DateTime maintenant, List<DateTime> renvois) =>
      !renvois.any((d) => d.year == maintenant.year && d.month == maintenant.month);
}

/// Une crasse telle que le serveur la garde.
class CrasseRecue {
  const CrasseRecue({required this.id, required this.ligueId, required this.de, required this.pour, required this.crasse, required this.date, this.reponse, this.renvoi = false});

  final String id;
  final String ligueId;
  final String de;
  final String pour;
  final Crasse crasse;
  final DateTime date;
  final Reponse? reponse;
  final bool renvoi;

  static CrasseRecue? depuisJson(Map<String, dynamic> j) {
    final c = Crasse.depuisNom(j['type'] as String?);
    if (c == null) return null;
    final r = j['reponse'] as String?;
    return CrasseRecue(
      id: j['id'] as String,
      ligueId: j['ligue_id'] as String,
      de: j['de'] as String,
      pour: j['pour'] as String,
      crasse: c,
      date: DateTime.parse(j['cree_le'] as String).toLocal(),
      reponse: Reponse.values.where((x) => x.name == r).firstOrNull,
      renvoi: (j['renvoi'] as bool?) ?? false,
    );
  }
}
