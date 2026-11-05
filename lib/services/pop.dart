import 'etat.dart';
import 'tirage.dart';

/// Un pari de Pop pour la semaine. S'il le perd, il recule de 2 cases.
class Pari {
  const Pari(this.texte, this.defi, this._tenu);

  /// Ce que Pop affirme, pour te provoquer.
  final String texte;

  /// Ce qu'il faut faire pour lui donner tort.
  final String defi;

  final bool Function(List<Billet> semaine) _tenu;

  bool releve(List<Billet> semaine) => _tenu(semaine);
}

/// Pop, le Programmateur : la mascotte VJOD et l'adversaire du solo.
/// Il avance d'une case par jour, triche un peu (et l'avoue), lance un pari
/// chaque semaine et chambre les pronostics ratés. Tout est calculé à partir
/// de la date et des billets : pas de hasard caché, même résultat partout.
abstract final class Pop {
  static const recul = 2;

  static final paris = <Pari>[
    Pari('Je parie que tu n\'oses pas une carte Rétro cette semaine.', 'Jouer une carte Rétro', (s) => s.any((b) => b.type == 'Rétro')),
    Pari('Je parie que tu ne quittes pas ton canapé… enfin, ton pays, cette semaine.', 'Jouer une carte Voyage', (s) => s.any((b) => b.type == 'Voyage')),
    Pari('Je parie que tu ne tiens pas 3 séances cette semaine.', 'Valider 3 séances', (s) => s.length >= 3),
    Pari('Je parie que tu n\'écris pas 2 Verdicts cette semaine. Trop de travail.', 'Écrire 2 Verdicts', (s) => s.where((b) => b.verdict.isNotEmpty).length >= 2),
    Pari('Je parie que tu ne tombes pas pile sur ton pronostic cette semaine.', 'Un pronostic exact', (s) => s.any((b) => b.note != null && b.note == b.pronostic)),
    Pari('Je parie que tu sèches l\'Affiche de la semaine.', 'Voir l\'Affiche', (s) => s.any((b) => b.type == 'Affiche')),
  ];

  static DateTime lundiDe(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  static int _numeroDeSemaine(DateTime lundi) => DateTime.utc(lundi.year, lundi.month, lundi.day).millisecondsSinceEpoch ~/ 86400000 ~/ 7;

  static Pari pariDe(DateTime jour) => paris[_numeroDeSemaine(lundiDe(jour)) % paris.length];

  /// Les billets d'une semaine qui comptent pour le plateau du mois de [jour].
  static List<Billet> semaine(DateTime lundi, DateTime jour, List<Billet> billets) {
    final fin = lundi.add(const Duration(days: 7));
    return billets
        .where((b) => !b.date.isBefore(lundi) && b.date.isBefore(fin) && b.date.month == jour.month && b.date.year == jour.year)
        .toList();
  }

  /// Les jours où Pop triche : un peu moins d'un jour sur huit.
  static bool triche(DateTime d) => (d.day * 7 + d.month * 3 + d.year) % 8 == 0;

  /// La case de Pop : un pas par jour, plus ses triches, moins ses paris perdus.
  static int position(DateTime maintenant, List<Billet> billets) {
    var p = maintenant.day;
    for (var j = 1; j <= maintenant.day; j++) {
      if (triche(DateTime(maintenant.year, maintenant.month, j))) p++;
    }
    p -= recul * parisPerdus(maintenant, billets);
    return p.clamp(1, Regles.taillePlateau);
  }

  static int parisPerdus(DateTime maintenant, List<Billet> billets) {
    var perdus = 0;
    var lundi = lundiDe(DateTime(maintenant.year, maintenant.month, 1));
    while (!lundi.isAfter(maintenant)) {
      if (pariDe(lundi).releve(semaine(lundi, maintenant, billets))) perdus++;
      lundi = DateTime(lundi.year, lundi.month, lundi.day + 7);
    }
    return perdus;
  }

  static String _une(List<String> l, int graine) => l[graine.abs() % l.length];

  static int graineDu(DateTime d) => d.day * 31 + d.month * 7 + d.hour;

  /// Pop commente ton pronostic une fois la vraie note connue.
  static String surPronostic({required int pronostic, required int note, required int graine}) {
    final ecart = (note - pronostic).abs();
    if (ecart == 0) {
      return _une([
        'Pile-poil. Tu as lu le scénario en cachette ?',
        'Exact. Je retire ce que j\'ai dit sur ton flair. Enfin, une partie.',
        'Dans le mille ! Je vais devoir surveiller tes cartes.',
      ], graine);
    }
    if (ecart == 1) {
      return _une([
        'À une étoile près. Comme moi au bowling.',
        'Presque. On dira que c\'est la faute du son.',
        'Pas loin ! Mais pas loin, ça ne fait pas avancer les pions.',
      ], graine);
    }
    if (note < pronostic) {
      return _une([
        'Tu lui donnais $pronostic, il finit à $note. Il va falloir régler ton radar.',
        'Ha ! $pronostic étoiles prédites, $note réelles. Je note ça dans mon carnet des grands ratés.',
        'Tu y croyais, hein ? Moi, j\'avais vu venir le $note dès la bande-annonce.',
      ], graine);
    }
    return _une([
      'Tu ne le voyais qu\'à $pronostic, et il te met $note ? Ouvre ton cœur, voyons.',
      'Sous-estimé à $pronostic, adoré à $note. Je te l\'avais dit. Enfin, j\'y pensais très fort.',
    ], graine);
  }

  /// Ce que Pop dit en te voyant sur le plateau.
  static String surPlateau({required int joueur, required int pop, required DateTime jour}) {
    final g = graineDu(jour);
    if (triche(jour)) {
      return _une([
        'J\'ai glissé sur une flaque de beurre : une case de plus. Ça compte, c\'est le règlement.',
        'Le vent a poussé ma figurine d\'une case. Je n\'y suis pour rien. Presque rien.',
        'J\'ai relu le règlement : il ne dit rien sur les pots de pop-corn. Une case de plus pour moi.',
      ], g);
    }
    if (pop > joueur) {
      return _une([
        'Je suis devant. Ne te décourage pas. Enfin, si, un peu.',
        'Tu vois ce pop-corn qui s\'éloigne ? C\'est moi.',
        '${pop - joueur} case${pop - joueur > 1 ? 's' : ''} d\'avance. J\'ai le temps de faire une sieste.',
      ], g);
    }
    if (pop == joueur) {
      return _une(['Côte à côte. Ne me pousse pas.', 'Même case. Il n\'y a pas assez de place pour nous deux.'], g);
    }
    return _une([
      'Tu m\'as doublé ? J\'avais du sel dans les yeux.',
      'Profite, profite. Je mijote quelque chose.',
      'Devant moi ? Le mois n\'est pas fini, champion.',
    ], g);
  }
}
