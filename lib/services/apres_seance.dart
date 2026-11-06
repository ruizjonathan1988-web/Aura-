import 'dart:math';

import 'traduction.dart';

/// Une question du défi d'après-séance : 4 réponses, une seule juste.
class QuestionApres {
  const QuestionApres(this.texte, this.reponses, this.bonne);

  final String texte;
  final List<String> reponses;
  final int bonne;
}

/// Le défi d'après-séance (R44) : trois questions sur le film qu'on vient de
/// voir (décennie, pays, genre), rien à taper. Chaque bonne réponse vaut un
/// point d'audace, et un sans-faute en vaut deux de plus.
abstract final class DefiApres {
  static const parBonneReponse = 1;
  static const bonusSansFaute = 2;

  static const _paysConnus = ['France', 'États-Unis', 'Royaume-Uni', 'Italie', 'Japon', 'Corée du Sud', 'Allemagne', 'Espagne', 'Inde', 'Mexique'];
  static const _genresConnus = ['comédie', 'drame', 'thriller', 'horreur', 'animation', 'science-fiction', 'romance', 'aventure', 'policier', 'guerre'];

  static List<QuestionApres> questions({required String titre, int? annee, List<String> pays = const [], List<String> genres = const [], int graine = 0}) {
    final hasard = Random(graine);
    QuestionApres? choix(String texte, String juste, List<String> leurres) {
      final autres = leurres.where((l) => l != juste).toList()..shuffle(hasard);
      if (autres.length < 3) return null;
      final r = [juste, ...autres.take(3)]..shuffle(hasard);
      return QuestionApres(texte, r, r.indexOf(juste));
    }

    final q = <QuestionApres?>[
      if (annee != null)
        choix('En quelle décennie est sorti « $titre » ?', 'Années ${(annee ~/ 10) * 10}',
            [for (var d = 1930; d <= 2020; d += 10) 'Années $d']),
      if (pays.isNotEmpty) choix('D\'où vient « $titre » ?', Traduction.pays(pays.first), _paysConnus),
      if (genres.isNotEmpty) choix('Quel est le genre de « $titre » ?', Traduction.genre(genres.first), _genresConnus),
    ];
    return q.whereType<QuestionApres>().toList();
  }

  /// L'audace gagnée pour [justes] bonnes réponses sur [total].
  static int audace(int justes, int total) => justes * parBonneReponse + (total > 0 && justes == total ? bonusSansFaute : 0);
}

/// La rareté d'une Pop-carte de l'album du mois (R44), selon le niveau visé
/// et le défi d'après-séance.
enum Rarete {
  commune('Commune'),
  rare('Rare'),
  epique('Épique'),
  legendaire('Légendaire');

  const Rarete(this.nom);
  final String nom;

  static Rarete de({int? niveau}) => switch (niveau) {
        null || <= 3 => commune,
        <= 6 => rare,
        <= 9 => epique,
        _ => legendaire,
      };
}
