/// Le déblocage progressif (R42) : le premier soir, on joue juste ses cartes
/// sur le plateau. Les règles s'ouvrent ensuite séance après séance, et Pop
/// présente chacune au moment où elle arrive.
enum Etape {
  deck(2, 'Ton deck d\'atouts',
      'Chaque jour, un booster gratuit de trois atouts. Pose-les dans ton deck : quand ton film remplit leur défi, ils rapportent de l\'audace, et les plus rares une case.'),
  niveaux(3, 'Tu te mets combien ?',
      'Avant chaque tirage, tu annonces un niveau de 1 à 10. Plus tu vises haut, plus les films sont pointus et plus ça rapporte. Ton audace du mois s\'additionne.'),
  festival(4, 'Le Festival de la semaine',
      'Chaque lundi, j\'annonce une règle folle pour la semaine, et un défi à relever. La même pour tout le monde : comparez-vous.'),
  pouvoirs(5, 'Ton pouvoir',
      'Ta figurine a un pouvoir. Arme-le dans Ce soir : il agit au prochain tirage ou à la prochaine séance. Une charge par semaine, plus une tous les 20 points d\'audace.'),
  casse(6, 'Le Casse de la Cinémathèque',
      'La dernière semaine de chaque mois, braque mon coffre : quatre serrures, un film chacune. Et méfie-toi : il y a peut-être une Taupe dans l\'équipe.'),
  coups(7, 'Coups de théâtre',
      'Les cases 4, 14 et 24 cachent un coup du sort, et deux Jokers arrivent : Volte-face quand tu es derrière moi, et le pari de Sisyphe en début de mois.'),
  crasses(9, 'Les crasses',
      'Dans ta ligue, tu peux faire une crasse par semaine à un ami. Il peut l\'encaisser, la parer ou te la renvoyer. Tes rivaux aussi vont s\'y mettre.');

  const Etape(this.seances, this.titre, this.explication);

  /// Le nombre de séances validées qui ouvre l'étape.
  final int seances;
  final String titre;
  final String explication;
}

abstract final class Deblocage {
  static bool ouvert(Etape e, {required int seances, bool toutOuvert = false}) => toutOuvert || seances >= e.seances;

  /// La prochaine étape à ouvrir, ou null si tout est ouvert.
  static Etape? prochaine({required int seances, bool toutOuvert = false}) {
    if (toutOuvert) return null;
    for (final e in Etape.values) {
      if (seances < e.seances) return e;
    }
    return null;
  }

  /// L'étape ouverte que Pop n'a pas encore présentée (la plus ancienne d'abord).
  static Etape? aAnnoncer({required int seances, required Set<String> annoncees, bool toutOuvert = false}) {
    if (toutOuvert) return null;
    for (final e in Etape.values) {
      if (seances >= e.seances && !annoncees.contains(e.name)) return e;
    }
    return null;
  }
}

/// La situation du soir, pour la carte « Ce soir pour toi ».
class Situation {
  const Situation({
    required this.seances,
    required this.position,
    required this.pop,
    required this.casesRestantes,
    this.toutOuvert = false,
    this.coupEnAttente,
    this.pouvoirCharge = false,
    this.pouvoirArme = false,
    this.nomPouvoir = '',
    this.niveauImpose,
    this.sisyphe = false,
  });

  final int seances;
  final int position;
  final int pop;
  final int casesRestantes;
  final bool toutOuvert;
  final int? coupEnAttente;
  final bool pouvoirCharge;
  final bool pouvoirArme;
  final String nomPouvoir;
  final int? niveauImpose;
  final bool sisyphe;
}

/// « Ce soir pour toi » : deux lignes au plus, la plus urgente d'abord.
abstract final class CeSoirPourToi {
  static List<String> lignes(Situation s) {
    bool ouvert(Etape e) => Deblocage.ouvert(e, seances: s.seances, toutOuvert: s.toutOuvert);
    final l = <String>[
      if (s.coupEnAttente != null) 'Un Coup de théâtre t\'attend sur le plateau, case ${s.coupEnAttente}.',
      if (s.niveauImpose != null) 'Un ami t\'a imposé le niveau ${s.niveauImpose} pour ce soir. Courage.',
      if (s.casesRestantes <= 0) 'Plafond du jour atteint : ta séance comptera dans tes billets, et demain ça repart.',
      if (s.sisyphe) 'Pari de Sisyphe en cours : n\'abandonne aucun film.',
      if (ouvert(Etape.pouvoirs) && s.pouvoirArme) 'Ton pouvoir ${s.nomPouvoir} est armé.',
      if (ouvert(Etape.pouvoirs) && s.pouvoirCharge && !s.pouvoirArme) 'Ton pouvoir ${s.nomPouvoir} est chargé : arme-le avant de tirer.',
      if (s.pop > s.position) 'Pop a ${s.pop - s.position} case${s.pop - s.position > 1 ? 's' : ''} d\'avance : une séance ce soir te rapproche.'
      else if (s.position > s.pop) 'Tu as ${s.position - s.pop} case${s.position - s.pop > 1 ? 's' : ''} d\'avance sur Pop. Garde-la.'
      else 'Pop et toi êtes sur la même case. À toi de faire la différence.',
    ];
    final suite = Deblocage.prochaine(seances: s.seances, toutOuvert: s.toutOuvert);
    final reste = suite == null ? 0 : suite.seances - s.seances;
    return [
      ...l.take(2),
      if (suite != null) 'Encore $reste séance${reste > 1 ? 's' : ''} avant la prochaine règle : « ${suite.titre} ».',
    ];
  }
}
