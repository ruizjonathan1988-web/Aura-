import 'dart:math';

import '../models/modeles.dart';
import 'tirage.dart';
import 'traduction.dart';

/// Le Plan du jour : un film à deviner en 3 indices, 1 seul essai.
/// Même film pour tout le monde le même jour (à catalogue égal), et une
/// réponse à choisir parmi 4 : rien à taper, tout se joue à la télécommande.
class PlanDuJour {
  const PlanDuJour({required this.film, required this.indices, required this.choix});

  final Film film;
  final List<String> indices;
  final List<Film> choix;

  static PlanDuJour? du(DateTime jour, List<Film> catalogue) {
    final vus = <String>{};
    final bons = catalogue.where((f) => Tirage.assezBon(f) && vus.add(f.titre.toLowerCase())).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (bons.length < 4) return null;
    final hasard = Random(jour.year * 10000 + jour.month * 100 + jour.day);
    // Un film reconnu à deviner ; les mauvaises réponses viennent de partout.
    final haut = Tirage.hautDuPanier(bons);
    final film = haut[hasard.nextInt(haut.length)];
    final autres = bons.where((f) => f.id != film.id).toList()..shuffle(hasard);
    final choix = [film, ...autres.take(3)]..shuffle(hasard);
    return PlanDuJour(film: film, indices: indicesPour(film), choix: choix);
  }

  /// Du plus vague au plus précis : genre et époque, pays et durée, réalisation.
  static List<String> indicesPour(Film f) {
    final genre = f.genres.isEmpty ? null : Traduction.genre(f.genres.first);
    final epoque = f.annee == null ? null : 'années ${f.annee! ~/ 10 * 10}';
    final pays = f.pays.isEmpty ? null : Traduction.pays(f.pays.first);
    final duree = f.dureeMinutes == null ? null : Traduction.duree(f.dureeMinutes!);
    return [
      [if (genre != null) 'Genre : $genre', if (epoque != null) 'Époque : $epoque'].join(' · ').ifEmpty('Un film noté 3 étoiles ou plus'),
      [if (pays != null) 'Pays : $pays', if (duree != null) 'Durée : $duree'].join(' · ').ifEmpty('Il est dans ta bibliothèque'),
      f.realisateur != null ? 'Réalisation : ${f.realisateur}' : (f.annee != null ? 'Sorti en ${f.annee}' : 'Dernière chance !'),
    ];
  }
}

/// Ce que le joueur a fait au Plan du jour : combien d'indices il a ouverts
/// avant de répondre, et s'il a trouvé.
class ResultatPlan {
  const ResultatPlan({required this.indices, required this.trouve});

  final int indices;
  final bool trouve;

  /// Le résultat à partager, sans dévoiler le film.
  String partage(DateTime jour) {
    const mois = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    final cases = List.generate(3, (i) {
      if (i < indices - 1) return '🟨';
      if (i == indices - 1) return trouve ? '🟩' : '🟥';
      return '⬜';
    }).join();
    final phrase = trouve ? 'Trouvé au ${indices == 1 ? '1er' : '${indices}e'} indice' : 'Raté, ce film m\'a eu';
    return 'Aura · Plan du jour du ${jour.day} ${mois[jour.month - 1]}\n$cases $phrase\nUn jeu VJOD';
  }
}

extension on String {
  String ifEmpty(String autre) => isEmpty ? autre : this;
}
