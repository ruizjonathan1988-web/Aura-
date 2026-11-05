import 'dart:math';

import '../models/modeles.dart';

/// Une carte posée sur la table du Duel.
class CarteEnJeu {
  CarteEnJeu(this.carte, this.joueur);

  final CarteDefi carte;

  /// 0 ou 1 : à qui appartient la carte.
  final int joueur;
  bool ecartee = false;
  bool protegee = false;
}

/// Le Duel du canapé : chacun pose ses 3 cartes, puis on écarte à tour de
/// rôle une carte de l'autre. Chacun a un Veto pour protéger une de ses
/// cartes. Quand l'autre n'a plus qu'une carte, on écarte une des siennes.
/// À la fin, il reste une carte par joueur : le mini-quiz départage.
class Duel {
  Duel(List<CarteDefi> a, List<CarteDefi> b)
      : cartes = [
          for (final c in a) CarteEnJeu(c, 0),
          for (final c in b) CarteEnJeu(c, 1),
        ];

  final List<CarteEnJeu> cartes;
  int tour = 0;
  final veto = [true, true];

  int get adversaire => 1 - tour;

  List<CarteEnJeu> restantes(int joueur) => cartes.where((c) => c.joueur == joueur && !c.ecartee).toList();

  bool get fini => restantes(0).length <= 1 && restantes(1).length <= 1;

  /// À qui le joueur du tour doit prendre une carte.
  int get cible => restantes(adversaire).length > 1 ? adversaire : tour;

  bool peutEcarter(CarteEnJeu c) {
    if (fini || c.ecartee || c.joueur != cible) return false;
    return !(c.joueur == adversaire && c.protegee);
  }

  bool peutProteger(CarteEnJeu c) => !fini && veto[tour] && c.joueur == tour && !c.ecartee && !c.protegee;

  void ecarter(CarteEnJeu c) {
    if (!peutEcarter(c)) throw StateError('Carte impossible à écarter');
    c.ecartee = true;
    tour = adversaire;
  }

  void proteger(CarteEnJeu c) {
    if (!peutProteger(c)) throw StateError('Veto impossible');
    c.protegee = true;
    veto[tour] = false;
    tour = adversaire;
  }

  /// Les deux cartes finalistes, celle du joueur 0 puis celle du joueur 1.
  List<CarteEnJeu> get finalistes => [restantes(0).first, restantes(1).first];
}

/// Une question du mini-quiz : la bonne réponse est toujours la première,
/// l'ordre est mélangé à l'affichage.
class Question {
  const Question(this.texte, this.reponses);
  final String texte;
  final List<String> reponses;

  String get bonne => reponses.first;
}

