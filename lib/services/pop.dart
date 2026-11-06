import 'carte_genres.dart';
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
    Pari('Je parie que tu n\'oseras pas jouer une carte Rétro cette semaine.', 'Jouer une carte Rétro', (s) => s.any((b) => b.type == 'Rétro')),
    Pari('Je parie que tu ne sortiras pas de tes frontières cette semaine.', 'Jouer une carte Voyage', (s) => s.any((b) => b.type == 'Voyage')),
    Pari('Je parie que tu ne tiendras pas trois séances cette semaine.', 'Valider 3 séances', (s) => s.length >= 3),
    Pari('Je parie que tu n\'écriras pas deux Verdicts cette semaine. Trop fatigant.', 'Écrire 2 Verdicts', (s) => s.where((b) => b.verdict.isNotEmpty).length >= 2),
    Pari('Je parie que tu ne tomberas pas pile sur ton pronostic cette semaine.', 'Réussir un pronostic exact', (s) => s.any((b) => b.note != null && b.note == b.pronostic)),
    Pari('Je parie que tu vas sécher l\'Affiche de la semaine.', 'Regarder l\'Affiche', (s) => s.any((b) => b.type == 'Affiche')),
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

  /// La case de Pop : un pas par jour, plus ses triches et ses régions de la
  /// carte des genres, moins ses paris perdus.
  static int position(DateTime maintenant, List<Billet> billets, {Set<int> boucliers = const {}}) {
    var p = maintenant.day;
    for (var j = 1; j <= maintenant.day; j++) {
      if (triche(DateTime(maintenant.year, maintenant.month, j))) p++;
    }
    p += CarteDesGenres.de(maintenant, billets, boucliers: boucliers).regionsDePop;
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
        'Pile-poil ! Tu as lu le scénario en cachette ?',
        'Exact. Je retire ce que j\'ai dit sur ton flair. Enfin, une partie.',
        'En plein dans le mille. Je vais devoir surveiller tes cartes.',
      ], graine);
    }
    if (ecart == 1) {
      return _une([
        'À une étoile près. Presque !',
        'Pas loin. Mais « pas loin », ça ne fait pas avancer les pions.',
        'Une étoile d\'écart. On dira que c\'était la faute du son.',
      ], graine);
    }
    if (note < pronostic) {
      return _une([
        'Tu lui donnais $pronostic étoiles, il n\'en mérite que $note. Il va falloir régler ton radar.',
        'Ha ! $pronostic étoiles prédites, $note au final. Je note ça dans mon carnet des grands ratés.',
        'Tu y croyais, hein ? Moi, j\'avais deviné le $note dès la bande-annonce.',
      ], graine);
    }
    return _une([
      'Tu ne lui donnais que $pronostic étoiles, et il en mérite $note ? Tu t\'es laissé surprendre.',
      'Sous-estimé à $pronostic, adoré à $note. Je te l\'avais dit. Enfin, je l\'ai pensé très fort.',
    ], graine);
  }

  /// Ce que Pop dit de la carte des genres.
  static String surLaCarte(CarteDesGenres carte, {bool bouclier = false}) {
    if (bouclier && carte.cible != null) {
      return 'Un Bouclier sur la région ${carte.cible!.libelle} ? Tricheur ! Bon, je la laisse… pour cette semaine.';
    }
    if (carte.prisesCetteSemaine.isNotEmpty) {
      final r = carte.prisesCetteSemaine.first.libelle;
      return 'Personne ne gardait la région $r : je l\'ai prise. Une case de plus pour moi. Viens la reprendre !';
    }
    final c = carte.cible;
    if (c == null) return 'Tu tiens toute la carte. Je boude.';
    return 'Cette semaine, je vise la région ${c.libelle}. Si tu n\'y regardes aucun film avant dimanche soir, elle est à moi.';
  }

  /// Ce que Pop dit en te voyant sur le plateau.
  static String surPlateau({required int joueur, required int pop, required DateTime jour}) {
    final g = graineDu(jour);
    if (triche(jour)) {
      return _une([
        'J\'ai glissé sur une flaque de beurre : une case de plus. Le règlement ne l\'interdit pas.',
        'Un coup de vent a poussé ma figurine d\'une case. Je n\'y suis pour rien… ou presque.',
        'J\'ai relu le règlement : il ne dit rien sur les pots de pop-corn. Une case de plus pour moi.',
      ], g);
    }
    if (pop > joueur) {
      return _une([
        'Je suis devant. Ne te décourage pas… enfin, un peu quand même.',
        'Tu vois ce pot de pop-corn qui s\'éloigne ? C\'est moi.',
        '${pop - joueur} case${pop - joueur > 1 ? 's' : ''} d\'avance. J\'ai le temps de faire une sieste.',
      ], g);
    }
    if (pop == joueur) {
      return _une(['Côte à côte. Ne me pousse pas.', 'Même case. Il n\'y a pas assez de place pour nous deux.'], g);
    }
    return _une([
      'Tu m\'as doublé ? J\'avais du sel dans les yeux.',
      'Profites-en. Je mijote quelque chose.',
      'Devant moi ? Le mois n\'est pas fini, champion.',
    ], g);
  }

  // Pop insolent (réglage par défaut) : un peu de mordant, jamais méchant.

  /// Ce que Pop te lance en ouvrant Ce soir.
  static String accueil({required int joueur, required int pop, required DateTime maintenant, bool insolent = true}) {
    final g = graineDu(maintenant);
    final h = maintenant.hour;
    if (!insolent) {
      return _une(['Bonsoir ! Envie de quoi ce soir ?', 'Content de te voir. On tire les cartes ?'], g);
    }
    if (h >= 23 || h < 5) {
      return _une([
        'Il est $h h. Tu cherches un film ou tu fuis ton lit ?',
        'À cette heure-ci ? Prends un film court, je ne veux pas te ramasser à la petite cuillère.',
      ], g);
    }
    if (pop > joueur) {
      final d = pop - joueur;
      return _une([
        'J\'ai $d case${d > 1 ? 's' : ''} d\'avance. Je t\'attendais. Pas trop, mais je t\'attendais.',
        'Encore derrière moi ? Je commence à me sentir seul, devant.',
        'Tu as regardé des séries sans moi, avoue.',
      ], g);
    }
    if (joueur > pop) {
      return _une([
        'Tu es devant moi. J\'ai prévenu mon avocat.',
        'Profite de la vue, devant. Ça ne va pas durer.',
        'Tu m\'as doublé. Je fais semblant que ça ne me touche pas.',
      ], g);
    }
    return _une([
      'Même case que moi. Pousse-toi un peu, je déborde.',
      'Ce soir, pas de film de trois heures : je te connais, tu t\'endors à la moitié.',
    ], g);
  }

  /// Le rappel du lendemain, « Alors, ce film ? ».
  static (String, String) rappel(String titre, {bool insolent = true}) => insolent
      ? ('Alors, $titre ?', 'Tu l\'as vu, ou tu t\'es endormi au générique ? Une note, et ton pion avance.')
      : ('Alors, $titre ?', 'Donne ta note en un geste, et ton pion avance.');
}
