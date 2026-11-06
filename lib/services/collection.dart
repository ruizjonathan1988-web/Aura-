import 'package:flutter/material.dart';

import 'carte_genres.dart';
import 'etat.dart';
import 'fidelite.dart';

/// Un exploit de la collection : une fois obtenu, il reste à toi pour
/// toujours, même quand le plateau repart à zéro le mois suivant.
class Exploit {
  const Exploit(this.id, this.nom, this.description, this.icone);

  final String id;
  final String nom;
  final String description;
  final IconData icone;
}

/// Ce que l'on sait du joueur pour décerner les exploits.
class Bilan {
  const Bilan({
    required this.billets,
    required this.position,
    required this.positionDePop,
    required this.bluffsGagnes,
    required this.maintenant,
  });

  final List<Billet> billets;
  final int position;
  final int positionDePop;
  final int bluffsGagnes;
  final DateTime maintenant;
}

abstract final class Collection {
  static const mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

  static const exploits = [
    Exploit('premiere', 'Première séance', 'Valider ton premier billet.', Icons.confirmation_number_rounded),
    Exploit('dix', 'Cinéphile', 'Valider 10 séances.', Icons.movie_filter_rounded),
    Exploit('retro', 'Voyage dans le temps', 'Jouer 3 cartes Rétro.', Icons.history_rounded),
    Exploit('globe', 'Globe-trotteur', 'Voir des films de 5 pays différents.', Icons.public_rounded),
    Exploit('carte', 'Maître de la carte', 'Tenir 6 régions de la carte des genres le même mois.', Icons.map_rounded),
    Exploit('serie', 'Fidèle au poste', 'Atteindre une série de 4 semaines.', Icons.local_fire_department_rounded),
    Exploit('devant', 'Pop dépassé', 'Passer devant Pop sur le plateau.', Icons.emoji_events_rounded),
    Exploit('devin', 'Devin', 'Tomber 3 fois pile sur ton pronostic.', Icons.auto_awesome_rounded),
    Exploit('detecteur', 'Détecteur de mensonges', 'Démasquer 3 Bluffs de Pop.', Icons.psychology_alt_rounded),
    Exploit('finale', 'Jusqu\'à la finale', 'Atteindre la case 30 en un mois.', Icons.flag_circle_rounded),
  ];

  /// La figurine de saison du mois : elle ne revient jamais. On la gagne en
  /// atteignant la case 20 pendant le mois.
  static String saison(DateTime d) => 'saison_${d.year}_${d.month}';
  static String nomDeSaison(String id) {
    final p = id.split('_');
    return 'Figurine de saison, ${mois[int.parse(p[2]) - 1]} ${p[1]}';
  }

  static const caseDeSaison = 20;

  /// Les exploits (et la figurine de saison) que ce bilan mérite.
  static Set<String> merites(Bilan b) {
    final m = <String>{};
    final n = b.billets.length;
    if (n >= 1) m.add('premiere');
    if (n >= 10) m.add('dix');
    if (b.billets.where((x) => x.type == 'Rétro').length >= 3) m.add('retro');
    if (b.billets.expand((x) => x.pays).toSet().length >= 5) m.add('globe');
    if (CarteDesGenres.de(b.maintenant, b.billets).regionsDuJoueur >= 6) m.add('carte');
    if (Fidelite.serie(b.maintenant, b.billets) >= 4) m.add('serie');
    if (n >= 1 && b.position > b.positionDePop) m.add('devant');
    if (b.billets.where((x) => x.note != null && x.note == x.pronostic).length >= 3) m.add('devin');
    if (b.bluffsGagnes >= 3) m.add('detecteur');
    if (b.position >= 30) m.add('finale');
    if (b.position >= caseDeSaison) m.add(saison(b.maintenant));
    return m;
  }

  static String nomDe(String id) =>
      id.startsWith('saison_') ? nomDeSaison(id) : exploits.firstWhere((e) => e.id == id, orElse: () => const Exploit('', 'Exploit', '', Icons.star)).nom;
}
