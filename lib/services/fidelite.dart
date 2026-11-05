import 'etat.dart';

/// Revenir doit toujours faire plaisir, jamais culpabiliser.
abstract final class Fidelite {
  /// À partir de combien de jours d'absence on offre la carte de rattrapage.
  static const pause = 3;

  /// Les cases offertes par la carte de rattrapage (plafond du jour compris).
  static const rattrapage = 2;

  static DateTime _lundi(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  static int _semaine(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000 ~/ 7;

  /// La série se compte en semaines où l'on a vu au moins un film. Une
  /// semaine sans film est une pause gratuite : elle ne casse pas la série.
  /// Deux semaines vides d'affilée la remettent à zéro, sans reproche.
  static int serie(DateTime maintenant, List<Billet> billets) {
    final semaines = billets.map((b) => _semaine(_lundi(b.date))).toSet();
    var courante = _semaine(_lundi(maintenant));
    // La semaine en cours ne compte que si on a déjà joué ; sinon on part
    // de la précédente, pour ne pas perdre sa série un lundi matin.
    if (!semaines.contains(courante)) courante--;
    var serie = 0;
    var vides = 0;
    for (var s = courante; s > courante - 520; s--) {
      if (semaines.contains(s)) {
        serie++;
        vides = 0;
      } else {
        vides++;
        if (vides >= 2) break;
      }
    }
    return serie;
  }

  /// Nombre de jours depuis la dernière visite, ou null au premier lancement.
  static int? joursDAbsence(DateTime? derniere, DateTime maintenant) {
    if (derniere == null) return null;
    final a = DateTime(derniere.year, derniere.month, derniere.day);
    final b = DateTime(maintenant.year, maintenant.month, maintenant.day);
    return b.difference(a).inDays;
  }
}
