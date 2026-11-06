import 'dart:math';

import 'apres_seance.dart' show Rarete;
import 'etat.dart' show Billet;

/// Le Deck d'atouts (R49) : des cartes à collectionner, comme dans Pokémon
/// TCG Pocket (un booster gratuit par jour, des séries à compléter) et
/// Balatro (chaque atout est simple, c'est leur combinaison qui fait le
/// jeu). On en pose 3 dans son deck (4 avec une grande collection) ; à
/// chaque billet, ceux dont la condition est remplie rapportent de l'audace,
/// et les plus rares une case. Le plafond de 3 cases par jour tient toujours,
/// et le deck ne donne jamais plus d'une case par billet.

/// Les trois séries à compléter.
enum Serie {
  plateau('Sur le plateau'),
  effets('Effets spéciaux'),
  ecran('Le grand écran');

  const Serie(this.nom);
  final String nom;

  /// L'exploit donné quand la série est complète.
  String get exploit => 'serie_$name';
}

/// Ce qu'un atout regarde pour se déclencher : le billet qui vient d'être
/// validé et ceux d'avant.
class ContexteAtout {
  const ContexteAtout({required this.billet, this.avant = const [], this.dureeMinutes});

  final Billet billet;

  /// Les billets d'avant, du plus récent au plus ancien.
  final List<Billet> avant;
  final int? dureeMinutes;

  Set<String> get genres => billet.genres.map((g) => g.toLowerCase()).toSet();
  bool genre(List<String> l) => l.any((g) => genres.contains(g.toLowerCase()));
  bool pays(String p) => billet.pays.contains(p);
}

class Atout {
  const Atout(this.id, this.nom, this.serie, this.rarete, this.texte, this.condition, {this.audace = 0, this.cases = 0});

  final String id;
  final String nom;
  final Serie serie;
  final Rarete rarete;

  /// Ce qu'il faut faire, en une phrase.
  final String texte;
  final bool Function(ContexteAtout c) condition;

  /// Ce qu'il rapporte au premier niveau (le niveau ajoute de l'audace).
  final int audace;
  final int cases;

  String get gain => [
        if (cases > 0) '+$cases case',
        if (audace > 0) '+$audace d\'audace',
      ].join(' et ');
}

