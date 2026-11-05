import 'dart:math';

import '../models/modeles.dart';
import 'tirage.dart';

/// Une question du test « Quel spectateur es-tu ? ». Chaque réponse pointe
/// vers un profil ; chaque profil apparaît trois fois dans le test.
class QuestionProfil {
  const QuestionProfil(this.texte, this.reponses);
  final String texte;
  final List<(String, Profil)> reponses;
}

abstract final class TestSpectateur {
  static const questions = [
    QuestionProfil('Un dimanche soir de libre : que fais-tu ?', [
      ('J\'enchaîne trois épisodes d\'affilée', Profil.devoreur),
      ('Je regarde un seul film, et j\'y repense ensuite', Profil.degustateur),
      ('Je mets un match ou un direct', Profil.supporter),
      ('J\'invite des amis pour une soirée film', Profil.hote),
    ]),
    QuestionProfil('Ton film préféré, c\'est plutôt…', [
      ('Un film que je revois chaque année', Profil.fidele),
      ('Un film venu d\'un pays que je connais mal', Profil.explorateur),
      ('Un film qu\'on peut analyser pendant des heures', Profil.critique),
      ('Un film de moins d\'une heure et demie', Profil.presse),
    ]),
    QuestionProfil('Un ami te recommande un film ou une série. Que fais-tu ?', [
      ('Je le regarde et je lui donne ma note', Profil.critique),
      ('Je lui propose qu\'on le regarde ensemble', Profil.hote),
      ('J\'ajoute toute la saison à ma liste', Profil.devoreur),
      ('Je regarde la bande-annonce en accéléré', Profil.presse),
    ]),
    QuestionProfil('Qu\'est-ce qui te fait vibrer ?', [
      ('Le suspense d\'un direct', Profil.supporter),
      ('Retrouver mes personnages préférés', Profil.fidele),
      ('Découvrir une époque que je ne connais pas', Profil.explorateur),
      ('Prendre le temps de savourer', Profil.degustateur),
    ]),
    QuestionProfil('Pour toi, le pire, c\'est…', [
      ('Un film trop long', Profil.presse),
      ('Regarder seul', Profil.hote),
      ('Un film dont on n\'a rien à dire', Profil.critique),
      ('Revoir toujours les mêmes films', Profil.explorateur),
    ]),
    QuestionProfil('Ta soirée idéale ?', [
      ('Revoir mes films fétiches', Profil.fidele),
      ('Une finale de coupe', Profil.supporter),
      ('Un film rare avec une tisane', Profil.degustateur),
      ('Une nuit blanche devant une série', Profil.devoreur),
    ]),
  ];

  /// Le profil le plus choisi. En cas d'égalité, le plus récemment choisi
  /// l'emporte : c'est la réponse la plus « à chaud ».
  static Profil resultat(List<Profil> reponses) {
    if (reponses.isEmpty) return Profil.fidele;
    final compte = <Profil, int>{};
    for (final p in reponses) {
      compte[p] = (compte[p] ?? 0) + 1;
    }
    final max = compte.values.reduce((a, b) => a > b ? a : b);
    return reponses.lastWhere((p) => compte[p] == max);
  }

  static String partage(Profil p) => 'Dans Aura, je suis ${p.nom}, pouvoir ${p.pouvoir}. Et toi, quel spectateur es-tu ? Fais le test dans Aura, un jeu VJOD.';
}

/// Le mini-Bluff du premier soir : un film, son vrai synopsis et deux faux
/// écrits par Pop. Trouver le vrai rapporte le Joker du Bluff.
class BluffDePop {
  const BluffDePop({required this.film, required this.synopsis, required this.vrai});

  final Film film;
  final List<String> synopsis;

  /// L'indice du vrai synopsis dans [synopsis].
  final int vrai;

  static const fauxDePop = [
    'Un projectionniste découvre que chaque film qu\'il diffuse change le passé de sa ville.',
    'Trois sœurs héritent d\'un phare et d\'une dette envers un contrebandier très patient.',
    'Un pâtissier amnésique se réveille dans un train de nuit avec une valise pleine de cartes postales.',
    'Deux cambrioleurs maladroits se trompent de maison et tombent sur un congrès de magiciens.',
    'Une championne d\'échecs à la retraite accepte une dernière partie contre un adversaire qui ne parle jamais.',
    'Dans un village de montagne, un facteur intercepte les lettres d\'amour pour les réécrire à sa façon.',
    'Une astronaute coincée en orbite ne peut plus parler à la Terre que par un radioamateur de dix ans.',
    'Un chef d\'orchestre devenu sourd prépare en secret le concert de sa vie.',
    'Un détective privé enquête sur la disparition d\'un chat qui appartient à tout un quartier.',
    'Un vieux forain et sa petite-fille traversent le pays pour ramener un manège dans sa ville natale.',
    'Une famille de vampires végétariens tente de passer inaperçue dans une banlieue pavillonnaire.',
    'La veille de sa première finale, un jeune boxeur promet à sa mère de ne jamais monter sur un ring.',
  ];

  /// Choisit un film à 3 étoiles ou plus, pas encore vu, avec un synopsis,
  /// hors documentaires. Renvoie null si le catalogue n'en a aucun.
  static BluffDePop? pour(List<Film> catalogue, Random hasard) {
    final candidats = catalogue.where((f) {
      final doc = f.genres.any((g) => ['documentary', 'documentaire'].contains(g.toLowerCase()));
      return Tirage.assezBon(f) && !f.dejaVu && !doc && premierePhrase(f.synopsis).length >= 30;
    }).toList();
    if (candidats.isEmpty) return null;
    final film = candidats[hasard.nextInt(candidats.length)];
    final faux = [...fauxDePop]..shuffle(hasard);
    final vrai = premierePhrase(film.synopsis);
    final liste = [vrai, faux[0], faux[1]]..shuffle(hasard);
    return BluffDePop(film: film, synopsis: liste, vrai: liste.indexOf(vrai));
  }

  /// La première phrase d'un synopsis, pour qu'il ait la même allure que
  /// ceux de Pop (une phrase, pas un roman).
  static String premierePhrase(String? texte) {
    final t = (texte ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return '';
    final fin = RegExp(r'[.!?…](\s|$)').firstMatch(t);
    final phrase = fin == null ? t : t.substring(0, fin.start + 1);
    return phrase.length > 220 ? '${phrase.substring(0, 217).trimRight()}…' : phrase;
  }
}
