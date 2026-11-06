import 'rivaux.dart';

/// Une notification de jeu prévue.
class AvisPrevu {
  const AvisPrevu(this.moment, this.titre, this.texte);

  final DateTime moment;
  final String titre;
  final String texte;
}

/// Les notifications de jeu (R45) : utiles et rares. Au plus deux par
/// semaine (le lundi, la charge de pouvoir revenue ; le jour de la crasse
/// d'un rival), à 18 h 30, jamais le même jour que le rappel « Alors, ce
/// film ? », et on peut les couper dans les Réglages.
abstract final class AvisDuJeu {
  static const heure = 18;
  static const minute = 30;

  static DateTime _a1830(DateTime d) => DateTime(d.year, d.month, d.day, heure, minute);

  static bool _memeJour(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Les avis des sept prochains jours.
  static List<AvisPrevu> prevus({
    required DateTime maintenant,
    required bool pouvoirs,
    required bool crasses,
    DateTime? rappelAlorsCeFilm,
    bool actifs = true,
  }) {
    if (!actifs) return const [];
    final avis = <AvisPrevu>[];
    for (var j = 0; j < 7; j++) {
      final jour = DateTime(maintenant.year, maintenant.month, maintenant.day + j);
      final moment = _a1830(jour);
      if (!moment.isAfter(maintenant)) continue;
      if (rappelAlorsCeFilm != null && _memeJour(rappelAlorsCeFilm, jour)) continue;
      if (pouvoirs && jour.weekday == DateTime.monday) {
        avis.add(AvisPrevu(moment, 'Nouvelle semaine dans Aura', 'Ta charge de pouvoir est revenue. Pop t\'attend sur le plateau.'));
        continue;
      }
      final c = Rivaux.crasseDeLaSemaine(moment);
      final hier = Rivaux.crasseDeLaSemaine(moment.subtract(const Duration(days: 1)));
      if (crasses && c != null && (hier == null || jour.weekday == DateTime.monday)) {
        avis.add(AvisPrevu(moment, '${c.rival.nom} t\'a fait une crasse', '${c.crasse.nom} ! Va la parer ou la renvoyer sur le plateau.'));
      }
    }
    return avis;
  }
}
