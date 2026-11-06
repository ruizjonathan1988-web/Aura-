import 'dart:math';

/// Le Bingo du film (R55) : on joue PENDANT le film. Quand la Soirée jeu
/// lance le film, chaque téléphone reçoit une grille secrète de 16 cases
/// tirées selon le genre (« quelqu'un dit je t'aime », « une voiture
/// explose »…), plus une case absurde glissée par Pop. On coche en silence.
/// Au générique, la télé montre ce que chacun a coché ; le salon peut
/// contester. Case acceptée : +1. Case contestée par la majorité des autres :
/// −1 (on a vu ton bluff). Ligne ou colonne entière acceptée : +3, BINGO.
abstract final class Bingo {
  static const cote = 4;
  static const cases = cote * cote;
  static const pointsLigne = 3;

  static const communs = [
    'Quelqu\'un dit « je t\'aime »',
    'Un téléphone sonne au mauvais moment',
    'Quelqu\'un claque une porte',
    'Une scène sous la pluie',
    'Un personnage boit un café',
    'Quelqu\'un court',
    'Un baiser',
    'Une scène de repas',
    'Quelqu\'un pleure',
    'Un flash-back',
    'Une voiture démarre en trombe',
    'Quelqu\'un ment, et on le sait',
    'Un chien ou un chat à l\'écran',
    'Quelqu\'un regarde par une fenêtre',
    'Un personnage dit le titre du film',
    'Une musique qui fait monter la tension',
    'Une gifle',
    'Quelqu\'un se réveille en sursaut',
    'Un plan sur une ville la nuit',
    'Une lettre ou un message lu à voix haute',
  ];

  static const parGenre = <String, List<String>>{
    'action': ['Une explosion', 'Une course-poursuite', 'Quelqu\'un saute d\'un toit', 'Une bagarre à mains nues', 'Le héros est blessé mais continue', 'Une réplique avant de frapper'],
    'horreur': ['Une lumière qui grésille', 'Quelqu\'un dit « il y a quelqu\'un ? »', 'Un miroir fait peur', 'Une porte grince', 'Un faux sursaut (ce n\'était qu\'un chat)', 'On se sépare, mauvaise idée'],
    'comedie': ['Quelqu\'un tombe', 'Un quiproquo', 'Une réplique culte (tout le monde rit)', 'Un déguisement', 'Un fou rire à l\'écran', 'Une situation très gênante'],
    'romance': ['Un regard qui dure trop longtemps', 'Une dispute d\'amoureux', 'Une course pour rattraper quelqu\'un', 'Un premier rendez-vous', 'Des fleurs', 'Une danse'],
    'sf': ['Un écran plein de chiffres', 'Un vaisseau ou un robot', 'Quelqu\'un dit « c\'est impossible »', 'Un compte à rebours', 'Une lumière bleue mystérieuse', 'Un saut dans le temps ou l\'espace'],
    'drame': ['Un silence très long', 'Une famille à table qui se dispute', 'Un enterrement', 'Une lettre qui change tout', 'Quelqu\'un fait ses valises', 'Un regard vers la mer'],
    'policier': ['Un interrogatoire', 'Un indice qu\'on remarque à peine', 'Une arme sur la table', 'Un tableau de photos reliées par des fils', 'Quelqu\'un est suivi', 'Un « tu n\'aurais pas dû venir »'],
  };

  /// Les cases absurdes de Pop : si le salon vous croit, tant mieux…
  static const pieges = [
    'Un lama traverse l\'écran',
    'Quelqu\'un mange du pop-corn géant',
    'Un personnage parle à une plante',
    'Une perruque tombe',
    'Un pingouin, n\'importe où',
  ];

  static String familleDe(List<String> genres) {
    final g = genres.map((x) => x.toLowerCase()).toSet();
    bool a(List<String> l) => l.any(g.contains);
    if (a(['horror', 'horreur'])) return 'horreur';
    if (a(['science fiction', 'fantasy', 'fantastique', 'science-fiction'])) return 'sf';
    if (a(['action', 'adventure', 'aventure'])) return 'action';
    if (a(['comedy', 'comédie'])) return 'comedie';
    if (a(['romance'])) return 'romance';
    if (a(['crime', 'thriller', 'mystery', 'policier', 'mystère'])) return 'policier';
    return 'drame';
  }

  /// Une grille de 16 cases : 6 du genre, 9 communes, 1 piège de Pop.
  static List<String> grille(List<String> genres, Random r) {
    final genre = [...parGenre[familleDe(genres)]!]..shuffle(r);
    final commun = [...communs]..shuffle(r);
    final piege = pieges[r.nextInt(pieges.length)];
    return [...genre.take(6), ...commun.take(9), piege]..shuffle(r);
  }

  /// Les lignes et colonnes entièrement acceptées.
  static int lignes(Set<int> acceptees) {
    var n = 0;
    for (var i = 0; i < cote; i++) {
      if (List.generate(cote, (k) => i * cote + k).every(acceptees.contains)) n++;
      if (List.generate(cote, (k) => k * cote + i).every(acceptees.contains)) n++;
    }
    return n;
  }

  /// Une case est rejetée si la majorité stricte des autres la conteste.
  static bool rejetee(int contestations, int autres) => autres > 0 && contestations * 2 > autres;

  /// Les points d'un joueur : +1 par case acceptée, −1 par case rejetée,
  /// +3 par ligne complète acceptée.
  static int points({required Set<int> cochees, required Set<int> rejetees}) {
    final acceptees = cochees.difference(rejetees);
    return acceptees.length - cochees.intersection(rejetees).length + pointsLigne * lignes(acceptees);
  }
}
