import 'package:flutter/material.dart';

import '../theme/aura_theme.dart';

/// Ce que le joueur veut ressentir ce soir, et les genres qui y mènent
/// (noms de genres tels que Jellyfin et TMDB les rangent).
enum Emotion {
  frissonner('Frissonner', ['Thriller', 'Horror', 'Mystery', 'Crime', 'Horreur', 'Mystère', 'Policier']),
  rire('Rire', ['Comedy', 'Comédie']),
  bouleverse('Être bouleversé', ['Drama', 'Romance', 'Drame']),
  evader('S\'évader', ['Adventure', 'Fantasy', 'Science Fiction', 'Animation', 'Aventure', 'Fantastique']),
  reflechir('Réfléchir', ['Documentary', 'History', 'War', 'Documentaire', 'Histoire', 'Guerre']);

  const Emotion(this.libelle, this.genres);
  final String libelle;
  final List<String> genres;
}

enum Duree {
  courte('Moins d\'1 h 30', 90),
  moyenne('2 h', 125),
  soiree('Toute la soirée', 600);

  const Duree(this.libelle, this.minutesMax);
  final String libelle;
  final int minutesMax;
}

/// Les huit profils de spectateur. Chacun a sa figurine, son pouvoir et son
/// contrat de saison (voir la bible du jeu).
enum Profil {
  devoreur('Le Dévoreur', AuraCouleurs.rose, 'Tu enchaînes les épisodes et tu finis une saison en un week-end.',
      'Marathon', 'Une saison terminée vaut une campagne entière.', 'Finir 2 séries de genres différents', 2,
      'savourer une série, un épisode par soir'),
  degustateur('Le Dégustateur', AuraCouleurs.peche, 'Un épisode ou un film, puis tu laisses reposer.', 'Slow',
      'Chaque séance notée et commentée rapporte double.', '6 séances avec Verdict', 6, 'tenir un marathon d\'un soir'),
  explorateur('L\'Explorateur', AuraCouleurs.vert, 'Tu cherches les pays, les époques et les genres jamais vus.',
      'Boussole', 'Une carte de plus au tirage, bonus sur les régions vierges.', '4 pays ou décennies inédits', 4,
      'partager un film avec un ami'),
  critique('Le Critique', AuraCouleurs.jaune, 'Tu notes, tu décortiques, tu as toujours un avis.', 'Plume',
      'Tes Verdicts pèsent double dans le Flair.', '5 conseils qui plaisent', 5, 'regarder un film sans le noter'),
  fidele('Le Fidèle', AuraCouleurs.creme, 'Tu revois tes films doudous et tes séries refuges.', 'Madeleine',
      'Un revisionnage compte, si tu le fais découvrir à un ami.', 'Faire adopter 2 favoris', 2,
      'découvrir un film sorti cette année'),
  supporter('Le Supporter', AuraCouleurs.bleu, 'Tu regardes surtout du sport et du direct.', 'Tribune',
      'Tes pronostics de match font avancer ton pion.', '8 pronostics, dont 3 justes', 8,
      'voir un film de sport, pour une fois'),
  hote('L\'Hôte', AuraCouleurs.violet, 'Tu regardes pour partager, en couple, en famille ou entre amis.',
      'Projectionniste', 'Une séance à plusieurs fait avancer tout le monde.', '3 séances partagées', 3,
      'une séance seul, choisie pour toi'),
  presse('Le Pressé', AuraCouleurs.citron, 'Tu as peu de temps et tu aimes les formats courts.', 'Court-métrage',
      'Un format de moins d\'une heure compte plein.', '6 formats courts et 4 Plans du jour', 10,
      'un film de plus de deux heures');

  const Profil(this.nom, this.couleur, this.description, this.pouvoir, this.effet, this.contrat,
      this.objectif, this.piege);

  final String nom;
  final Color couleur;
  final String description;
  final String pouvoir;
  final String effet;
  final String contrat;
  final int objectif;
  final String piege;

  String get figurine => 'assets/figurines/$name.svg';

  static Profil depuisNom(String? n) =>
      Profil.values.firstWhere((p) => p.name == n, orElse: () => Profil.fidele);
}

/// Un film ou une série proposé par une source (Jellyfin, catalogue public…).
class Film {
  const Film({
    required this.id,
    required this.titre,
    this.annee,
    this.dureeMinutes,
    this.note,
    this.nombreVotes,
    this.genres = const [],
    this.pays = const [],
    this.realisateur,
    this.synopsis,
    this.dejaVu = false,
    this.serveurId,
    this.source = SourceFilm.demo,
  });

  final String id;
  final String titre;
  final int? annee;
  final int? dureeMinutes;

  /// Note sur 10 (TMDB / Jellyfin « CommunityRating »).
  final double? note;
  final int? nombreVotes;
  final List<String> genres;
  final List<String> pays;
  final String? realisateur;

  /// Le résumé du film (Jellyfin « Overview »), utile au Bluff.
  final String? synopsis;
  final bool dejaVu;

  /// Identifiant du serveur Jellyfin, utile au lien profond VJOD.
  final String? serveurId;
  final SourceFilm source;

  /// Note affichée sur 5 étoiles.
  double? get etoiles => note == null ? null : note! / 2;

  String get infos {
    final parts = <String>[
      if (annee != null) '$annee',
      if (realisateur != null) realisateur!,
      if (dureeMinutes != null) _duree(dureeMinutes!),
    ];
    return parts.join(', ');
  }

  static String _duree(int m) => m < 60 ? '$m min' : '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
}

enum SourceFilm { demo, jellyfin }

enum TypeCarte {
  retro('Rétro', AuraCouleurs.caseOrange, Color(0xFFFFC772)),
  voyage('Voyage', AuraCouleurs.caseVert, Color(0xFF62C472)),
  pepite('Pépite', AuraCouleurs.caseRose, Color(0xFFFFB3DC)),
  envie('Envie', AuraCouleurs.caseBleu, Color(0xFF8CC6F2)),
  affiche('Affiche', AuraCouleurs.caseRouge, Color(0xFFF57D6C));

  const TypeCarte(this.libelle, this.couleur, this.couleurClaire);
  final String libelle;
  final Color couleur;
  final Color couleurClaire;
}

/// Une carte défi tirée le soir : le défi est visible, le film reste caché
/// jusqu'à ce que la carte soit jouée.
class CarteDefi {
  const CarteDefi({
    required this.type,
    required this.defi,
    required this.indice,
    required this.cases,
    required this.joker,
    required this.film,
    required this.bulleDePop,
  });

  final TypeCarte type;
  final String defi;
  final String indice;
  final int cases;
  final String joker;
  final Film film;
  final String bulleDePop;
}
