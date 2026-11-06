import '../models/modeles.dart';
import 'affiche.dart';

/// Quand un pouvoir agit : au prochain tirage de Ce soir, ou au prochain billet.
enum MomentPouvoir { tirage, billet }

/// Les pouvoirs des pions (R39). Chaque profil a le sien, qui vaut à peu près
/// une case par semaine, pour que personne ne soit avantagé.
///
/// - Une charge par semaine, plus une par tranche de 20 points d'audace du mois.
/// - Le joueur arme son pouvoir dans Ce soir ; il agit au prochain tirage
///   (Boussole, Madeleine) ou au prochain billet (les autres). La charge part
///   à ce moment-là, même si la condition n'est pas remplie.
/// - Les cases gagnées restent sous le plafond du jour.
abstract final class Pouvoirs {
  /// Les points d'audace qui donnent une charge de plus.
  static const audaceParCharge = 20;

  static MomentPouvoir moment(Profil p) =>
      p == Profil.explorateur || p == Profil.fidele ? MomentPouvoir.tirage : MomentPouvoir.billet;

  /// Ce qui se passe quand le pouvoir agit, en une ligne pour l'écran.
  static String quand(Profil p) => moment(p) == MomentPouvoir.tirage ? 'au prochain tirage' : 'à ta prochaine séance';

  /// Les charges qui restent : celle de la semaine si elle n'a pas servi,
  /// plus celles de l'audace du mois qui n'ont pas servi.
  static int charges({required DateTime maintenant, required List<UsagePouvoir> usages, required int audaceDuMois}) =>
      (chargeDeLaSemaine(maintenant: maintenant, usages: usages) ? 1 : 0) +
      chargesDAudace(maintenant: maintenant, usages: usages, audaceDuMois: audaceDuMois);

  static bool chargeDeLaSemaine({required DateTime maintenant, required List<UsagePouvoir> usages}) {
    final lundi = Affiche.lundiDe(maintenant);
    return !usages.any((u) => !u.audace && Affiche.lundiDe(u.date) == lundi);
  }

  static int chargesDAudace({required DateTime maintenant, required List<UsagePouvoir> usages, required int audaceDuMois}) {
    final prises = usages.where((u) => u.audace && u.date.year == maintenant.year && u.date.month == maintenant.month).length;
    final r = audaceDuMois ~/ audaceParCharge - prises;
    return r < 0 ? 0 : r;
  }

  /// La case de plus que rapporte un pouvoir « au billet » (le Marathon
  /// n'ajoute rien : il relève le plafond, voir [plafond]).
  static int bonus(
    Profil p, {
    required int pronostic,
    int? note,
    int? dureeMinutes,
    bool aPlusieurs = false,
    bool derrierePop = false,
  }) =>
      switch (p) {
        Profil.degustateur => note != null ? 1 : 0,
        Profil.critique => note != null && note == pronostic ? 1 : 0,
        Profil.presse => dureeMinutes != null && dureeMinutes < 90 ? 1 : 0,
        Profil.hote => aPlusieurs ? 1 : 0,
        Profil.supporter => derrierePop ? 1 : 0,
        _ => 0,
      };

  /// Le Marathon du Dévoreur : plafond du jour à 4 pour ce billet.
  static int plafond(Profil p, int plafondDuNiveau) => p == Profil.devoreur && plafondDuNiveau < 4 ? 4 : plafondDuNiveau;

  /// La Boussole de l'Explorateur : une 4e carte au tirage.
  static int cartesAuTirage(Profil p) => p == Profil.explorateur ? 4 : 3;

  /// La Madeleine du Fidèle : le tirage peut proposer des films déjà vus.
  static bool revoir(Profil p) => p == Profil.fidele;

  /// Ce que dit Pop quand le pouvoir agit, ou fait chou blanc.
  static String phrase(Profil p, {required bool agi}) => agi
      ? switch (p) {
          Profil.explorateur => 'Boussole ! Une quatrième carte pour toi. Je n\'étais pas d\'accord, mais bon.',
          Profil.fidele => 'Madeleine ! Tes vieux amis peuvent revenir dans la main ce soir.',
          Profil.degustateur => 'Slow : une séance notée, une case de plus. Tu prends ton temps, et ça paie.',
          Profil.critique => 'Plume : pronostic pile poil, une case de plus. Je déteste quand tu as raison.',
          Profil.devoreur => 'Marathon : tu as dépassé le plafond du jour. Va dormir, maintenant.',
          Profil.presse => 'Court-métrage : moins d\'une heure et demie, une case de plus. Efficace.',
          Profil.hote => 'Projectionniste : une séance à plusieurs, une case de plus.',
          Profil.supporter => 'Remontada ! Tu étais derrière moi : une case de plus. Ne t\'habitue pas.',
        }
      : switch (p) {
          Profil.degustateur => 'Slow : pas de note, pas de bonus. La charge est partie quand même.',
          Profil.critique => 'Plume : pronostic à côté. La charge est partie, désolé (pas tant que ça).',
          Profil.devoreur => 'Marathon : tu n\'avais pas besoin de dépasser le plafond. Charge utilisée.',
          Profil.presse => 'Court-métrage : ce film dure plus d\'une heure et demie. Charge utilisée.',
          Profil.hote => 'Projectionniste : séance en solo, pas de bonus. Charge utilisée.',
          Profil.supporter => 'Remontada : tu étais devant moi, rien à remonter. Charge utilisée.',
          _ => 'Ton pouvoir a fait chou blanc. Charge utilisée.',
        };
}

/// Une charge utilisée : sa date, et si c'était une charge d'audace.
class UsagePouvoir {
  const UsagePouvoir(this.date, {this.audace = false});

  final DateTime date;
  final bool audace;

  String versTexte() => '${date.toIso8601String()}|${audace ? 'a' : 's'}';

  static UsagePouvoir? depuisTexte(String t) {
    final parts = t.split('|');
    final d = DateTime.tryParse(parts.first);
    if (d == null) return null;
    return UsagePouvoir(d, audace: parts.length > 1 && parts[1] == 'a');
  }
}
