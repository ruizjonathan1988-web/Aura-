import 'dart:math';

import '../models/modeles.dart';
import 'niveau.dart';
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
    if (e.exclus.any((x) => g.contains(x.toLowerCase()))) return false;
    return e.genres.any((x) => g.contains(x.toLowerCase()));
  }

  /// Tire jusqu'à trois cartes de types différents. [paysVus] sert au défi
  /// Voyage (un pays jamais vu par le joueur). Avec un [niveau] (« Tu te
  /// mets combien ? »), seuls les films proches de ce niveau sont tirés, et
  /// chaque carte rapporte les cases du niveau, quel que soit son type.
  List<CarteDefi> tirer({
    required List<Film> catalogue,
    required Emotion emotion,
    required Duree duree,
    required Profil profil,
    Set<String> paysVus = const {},
    int? niveau,
  }) {
    final possibles = catalogue.where((f) => !f.dejaVu && assezBon(f) && correspond(f, emotion, duree)).toList();
    final tous = (niveau == null ? possibles : Niveau.proches(possibles, niveau))..shuffle(_hasard);
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
    final main = cartes.take(3).toList();
    if (niveau == null) return main;
    final gain = Niveau.cases(niveau);
    return [
      for (final c in main)
        CarteDefi(
          type: c.type,
          defi: c.defi,
          indice: c.indice,
          cases: gain,
          joker: 'Tu t\'es mis $niveau : ${gain == 1 ? '1 case' : '$gain cases'} si tu vas au bout.',
          film: c.film,
          bulleDePop: c.bulleDePop,
          niveau: niveau,
        ),
    ];
  }

  /// Jamais d'impasse : si l'envie et la durée ne donnent pas trois cartes,
  /// Pop allonge la durée d'un cran, puis va jusqu'à « toute la soirée ».
  /// S'il n'y a vraiment rien pour cette envie, il garde la durée et prend
  /// les meilleurs films de la sélection. Le message dit ce qu'il a changé
  /// (null si rien).
  ({List<CarteDefi> cartes, String? message}) tirerSansImpasse({
    required List<Film> catalogue,
    required Emotion emotion,
    required Duree duree,
    required Profil profil,
    Set<String> paysVus = const {},
    int? niveau,
  }) {
    final cartes = tirer(catalogue: catalogue, emotion: emotion, duree: duree, profil: profil, paysVus: paysVus, niveau: niveau);
    if (cartes.length >= 3) return (cartes: cartes, message: null);
    for (final plusLong in Duree.values.where((d) => d.minutesMax > duree.minutesMax)) {
      final autres = tirer(catalogue: catalogue, emotion: emotion, duree: plusLong, profil: profil, paysVus: paysVus, niveau: niveau);
      if (autres.length > cartes.length) {
        return (
          cartes: autres,
          message: 'Pas assez de films ${_suite(emotion)} de cette durée : j\'ai pris des films un peu plus longs (${plusLong.libelle.toLowerCase()}).',
        );
      }
    }
    if (cartes.isNotEmpty) return (cartes: cartes, message: null);
    // Rien pour cette envie : les meilleurs films qui tiennent dans la durée.
    final secours = Emotion.values
        .where((e) => e != emotion)
        .map((e) => tirer(catalogue: catalogue, emotion: e, duree: duree, profil: profil, paysVus: paysVus, niveau: niveau))
        .fold<List<CarteDefi>>([], (a, b) => b.length > a.length ? b : a);
    if (secours.isNotEmpty) {
      return (cartes: secours, message: 'Je n\'ai aucun film ${_suite(emotion)} pour l\'instant : voici mes meilleures cartes pour une autre envie.');
    }
    return (cartes: const [], message: 'Ta bibliothèque n\'a encore aucun film noté 3 étoiles ou plus que tu n\'aies pas vu. Ajoute des films, ou passe en sélection de démonstration dans les réglages.');
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

  static int casesAccordees({required int demandees, required int dejaGagneesAujourdhui, int plafond = casesParJourMax}) {
    final reste = plafond - dejaGagneesAujourdhui;
    if (reste <= 0) return 0;
    return demandees.clamp(0, reste);
  }
}
