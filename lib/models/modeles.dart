import 'package:flutter/material.dart';

import '../theme/aura_theme.dart';

/// Ce que le joueur veut ressentir ce soir, et les genres qui y mènent
/// (noms de genres tels que Jellyfin et TMDB les rangent).
enum Emotion {
  frissonner('Frissonner', 'Un film qui fait frissonner', ['Thriller', 'Horror', 'Mystery', 'Crime', 'Horreur', 'Mystère', 'Policier']),
  rire('Rire', 'Un film pour rire', ['Comedy', 'Comédie']),
  bouleverse('Être ému', 'Un film qui émeut', ['Drama', 'Romance', 'Drame']),
  evader('S\'évader', 'Un film pour s\'évader', ['Adventure', 'Fantasy', 'Science Fiction', 'Animation', 'Aventure', 'Fantastique']),
  reflechir('Réfléchir', 'Un film qui fait réfléchir', ['Documentary', 'History', 'War', 'Documentaire', 'Histoire', 'Guerre']);

  const Emotion(this.libelle, this.phrase, this.genres);
  final String libelle;

  /// La même envie, en toutes lettres (défi de la carte Envie).
  final String phrase;
  final List<String> genres;
}

enum Duree {
  courte('Moins d\'une heure et demie', 90),
  moyenne('Environ deux heures', 125),
  soiree('Toute la soirée', 600);

  const Duree(this.libelle, this.minutesMax);
  final String libelle;
  final int minutesMax;
}

/// Les huit profils de spectateur. Chacun a sa figurine, son pouvoir et son
/// contrat de saison (voir la bible du jeu).
enum Profil {
  devoreur('Le Dévoreur', AuraCouleurs.rose, 'Tu enchaînes les épisodes et tu termines une saison en un week-end.',
      'Marathon', 'Une saison terminée compte comme une campagne entière.', 'Terminer 2 séries de genres différents', 2,
      'savourer une série à raison d\'un épisode par soir'),
  degustateur('Le Dégustateur', AuraCouleurs.peche, 'Un film ou un épisode, puis tu prends le temps d\'y repenser.', 'Slow',
      'Chaque séance notée et commentée rapporte le double.', '6 séances avec un Verdict', 6, 'enchaîner tout un marathon en une soirée'),
  explorateur('L\'Explorateur', AuraCouleurs.vert, 'Tu cherches les pays, les époques et les genres que tu n\'as jamais vus.',
      'Boussole', 'Une carte de plus au tirage, et un bonus sur les régions encore libres.', '4 pays ou décennies jamais explorés', 4,
      'partager un film avec un ami'),
  critique('Le Critique', AuraCouleurs.jaune, 'Tu notes, tu analyses, tu as toujours un avis.', 'Plume',
      'Tes Verdicts comptent double dans le Flair.', '5 conseils qui plaisent', 5, 'regarder un film sans le noter'),
  fidele('Le Fidèle', AuraCouleurs.creme, 'Tu revois tes films fétiches et tes séries refuges.', 'Madeleine',
      'Revoir un film compte, à condition de le faire découvrir à un ami.', 'Faire aimer 2 de tes films préférés', 2,
      'découvrir un film sorti cette année'),
  supporter('Le Supporter', AuraCouleurs.bleu, 'Tu regardes surtout du sport et des directs.', 'Tribune',
      'Tes pronostics de match font avancer ton pion.', '8 pronostics, dont 3 justes', 8,
      'regarder un film de sport, pour changer'),
  hote('L\'Hôte', AuraCouleurs.violet, 'Tu regardes pour partager : en couple, en famille ou entre amis.',
      'Projectionniste', 'Une séance à plusieurs fait avancer tout le monde.', '3 séances partagées', 3,
      'une séance en solo, choisie pour toi'),
  presse('Le Pressé', AuraCouleurs.citron, 'Tu as peu de temps et tu aimes les formats courts.', 'Court-métrage',
      'Un film de moins d\'une heure compte comme un long.', '6 formats courts et 4 Plans du jour', 10,
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
    this.autresTitres = const [],
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

  /// Titre original et titres connus ailleurs (pour reconnaître le film dans
  /// un historique Letterboxd, souvent en anglais).
  final List<String> autresTitres;
  final bool dejaVu;

  /// Le même film, marqué comme déjà vu.
  Film vu() => Film(
        id: id,
        titre: titre,
        annee: annee,
        dureeMinutes: dureeMinutes,
        note: note,
        nombreVotes: nombreVotes,
        genres: genres,
        pays: pays,
        realisateur: realisateur,
        synopsis: synopsis,
        autresTitres: autresTitres,
        dejaVu: true,
        serveurId: serveurId,
        source: source,
      );

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