bool _semaine(DateTime a, DateTime b) {
  DateTime lundi(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
  return lundi(a) == lundi(b);
}

bool _jour(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

abstract final class Deck {
  static const action = ['Action', 'Adventure', 'Aventure'];
  static const horreur = ['Horror', 'Horreur'];
  static const sf = ['Science Fiction', 'Fantasy', 'Fantastique', 'Science-Fiction'];

  static final atouts = <Atout>[
    // Sur le plateau : les métiers du cinéma.
    Atout('projectionniste', 'Le Projectionniste', Serie.plateau, Rarete.commune, 'Un film d\'avant 1980.', (c) => (c.billet.annee ?? 3000) < 1980, audace: 2),
    Atout('scripte', 'La Scripte', Serie.plateau, Rarete.commune, 'Noter le film.', (c) => c.billet.note != null, audace: 1),
    Atout('cascadeur', 'Le Cascadeur', Serie.plateau, Rarete.commune, 'Un film d\'action ou d\'aventure.', (c) => c.genre(action), audace: 2),
    Atout('maquilleuse', 'La Maquilleuse', Serie.plateau, Rarete.commune, 'Un film d\'horreur.', (c) => c.genre(horreur), audace: 2),
    Atout('doubleur', 'Le Doubleur', Serie.plateau, Rarete.rare, 'Un film ni français ni américain.',
        (c) => c.billet.pays.isNotEmpty && !c.billet.pays.any((p) => p == 'France' || p == 'États-Unis' || p == 'United States of America'), cases: 1),
    Atout('critique', 'La Critique', Serie.plateau, Rarete.rare, 'Ta note tombe pile sur ton pronostic.', (c) => c.billet.note == c.billet.pronostic, cases: 1),
    Atout('producteur', 'Le Producteur', Serie.plateau, Rarete.epique, 'Une carte de niveau 7 ou plus.', (c) => (c.billet.niveau ?? 0) >= 7, cases: 1, audace: 2),
    Atout('realisatrice', 'La Réalisatrice', Serie.plateau, Rarete.legendaire, 'Ton 3e film de la semaine.',
        (c) => c.avant.where((b) => _semaine(b.date, c.billet.date)).length == 2, cases: 1, audace: 3),
    // Effets spéciaux : la technique.
    Atout('ralenti', 'Le Ralenti', Serie.effets, Rarete.commune, 'Un film de 2 h 30 ou plus.', (c) => (c.dureeMinutes ?? 0) >= 150, audace: 2),
    Atout('fondu', 'Le Fondu', Serie.effets, Rarete.commune, 'Un film de moins d\'1 h 30.', (c) => c.dureeMinutes != null && c.dureeMinutes! < 90, audace: 2),
    Atout('cameo', 'Le Caméo', Serie.effets, Rarete.commune, 'Jouer la carte Envie.', (c) => c.billet.type == 'Envie', audace: 1),
    Atout('plan_sequence', 'Le Plan-séquence', Serie.effets, Rarete.rare, 'Un film hier soir aussi.',
        (c) => c.avant.any((b) => _jour(b.date, c.billet.date.subtract(const Duration(days: 1)))), cases: 1),
    Atout('twist', 'Le Twist', Serie.effets, Rarete.rare, 'Ta note s\'écarte de 2 ou plus de ton pronostic.',
        (c) => c.billet.note != null && (c.billet.note! - c.billet.pronostic).abs() >= 2, cases: 1),
    Atout('ecran_vert', 'L\'Écran vert', Serie.effets, Rarete.epique, 'Un film de science-fiction ou fantastique.', (c) => c.genre(sf), cases: 1),
    Atout('montage', 'Le Montage alterné', Serie.effets, Rarete.epique, 'Un genre absent de tes 3 derniers films.', (c) {
      final recents = c.avant.take(3).expand((b) => b.genres.map((g) => g.toLowerCase())).toSet();
      return c.genres.isNotEmpty && c.avant.length >= 3 && c.genres.every((g) => !recents.contains(g));
    }, cases: 1),
    Atout('generique', 'Le Générique de fin', Serie.effets, Rarete.legendaire, 'Un film le dimanche.', (c) => c.billet.date.weekday == DateTime.sunday, cases: 1, audace: 2),
    // Le grand écran : les époques et les genres.
    Atout('noir_blanc', 'Le Noir et blanc', Serie.ecran, Rarete.commune, 'Un film d\'avant 1960.', (c) => (c.billet.annee ?? 3000) < 1960, audace: 2),
    Atout('annees80', 'Les Années 80', Serie.ecran, Rarete.commune, 'Un film des années 1980.', (c) => (c.billet.annee ?? 0) >= 1980 && (c.billet.annee ?? 0) < 1990, audace: 2),
    Atout('blockbuster', 'Le Blockbuster', Serie.ecran, Rarete.commune, 'Un film américain depuis 2000.',
        (c) => (c.billet.annee ?? 0) >= 2000 && (c.pays('États-Unis') || c.pays('United States of America')), audace: 1),
    Atout('nouvelle_vague', 'La Nouvelle Vague', Serie.ecran, Rarete.rare, 'Un film français d\'avant 1975.', (c) => c.pays('France') && (c.billet.annee ?? 3000) < 1975, cases: 1),
    Atout('musical', 'La Comédie musicale', Serie.ecran, Rarete.rare, 'Un film musical.', (c) => c.genre(['Music', 'Musical', 'Musique']), cases: 1),
    Atout('documentaire', 'Le Documentaire', Serie.ecran, Rarete.rare, 'Un documentaire.', (c) => c.genre(['Documentary', 'Documentaire']), cases: 1),
    Atout('tour_du_monde', 'Le Tour du monde', Serie.ecran, Rarete.epique, 'Un pays pas encore vu ce mois-ci.', (c) {
      final vus = c.avant.where((b) => b.date.year == c.billet.date.year && b.date.month == c.billet.date.month).expand((b) => b.pays).toSet();
      return c.billet.pays.isNotEmpty && !c.billet.pays.any(vus.contains);
    }, cases: 1),
    Atout('chef_oeuvre', 'Le Chef-d\'œuvre', Serie.ecran, Rarete.legendaire, 'Mettre 5 à un film.', (c) => c.billet.note == 5, cases: 1, audace: 3),
  ];

  static Atout? de(String id) => atouts.where((a) => a.id == id).firstOrNull;

  static List<Atout> dela(Serie s) => atouts.where((a) => a.serie == s).toList();

  /// Le niveau d'un atout selon le nombre d'exemplaires : 1, puis 2 dès 3
  /// exemplaires, 3 (doré) dès 6. Chaque niveau au-dessus du premier ajoute
  /// une d'audace quand il se déclenche.
  static int niveau(int exemplaires) => exemplaires >= 6 ? 3 : exemplaires >= 3 ? 2 : 1;

  /// Les places du deck : 3, et une 4e quand on possède 15 atouts différents.
  static const grandeCollection = 15;
  static int emplacements(int differents) => differents >= grandeCollection ? 4 : 3;

  /// Ce que le deck rapporte pour ce billet : une case au plus, l'audace de
  /// tous les atouts déclenchés, et leurs noms pour le dire.
  static ({int cases, int audace, List<Atout> declenches}) effets(List<String> deck, Map<String, int> collection, ContexteAtout c) {
    final declenches = <Atout>[];
    var cases = 0;
    var audace = 0;
    for (final id in deck.toSet()) {
      final a = de(id);
      if (a == null || (collection[id] ?? 0) <= 0 || !a.condition(c)) continue;
      declenches.add(a);
      cases = max(cases, a.cases);
      audace += a.audace + niveau(collection[id]!) - 1;
    }
    return (cases: min(cases, 1), audace: audace, declenches: declenches);
  }

  // Les boosters.

  static const parBooster = 3;

  /// Au plus deux boosters en réserve : un jour manqué ne fait rien perdre,
  /// une semaine manquée ne fait pas tout gagner.
  static const reserveMax = 2;

  /// Une carte Épique ou mieux est garantie au plus tard au 10e booster.
  static const garantie = 10;

  static Rarete _rarete(Random r) {
    final x = r.nextInt(100);
    if (x < 2) return Rarete.legendaire;
    if (x < 10) return Rarete.epique;
    if (x < 34) return Rarete.rare;
    return Rarete.commune;
  }

  /// Trois atouts. [sansEpique] compte les boosters ouverts depuis la
  /// dernière carte Épique ou Légendaire.
  static List<Atout> booster(Random r, {int sansEpique = 0}) {
    final out = <Atout>[];
    for (var i = 0; i < parBooster; i++) {
      var rarete = _rarete(r);
      if (i == parBooster - 1 && sansEpique + 1 >= garantie && !out.any((a) => a.rarete.index >= Rarete.epique.index) && rarete.index < Rarete.epique.index) {
        rarete = Rarete.epique;
      }
      final lot = atouts.where((a) => a.rarete == rarete).toList();
      out.add(lot[r.nextInt(lot.length)]);
    }
    return out;
  }

  /// Les boosters disponibles aujourd'hui : un de plus par jour écoulé
  /// depuis le dernier don, sans dépasser la réserve. Le premier jour, un.
  static int disponibles({required int reserve, required DateTime? dernierDon, required DateTime aujourdhui}) {
    if (dernierDon == null) return max(reserve, 1).clamp(0, reserveMax);
    final jours = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day).difference(DateTime(dernierDon.year, dernierDon.month, dernierDon.day)).inDays;
    return (reserve + max(0, jours)).clamp(0, reserveMax);
  }

  /// Ce que Pop dit quand des atouts se déclenchent.
  static String phraseDePop(List<Atout> declenches, {int graine = 0}) {
    final a = declenches.first;
    final phrases = [
      '${a.nom} s\'est déclenché. Joli. Mais un atout, ce n\'est pas du talent.',
      'Tiens, ${a.nom} ! Tu as de la chance que je ne joue pas aux cartes.',
      '${a.nom}, et hop. Je note, je note.',
      if (declenches.length > 1) '${declenches.length} atouts d\'un coup ? Tu as triché, avoue.',
    ];
    return phrases[graine % phrases.length];
  }

  /// Les séries complètes.
  static List<Serie> seriesCompletes(Map<String, int> collection) =>
      [for (final s in Serie.values) if (dela(s).every((a) => (collection[a.id] ?? 0) > 0)) s];
}
