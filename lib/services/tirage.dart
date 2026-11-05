import 'dart:math';

import '../models/modeles.dart';

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
    final candidats = catalogue
        .where((f) => !f.dejaVu && assezBon(f) && correspond(f, emotion, duree))
        .toList()
      ..shuffle(_hasard);
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
        defi: 'Un film d\'avant 1980',
        indice: _indice(retro),
        cases: 3,
        joker: 'Ton Joker Nostalgique double les cases de cette carte',
        film: retro,
        bulleDePop: 'Un film d\'avant 1980 ? Fais pas cette tête, le noir et blanc ne mord pas.',
      ));
    }

    final voyage = prendre((f) => f.pays.isNotEmpty && !f.pays.any(paysVus.contains));
    if (voyage != null) {
      cartes.add(CarteDefi(
        type: TypeCarte.voyage,
        defi: 'Un pays jamais vu',
        indice: _indice(voyage),
        cases: 2,
        joker: 'Ton Joker Voyageur ajoute une case',
        film: voyage,
        bulleDePop: 'Un pays jamais vu. Prépare ton passeport et tes sous-titres !',
      ));
    }

    final pepite = prendre((f) => (f.note ?? 0) >= 7.5);
    if (pepite != null) {
      cartes.add(CarteDefi(
        type: TypeCarte.pepite,
        defi: 'Une pépite à plus de 3,7 étoiles',
        indice: _indice(pepite),
        cases: 2,
        joker: 'Une pépite rapporte un bonus de Flair si tu la conseilles',
        film: pepite,
        bulleDePop: 'Celle-là, je l\'ai gardée pour toi. Ne me déçois pas.',
      ));
    }

    while (cartes.length < 3) {
      final f = prendre((_) => true);
      if (f == null) break;
      cartes.add(CarteDefi(
        type: TypeCarte.envie,
        defi: 'Pile dans ton envie : ${emotion.libelle.toLowerCase()}',
        indice: _indice(f),
        cases: 1,
        joker: 'Une carte sûre, une case assurée',
        film: f,
        bulleDePop: 'Pas de défi ce soir ? Pas de souci, je ne juge pas. Enfin, un peu.',
      ));
    }
    return cartes.take(3).toList();
  }

  /// Un indice qui ne donne ni le titre ni l'année exacte.
  String _indice(Film f) {
    final parts = <String>[];
    if (f.annee != null) parts.add('Années ${(f.annee! ~/ 10) * 10}');
    if (f.pays.isNotEmpty) parts.add(f.pays.first);
    if (f.genres.isNotEmpty) parts.add(f.genres.first.toLowerCase());
    if (f.dureeMinutes != null) parts.add('${f.dureeMinutes} min');
    return parts.join(', ');
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
