import 'dart:math';

import '../models/modeles.dart';
import 'tirage.dart';

/// L'époque voulue, pour « Juste un film ».
enum Epoque {
  toutes('Peu importe', null, null),
  classique('Avant 1980', null, 1979),
  annees80('1980 à 1999', 1980, 1999),
  recent('Depuis 2000', 2000, null);

  const Epoque(this.libelle, this.depuis, this.jusqua);
  final String libelle;
  final int? depuis;
  final int? jusqua;

  bool contient(int? annee) {
    if (this == Epoque.toutes) return true;
    if (annee == null) return false;
    return (depuis == null || annee >= depuis!) && (jusqua == null || annee <= jusqua!);
  }
}

/// « Juste un film » : des propositions sans jeu, pour les soirs où l'on n'a
/// pas envie de jouer. On change autant qu'on veut, rien ne compte pour le
/// plateau.
///
/// Ce qui ne change pas : la règle zéro navet (3 étoiles ou plus, assez
/// d'avis) et aucun film déjà vu.
class JusteUnFilm {
  JusteUnFilm({Random? hasard}) : _hasard = hasard ?? Random();

  final Random _hasard;

  /// Les films déjà montrés depuis l'ouverture de l'écran : ils ne reviennent
  /// qu'une fois tous les autres passés.
  final Set<String> dejaMontres = {};

  static const nombre = 3;

  /// Ce qui peut être proposé, avant le mélange. Sans envie, tous les genres.
  static List<Film> possibles(List<Film> catalogue, {Emotion? emotion, required Duree duree, Epoque epoque = Epoque.toutes}) => catalogue
      .where((f) =>
          !f.dejaVu &&
          Tirage.assezBon(f) &&
          epoque.contient(f.annee) &&
          (emotion == null ? (f.dureeMinutes == null || f.dureeMinutes! <= duree.minutesMax) : Tirage.correspond(f, emotion, duree)))
      .toList();

  /// Trois nouvelles idées. Les mieux notées passent d'abord, mélangées ;
  /// un film déjà montré ne revient pas tant qu'il en reste d'autres.
  List<Film> proposer(List<Film> catalogue, {Emotion? emotion, required Duree duree, Epoque epoque = Epoque.toutes, Set<String> garder = const {}}) {
    final tous = possibles(catalogue, emotion: emotion, duree: duree, epoque: epoque);
    if (tous.isEmpty) return const [];
    var frais = tous.where((f) => !dejaMontres.contains(f.id) && !garder.contains(f.id)).toList();
    if (frais.isEmpty) {
      // Tout a défilé : on recommence le tour, sans redonner ce qui est à l'écran.
      dejaMontres.removeWhere((id) => !garder.contains(id));
      frais = tous.where((f) => !garder.contains(f.id)).toList();
    }
    final parNote = [...frais]..sort((a, b) => (b.note ?? 0).compareTo(a.note ?? 0));
    final haut = max(nombre * 3, (parNote.length * .4).ceil());
    final ordre = [...(parNote.take(haut).toList()..shuffle(_hasard)), ...(parNote.skip(haut).toList()..shuffle(_hasard))];
    final choix = ordre.take(nombre - garder.length.clamp(0, nombre)).toList();
    dejaMontres.addAll(choix.map((f) => f.id));
    return choix;
  }

  /// Remplace une seule idée de [actuels] (à la position [index]) par une
  /// autre, sans toucher aux deux restantes. Renvoie la liste à jour.
  List<Film> remplacer(List<Film> catalogue, List<Film> actuels, int index, {Emotion? emotion, required Duree duree, Epoque epoque = Epoque.toutes}) {
    if (index < 0 || index >= actuels.length) return actuels;
    final garder = {for (final (i, f) in actuels.indexed) if (i != index) f.id};
    dejaMontres.add(actuels[index].id);
    final tous = possibles(catalogue, emotion: emotion, duree: duree, epoque: epoque);
    var frais = tous.where((f) => !dejaMontres.contains(f.id) && !garder.contains(f.id)).toList();
    if (frais.isEmpty) {
      dejaMontres.removeWhere((id) => !garder.contains(id));
      frais = tous.where((f) => !garder.contains(f.id) && f.id != actuels[index].id).toList();
    }
    if (frais.isEmpty) return actuels;
    final parNote = [...frais]..sort((a, b) => (b.note ?? 0).compareTo(a.note ?? 0));
    final haut = parNote.take(max(nombre * 3, (parNote.length * .4).ceil())).toList();
    final nouveau = haut[_hasard.nextInt(haut.length)];
    dejaMontres.add(nouveau.id);
    return [for (final (i, f) in actuels.indexed) i == index ? nouveau : f];
  }
}