abstract final class Quiz {
  /// Des questions sur des films reconnus (ceux de la sélection Aura).
  static const questions = [
    Question('Dans « Le Parrain », qui joue Vito Corleone ?', ['Marlon Brando', 'Al Pacino', 'Robert De Niro', 'James Caan']),
    Question('Qui a réalisé « Parasite », Palme d\'or 2019 ?', ['Bong Joon-ho', 'Park Chan-wook', 'Hirokazu Kore-eda', 'Kim Jee-woon']),
    Question('Quel studio a créé « Le Voyage de Chihiro » ?', ['Le studio Ghibli', 'Pixar', 'Toei Animation', 'DreamWorks']),
    Question('Dans « Retour vers le futur », en quelle année Marty se retrouve-t-il ?', ['1955', '1945', '1965', '1975']),
    Question('Qui a réalisé « Les Quatre Cents Coups » ?', ['François Truffaut', 'Jean-Luc Godard', 'Éric Rohmer', 'Claude Chabrol']),
    Question('Comment « La Haine » de Mathieu Kassovitz a-t-il été tourné ?', ['En noir et blanc', 'En couleur', 'En un seul plan', 'En animation']),
    Question('Dans quel quartier de Paris vit Amélie Poulain ?', ['Montmartre', 'Belleville', 'Le Marais', 'Saint-Germain-des-Prés']),
    Question('Dans « Intouchables », qui joue Philippe ?', ['François Cluzet', 'Daniel Auteuil', 'Fabrice Luchini', 'Jean Dujardin']),
    Question('Comment s\'appelle le motel de « Psychose » ?', ['Le Bates Motel', 'Le Overlook', 'Le Continental', 'Le Grand Budapest']),
    Question('Comment s\'appelle l\'hôtel isolé de « Shining » ?', ['L\'Overlook', 'Le Bates Motel', 'Le Grand Budapest', 'Le Continental']),
    Question('Comment s\'appelle le vaisseau d\'« Alien, le huitième passager » ?', ['Le Nostromo', 'Le Discovery', 'L\'Enterprise', 'Le Millennium Falcon']),
    Question('Qui a composé la musique du « Bon, la Brute et le Truand » ?', ['Ennio Morricone', 'John Williams', 'Nino Rota', 'Maurice Jarre']),
    Question('Qui a composé la musique du « Parrain » ?', ['Nino Rota', 'Ennio Morricone', 'Hans Zimmer', 'Howard Shore']),
    Question('Dans quel pays a été tournée la trilogie « Le Seigneur des anneaux » ?', ['La Nouvelle-Zélande', 'L\'Irlande', 'L\'Islande', 'Le Canada']),
    Question('Quel duo mène « La Grande Vadrouille » ?', ['Bourvil et Louis de Funès', 'Jean Gabin et Lino Ventura', 'Pierre Richard et Gérard Depardieu', 'Fernandel et Gino Cervi']),
    Question('Dans « Le Dîner de cons », comment s\'appelle le personnage de Jacques Villeret ?', ['François Pignon', 'Pierre Brochant', 'Juste Leblanc', 'Lucien Cheval']),
    Question('« Les Évadés » est adapté d\'une nouvelle de…', ['Stephen King', 'John Grisham', 'Michael Crichton', 'Dennis Lehane']),
    Question('De quel instrument joue le héros de « Whiplash » ?', ['De la batterie', 'De la trompette', 'Du piano', 'De la contrebasse']),
    Question('Quelle fête mexicaine est au cœur de « Coco » ?', ['Le jour des Morts', 'Le carnaval', 'Noël', 'La fête de l\'Indépendance']),
    Question('Où se déroule presque tout « 12 hommes en colère » ?', ['Dans une salle de délibération', 'Dans un tribunal', 'Dans une prison', 'Dans un train']),
    Question('Dans « Mad Max: Fury Road », qui joue Furiosa ?', ['Charlize Theron', 'Emily Blunt', 'Sigourney Weaver', 'Cate Blanchett']),
    Question('Dans « Le Silence des agneaux », qui joue Hannibal Lecter ?', ['Anthony Hopkins', 'Gary Oldman', 'Ralph Fiennes', 'Jack Nicholson']),
    Question('Dans « Le Cinquième Élément », qui joue le chauffeur de taxi ?', ['Bruce Willis', 'Harrison Ford', 'Mel Gibson', 'Kurt Russell']),
    Question('Qui joue OSS 117 dans « Le Caire, nid d\'espions » ?', ['Jean Dujardin', 'Gilles Lellouche', 'José Garcia', 'Alain Chabat']),
    Question('Quelle est la plus haute récompense du Festival de Cannes ?', ['La Palme d\'or', 'L\'Ours d\'or', 'Le Lion d\'or', 'Le César du meilleur film']),
    Question('« Persepolis » est adapté de la bande dessinée de…', ['Marjane Satrapi', 'Riad Sattouf', 'Joann Sfar', 'Enki Bilal']),
  ];

  /// [n] questions tirées au hasard, réponses mélangées.
  static List<Question> tirer(int n, Random hasard) {
    final q = [...questions]..shuffle(hasard);
    return q.take(n).toList();
  }
}
