import 'dart:math';

import '../models/modeles.dart';
import 'traduction.dart';

/// Le tirage des trois cartes du soir.
///
/// Règle « zéro navet » : le jeu ne propose de lui-même que des titres notés
/// au moins 6/10 (3 étoiles), avec assez d'avis pour que la note veuille
/// dire quelque chose. Le seuil d'avis est plus bas pour les films anciens,
/// pour que les pépites restent possibles.
class Tirage {
  Tirage({Random? hasard}) : _hasard = hasard ?? Random();

  final Random _hasard;

  static const noteMinimale = 6.0;

  static bool assezBon(Film f) {
    final note = f.note;
    if (note == null || note < noteMinimale) return false;
    final votes = f.nombreVotes;
    if (votes == null) return true; // la source ne donne pas le nombre d'avis
    final seuil = (f.annee ?? 2000) < 1990 ? 30 : 150;
    return votes >= seuil;
  }

  /// Le haut du panier : les 40 % les mieux notés (au moins [minimum]
  /// films), rangés par identifiant pour que le choix du jour soit stable.
  static List<Film> hautDuPanier(List<Film> films, {int minimum = 9}) {
    final parNote = [...films]..sort((a, b) => (b.note ?? 0).compareTo(a.note ?? 0));
    return parNote.take(max(minimum, (films.length * .4).ceil())).toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  static bool correspond(Film f, Emotion e, Duree d) {
    if (f.dureeMinutes != null && f.dureeMinutes! > d.minutesMax) return false;
    if (f.genres.isEmpty) return true;
    final g = f.genres.map((x) => x.toLowerCase()).toSet();
    return e.genres.any((x) => g.contains(x.toLowerCase()));
  }

  /// Tire jusqu'à trois cartes de types différents. [paysVus] sert au défi
  /// Voyage (un pays jamais vu par le joueur).
  List<CarteDefi> tirer({
    required List<Film> catalogue,
    required Emotion emotion,
    required Duree duree,
    required Profil profil,
    Set<String> paysVus = const {},
  }) {
    final tous = catalogue.where((f) => !f.dejaVu && assezBon(f) && correspond(f, emotion, duree)).toList()
      ..shuffle(_hasard);
    // Le haut du panier d'abord : on garde les mieux notés (40 % du lot, au
    // moins 9 films), puis on mélange. Les autres ne servent qu'en secours.
    final parNote = [...tous]..sort((a, b) => (b.note ?? 0).compareTo(a.note ?? 0));
    final garde = max(9, (tous.length * .4).ceil());
    final candidats = [...parNote.take(garde).toList()..shuffle(_hasard), ...parNote.skip(garde)];
    final pris = <String>{};
    final cartes = <CarteDefi>[];

    Film? prendre(bool Function(Film) filtre) {
      for (final f in candidats) {
        if (!pris.contains(f.id) && filtre(f)) {
          pris.add(f.id);
          return f;
        }
      }
      return null;
    }

    final retro = prendre((f) => (f.annee ?? 3000) < 1980);
    if (retro != null) {
      cartes.add(CarteDefi(
        type: TypeCarte.retro,
        defi: 'Un classique ${_suite(emotion)}, avant 1980',
        indice: _indice(retro),
        cases: 3,
        joker: 'Un classique : 3 cases, la plus belle récompense.',
        film: retro,
        bulleDePop: 'Un film d\'avant 1980 ? Ne fais pas cette tête : le noir et blanc ne mord pas.',
      ));
    }

    final voyage = prendre((f) => f.pays.isNotEmpty && !f.pays.any(paysVus.contains));
    if (voyage != null) {
      cartes.add(CarteDefi(
        type: TypeCarte.voyage,
        defi: 'Un film ${_suite(emotion)}, d\'un pays jamais vu',
        indice: _indice(voyage),
        cases: 2,
        joker: 'Un voyage : 2 cases.',
        film: voyage,
        bulleDePop: 'Cap sur un pays que tu ne connais pas encore. Prépare ton passeport et les sous-titres !',
      ));
    }

    final pepite = prendre((f) => (f.note ?? 0) >= 7.5);
    if (pepite != null) {
      cartes.add(CarteDefi(
        type: TypeCarte.pepite,
        defi: 'Une pépite ${_suite(emotion)}, très bien notée',
        indice: _indice(pepite),
        cases: 2,
        joker: 'Une pépite : 2 cases.',
        film: pepite,
        bulleDePop: 'Celle-là, je la gardais pour toi. Ne me déçois pas.',
      ));
    }

    while (cartes.length < 3) {
      final f = prendre((_) => true);
      if (f == null) break;
      cartes.add(CarteDefi(
        type: TypeCarte.envie,
        defi: emotion.phrase,
        indice: _indice(f),
        cases: 1,
        joker: 'Une valeur sûre : 1 case.',
        film: f,
        bulleDePop: 'Pas de défi ce soir ? Je ne juge pas. Enfin, si, un peu.',
      ));
    }
    return cartes.take(3).toList();
  }

  /// L'envie dans le défi, pour que chaque envie donne d'autres cartes.
  static String _suite(Emotion e) => switch (e) {
        Emotion.frissonner => 'qui fait frissonner',
        Emotion.rire => 'pour rire',
        Emotion.bouleverse => 'qui émeut',
        Emotion.evader => 'pour s\'évader',
        Emotion.reflechir => 'qui fait réfléchir',
      };

  /// Un indice qui ne donne ni le titre ni l'année exacte.
  String _indice(Film f) {
    final parts = <String>[];
    if (f.annee != null) parts.add('Années ${(f.annee! ~/ 10) * 10}');
    if (f.pays.isNotEmpty) parts.add(Traduction.pays(f.pays.first));
    if (f.genres.isNotEmpty) parts.add(Traduction.genre(f.genres.first));
    if (f.dureeMinutes != null) parts.add(Traduction.duree(f.dureeMinutes!));
    return parts.join(' · ');
  }
}

/// Le plafond d'équité : jamais plus de 3 cases par jour, quoi qu'on regarde.
abstract final class Regles {
  static const casesParJourMax = 3;
  static const taillePlateau = 30;

  static int casesAccordees({required int demandees, required int dejaGagneesAujourdhui}) {
    final reste = casesParJourMax - dejaGagneesAujourdhui;
    if (reste <= 0) return 0;
    return demandees.clamp(0, reste);
  }
}
