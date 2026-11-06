import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/modeles.dart';

/// D'où viennent les films proposés par le jeu.
abstract class SourceFilms {
  String get nom;

  /// Les films de la source. Sans [emotion], tous les genres. [auHasard] à
  /// faux donne toujours le même ordre (utile au Plan du jour et à l'Affiche).
  Future<List<Film>> catalogue({Emotion? emotion, bool auHasard = true});
}

/// Réglages de connexion à Jellyfin (édition VJOD).
class ConnexionJellyfin {
  const ConnexionJellyfin({required this.adresse, required this.utilisateurId, required this.jeton});

  final String adresse;
  final String utilisateurId;
  final String jeton;

  bool get complete => adresse.isNotEmpty && utilisateurId.isNotEmpty && jeton.isNotEmpty;

  Uri url(String chemin, Map<String, String> params) {
    final base = adresse.endsWith('/') ? adresse.substring(0, adresse.length - 1) : adresse;
    return Uri.parse('$base$chemin').replace(queryParameters: params);
  }
}

/// La bibliothèque Jellyfin de l'édition VJOD. Le filtre « 3 étoiles » est
/// déjà demandé au serveur (MinCommunityRating=6), puis revérifié au tirage.
class SourceJellyfin implements SourceFilms {
  SourceJellyfin(this.connexion, {http.Client? client}) : _client = client ?? http.Client();

  final ConnexionJellyfin connexion;
  final http.Client _client;

  @override
  String get nom => 'ta bibliothèque Jellyfin';

  @override
  Future<List<Film>> catalogue({Emotion? emotion, bool auHasard = true}) async {
    final uri = connexion.url('/Users/${connexion.utilisateurId}/Items', {
      'IncludeItemTypes': 'Movie',
      'Recursive': 'true',
      'MinCommunityRating': '6',
      'SortBy': auHasard ? 'Random' : 'SortName',
      'Limit': auHasard ? '120' : '400',
      'Fields': 'Genres,ProductionLocations,People,ProductionYear,RunTimeTicks,CommunityRating,UserData,Overview,OriginalTitle',
      if (emotion != null) 'Genres': emotion.genres.join('|'),
    });
    final rep = await _client.get(uri, headers: {
      'X-Emby-Token': connexion.jeton,
      'Accept': 'application/json',
    });
    if (rep.statusCode == 401) {
      throw const ErreurSource('Jellyfin refuse la connexion : vérifie la clé d\'API dans les réglages.');
    }
    if (rep.statusCode != 200) {
      throw ErreurSource('Jellyfin a renvoyé une erreur (${rep.statusCode}). Réessaie dans un instant.');
    }
    final json = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
    final items = (json['Items'] as List? ?? const []).cast<Map<String, dynamic>>();
    return items.map(filmDepuisJellyfin).toList();
  }

  /// Si le film a été vu depuis [debut], renvoie le moment où il l'a été
  /// (ou maintenant si Jellyfin ne le précise pas) ; sinon null.
  Future<DateTime?> vuDepuis(String itemId, DateTime debut) async {
    final rep = await _client.get(connexion.url('/Users/${connexion.utilisateurId}/Items/$itemId', const {}), headers: {
      'X-Emby-Token': connexion.jeton,
      'Accept': 'application/json',
    });
    if (rep.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
    return dateDeVisionnage(j['UserData'] as Map<String, dynamic>?, debut);
  }

  /// Jellyfin marque un film « vu » quand il a été regardé presque jusqu'au
  /// bout. On ne compte que les visionnages qui suivent la carte jouée.
  static DateTime? dateDeVisionnage(Map<String, dynamic>? userData, DateTime debut) {
    if (userData == null) return null;
    final vu = (userData['Played'] as bool?) ?? false;
    final pourcentage = (userData['PlayedPercentage'] as num?)?.toDouble() ?? 0;
    if (!vu && pourcentage < 90) return null;
    final brut = userData['LastPlayedDate'] as String?;
    final derniere = brut == null ? null : DateTime.tryParse(brut)?.toLocal();
    if (derniere == null) return DateTime.now();
    if (derniere.isBefore(debut.subtract(const Duration(minutes: 5)))) return null;
    return derniere;
  }

  static Film filmDepuisJellyfin(Map<String, dynamic> j) {
    final ticks = j['RunTimeTicks'];
    final people = (j['People'] as List? ?? const []).cast<Map<String, dynamic>>();
    final realisateur = people.where((p) => p['Type'] == 'Director').map((p) => p['Name'] as String?).firstOrNull;
    final userData = j['UserData'] as Map<String, dynamic>?;
    return Film(
      id: j['Id'] as String,
      titre: (j['Name'] as String?) ?? 'Sans titre',
      annee: j['ProductionYear'] as int?,
      dureeMinutes: ticks is int ? ticks ~/ 600000000 : null,
      note: (j['CommunityRating'] as num?)?.toDouble(),
      genres: (j['Genres'] as List? ?? const []).cast<String>(),
      pays: (j['ProductionLocations'] as List? ?? const []).cast<String>(),
      realisateur: realisateur,
      synopsis: j['Overview'] as String?,
      autresTitres: [if (j['OriginalTitle'] is String && j['OriginalTitle'] != j['Name']) j['OriginalTitle'] as String],
      dejaVu: (userData?['Played'] as bool?) ?? false,
      serveurId: j['ServerId'] as String?,
      source: SourceFilm.jellyfin,
    );
  }
}

class ErreurSource implements Exception {
  const ErreurSource(this.message);
  final String message;
  @override
  String toString() => message;
}

/// La sélection de démonstration, pour jouer sans serveur : des films
/// reconnus, choisis dans les classements IMDb et SensCritique (notes IMDb
/// arrondies), avec des synopsis rédigés pour Aura.
class SourceDemo implements SourceFilms {
  @override
  String get nom => 'la sélection de démonstration';

  @override
  Future<List<Film>> catalogue({Emotion? emotion, bool auHasard = true}) async => _films;

  static const _films = <Film>[
    Film(id: 'd1', titre: 'Le Samouraï', annee: 1967, dureeMinutes: 105, note: 7.9, genres: ['Crime', 'Thriller'], pays: ['France'], realisateur: 'Jean-Pierre Melville', synopsis: 'Un tueur à gages solitaire et méthodique se retrouve traqué à la fois par la police et par ceux qui l\'ont engagé.', autresTitres: ['Le Samourai']),
    Film(id: 'd2', titre: 'La Isla Mínima', annee: 2014, dureeMinutes: 105, note: 7.2, genres: ['Thriller', 'Crime'], pays: ['Espagne'], realisateur: 'Alberto Rodríguez', synopsis: 'En 1980, deux policiers que tout oppose enquêtent sur la disparition de deux adolescentes dans les marais andalous.', autresTitres: ['Marshland']),
    Film(id: 'd3', titre: 'Les Diaboliques', annee: 1955, dureeMinutes: 117, note: 8.0, genres: ['Thriller', 'Mystery'], pays: ['France'], realisateur: 'Henri-Georges Clouzot', synopsis: 'L\'épouse et la maîtresse d\'un directeur d\'école tyrannique s\'allient pour le tuer, mais le corps disparaît.', autresTitres: ['Diabolique']),
    Film(id: 'd4', titre: 'Memories of Murder', annee: 2003, dureeMinutes: 132, note: 8.1, genres: ['Crime', 'Thriller'], pays: ['Corée du Sud'], realisateur: 'Bong Joon-ho', synopsis: 'En 1986, dans la campagne coréenne, deux inspecteurs aux méthodes opposées traquent l\'auteur d\'une série de meurtres.'),
    Film(id: 'd5', titre: 'Le Dîner de cons', annee: 1998, dureeMinutes: 80, note: 7.6, genres: ['Comedy'], pays: ['France'], realisateur: 'Francis Veber', synopsis: 'Un éditeur qui invite chaque semaine un « con » à dîner pour s\'en moquer voit sa soirée tourner au désastre à cause de son invité.', autresTitres: ['The Dinner Game']),
    Film(id: 'd6', titre: 'Le Voyage de Chihiro', annee: 2001, dureeMinutes: 125, note: 8.6, genres: ['Animation', 'Fantasy'], pays: ['Japon'], realisateur: 'Hayao Miyazaki', synopsis: 'Une fillette piégée dans un monde d\'esprits doit travailler dans des bains publics pour sauver ses parents changés en cochons.', autresTitres: ['Spirited Away']),
    Film(id: 'd7', titre: 'Intouchables', annee: 2011, dureeMinutes: 112, note: 8.5, genres: ['Comedy', 'Drama'], pays: ['France'], realisateur: 'Olivier Nakache, Éric Toledano', synopsis: 'Un riche aristocrate tétraplégique engage comme auxiliaire de vie un jeune homme de banlieue tout juste sorti de prison.', autresTitres: ['The Intouchables']),
    Film(id: 'd8', titre: 'Les Temps modernes', annee: 1936, dureeMinutes: 87, note: 8.5, genres: ['Comedy', 'Drama'], pays: ['États-Unis'], realisateur: 'Charlie Chaplin', synopsis: 'Un ouvrier broyé par le travail à la chaîne enchaîne les mésaventures et croise la route d\'une jeune orpheline.', autresTitres: ['Modern Times']),
    Film(id: 'd9', titre: 'Une séparation', annee: 2011, dureeMinutes: 123, note: 8.3, genres: ['Drama'], pays: ['Iran'], realisateur: 'Asghar Farhadi', synopsis: 'À Téhéran, un couple en instance de divorce se retrouve pris dans un conflit avec l\'aide-soignante engagée pour le père malade.', autresTitres: ['A Separation']),
    Film(id: 'd10', titre: 'Les Parapluies de Cherbourg', annee: 1964, dureeMinutes: 91, note: 7.8, genres: ['Drama', 'Romance'], pays: ['France'], realisateur: 'Jacques Demy', synopsis: 'Une jeune vendeuse de parapluies et un garagiste s\'aiment, mais la guerre d\'Algérie les sépare. Tout est chanté.', autresTitres: ['The Umbrellas of Cherbourg']),
    Film(id: 'd11', titre: 'Mad Max: Fury Road', annee: 2015, dureeMinutes: 120, note: 8.1, genres: ['Adventure', 'Science Fiction'], pays: ['Australie'], realisateur: 'George Miller', synopsis: 'Dans un désert post-apocalyptique, Max et l\'impératrice Furiosa fuient un tyran à bord d\'un camion de guerre.'),
    Film(id: 'd12', titre: 'Le Salaire de la peur', annee: 1953, dureeMinutes: 131, note: 8.1, genres: ['Adventure', 'Thriller'], pays: ['France'], realisateur: 'Henri-Georges Clouzot', synopsis: 'En Amérique du Sud, quatre hommes sans le sou acceptent de transporter de la nitroglycérine sur des routes défoncées.', autresTitres: ['The Wages of Fear']),
    Film(id: 'd13', titre: 'Persepolis', annee: 2007, dureeMinutes: 96, note: 8.0, genres: ['Animation', 'Drama'], pays: ['France'], realisateur: 'Marjane Satrapi, Vincent Paronnaud', synopsis: 'Une jeune Iranienne grandit pendant la révolution islamique puis la guerre, avant de partir vivre en Europe.'),
    Film(id: 'd14', titre: 'Rec', annee: 2007, dureeMinutes: 78, note: 7.4, genres: ['Horror'], pays: ['Espagne'], realisateur: 'Jaume Balagueró, Paco Plaza', synopsis: 'Une journaliste et son caméraman suivent des pompiers dans un immeuble de Barcelone soudain placé en quarantaine.'),
    Film(id: 'd15', titre: 'Le Parrain', annee: 1972, dureeMinutes: 175, note: 9.2, genres: ['Crime', 'Drama'], pays: ['États-Unis'], realisateur: 'Francis Ford Coppola', synopsis: 'Le chef vieillissant d\'une famille de la mafia new-yorkaise transmet son empire à son plus jeune fils, d\'abord réticent.', autresTitres: ['The Godfather']),
    Film(id: 'd16', titre: 'Les Évadés', annee: 1994, dureeMinutes: 142, note: 9.3, genres: ['Drama'], pays: ['États-Unis'], realisateur: 'Frank Darabont', synopsis: 'Condamné à tort pour le meurtre de sa femme, un banquier se lie d\'amitié avec un autre détenu au fil de longues années de prison.', autresTitres: ['The Shawshank Redemption']),
    Film(id: 'd17', titre: 'Le Bon, la Brute et le Truand', annee: 1966, dureeMinutes: 178, note: 8.8, genres: ['Western'], pays: ['Italie'], realisateur: 'Sergio Leone', synopsis: 'Pendant la guerre de Sécession, trois hommes sans scrupules se disputent un trésor enterré dans un cimetière.', autresTitres: ['The Good, the Bad and the Ugly']),
    Film(id: 'd18', titre: 'Parasite', annee: 2019, dureeMinutes: 132, note: 8.5, genres: ['Comedy', 'Thriller', 'Drama'], pays: ['Corée du Sud'], realisateur: 'Bong Joon-ho', synopsis: 'Une famille pauvre s\'infiltre, un membre après l\'autre, au service d\'une riche famille de Séoul.'),
    Film(id: 'd19', titre: 'Le Fabuleux Destin d\'Amélie Poulain', annee: 2001, dureeMinutes: 122, note: 8.3, genres: ['Comedy', 'Romance'], pays: ['France'], realisateur: 'Jean-Pierre Jeunet', synopsis: 'Une jeune serveuse de Montmartre décide de faire en secret le bonheur des gens qui l\'entourent.', autresTitres: ['Amélie']),
    Film(id: 'd20', titre: 'La Haine', annee: 1995, dureeMinutes: 98, note: 8.1, genres: ['Drama', 'Crime'], pays: ['France'], realisateur: 'Mathieu Kassovitz', synopsis: 'Au lendemain d\'une émeute, trois amis d\'une cité de banlieue errent pendant vingt-quatre heures entre la cité et Paris.'),
    Film(id: 'd21', titre: 'Alien, le huitième passager', annee: 1979, dureeMinutes: 117, note: 8.5, genres: ['Horror', 'Science Fiction'], pays: ['Royaume-Uni'], realisateur: 'Ridley Scott', synopsis: 'L\'équipage d\'un cargo spatial recueille à son bord une créature qui l\'élimine un membre après l\'autre.', autresTitres: ['Alien']),
    Film(id: 'd22', titre: 'Retour vers le futur', annee: 1985, dureeMinutes: 116, note: 8.5, genres: ['Adventure', 'Comedy', 'Science Fiction'], pays: ['États-Unis'], realisateur: 'Robert Zemeckis', synopsis: 'Un adolescent remonte accidentellement le temps jusqu\'en 1955 et doit s\'assurer que ses futurs parents tombent amoureux.', autresTitres: ['Back to the Future']),
    Film(id: 'd23', titre: 'Le Silence des agneaux', annee: 1991, dureeMinutes: 118, note: 8.6, genres: ['Crime', 'Thriller', 'Horror'], pays: ['États-Unis'], realisateur: 'Jonathan Demme', synopsis: 'Une jeune recrue du FBI sollicite l\'aide d\'un psychiatre cannibale pour arrêter un tueur en série.', autresTitres: ['The Silence of the Lambs']),
    Film(id: 'd24', titre: 'Mon voisin Totoro', annee: 1988, dureeMinutes: 86, note: 8.1, genres: ['Animation', 'Family', 'Fantasy'], pays: ['Japon'], realisateur: 'Hayao Miyazaki', synopsis: 'Deux sœurs installées à la campagne se lient d\'amitié avec les esprits de la forêt voisine.', autresTitres: ['My Neighbor Totoro']),
    Film(id: 'd25', titre: 'Les Quatre Cents Coups', annee: 1959, dureeMinutes: 99, note: 8.1, genres: ['Drama'], pays: ['France'], realisateur: 'François Truffaut', synopsis: 'Délaissé par ses parents et puni à l\'école, le jeune Antoine Doinel multiplie les fugues dans le Paris des années 1950.', autresTitres: ['The 400 Blows']),
    Film(id: 'd26', titre: 'La Grande Vadrouille', annee: 1966, dureeMinutes: 132, note: 7.9, genres: ['Comedy', 'War'], pays: ['France'], realisateur: 'Gérard Oury', synopsis: 'Sous l\'Occupation, un chef d\'orchestre et un peintre en bâtiment aident des aviateurs anglais à gagner la zone libre.', autresTitres: ['Don\'t Look Now... We\'re Being Shot At!']),
    Film(id: 'd27', titre: 'The Grand Budapest Hotel', annee: 2014, dureeMinutes: 100, note: 8.1, genres: ['Comedy', 'Adventure'], pays: ['États-Unis'], realisateur: 'Wes Anderson', synopsis: 'Le concierge d\'un grand hôtel d\'Europe centrale et son jeune groom se retrouvent mêlés au vol d\'un tableau de grande valeur.'),
    Film(id: 'd28', titre: 'Get Out', annee: 2017, dureeMinutes: 104, note: 7.8, genres: ['Horror', 'Mystery', 'Thriller'], pays: ['États-Unis'], realisateur: 'Jordan Peele', synopsis: 'Un jeune homme noir rend visite à la famille de sa petite amie blanche, et le week-end prend une tournure inquiétante.'),
    Film(id: 'd29', titre: 'Le Labyrinthe de Pan', annee: 2006, dureeMinutes: 118, note: 8.2, genres: ['Fantasy', 'Drama', 'War'], pays: ['Espagne'], realisateur: 'Guillermo del Toro', synopsis: 'En 1944, dans l\'Espagne franquiste, une fillette s\'invente un monde merveilleux et inquiétant pour échapper à la violence de son beau-père.', autresTitres: ['Pan\'s Labyrinth']),
    Film(id: 'd30', titre: 'Whiplash', annee: 2014, dureeMinutes: 106, note: 8.5, genres: ['Drama', 'Music'], pays: ['États-Unis'], realisateur: 'Damien Chazelle', synopsis: 'Un jeune batteur de jazz subit les méthodes impitoyables d\'un professeur prêt à tout pour faire de lui un grand musicien.'),
    Film(id: 'd31', titre: 'In the Mood for Love', annee: 2000, dureeMinutes: 98, note: 8.1, genres: ['Drama', 'Romance'], pays: ['Hong Kong'], realisateur: 'Wong Kar-wai', synopsis: 'Dans le Hong Kong des années 1960, deux voisins découvrent que leurs conjoints ont une liaison.'),
    Film(id: 'd32', titre: 'La Cité de Dieu', annee: 2002, dureeMinutes: 130, note: 8.6, genres: ['Crime', 'Drama'], pays: ['Brésil'], realisateur: 'Fernando Meirelles, Kátia Lund', synopsis: 'Dans une favela de Rio, un jeune photographe raconte l\'ascension des gangs qui règnent sur son quartier.', autresTitres: ['City of God']),
    Film(id: 'd33', titre: 'Coco', annee: 2017, dureeMinutes: 105, note: 8.4, genres: ['Animation', 'Family', 'Fantasy'], pays: ['États-Unis'], realisateur: 'Lee Unkrich', synopsis: 'Un jeune Mexicain passionné de musique se retrouve au pays des morts et part à la recherche de son arrière-arrière-grand-père.'),
    Film(id: 'd34', titre: 'Le Seigneur des anneaux : La Communauté de l\'anneau', annee: 2001, dureeMinutes: 178, note: 8.9, genres: ['Adventure', 'Fantasy'], pays: ['Nouvelle-Zélande'], realisateur: 'Peter Jackson', synopsis: 'Un jeune hobbit hérite d\'un anneau maléfique et part avec huit compagnons pour le détruire.', autresTitres: ['The Lord of the Rings: The Fellowship of the Ring']),
    Film(id: 'd35', titre: 'Psychose', annee: 1960, dureeMinutes: 109, note: 8.5, genres: ['Horror', 'Thriller'], pays: ['États-Unis'], realisateur: 'Alfred Hitchcock', synopsis: 'Après avoir volé une grosse somme d\'argent, une secrétaire s\'arrête dans un motel isolé tenu par un jeune homme étrange.', autresTitres: ['Psycho']),
    Film(id: 'd36', titre: 'Shining', annee: 1980, dureeMinutes: 146, note: 8.4, genres: ['Horror'], pays: ['Royaume-Uni'], realisateur: 'Stanley Kubrick', synopsis: 'Gardien d\'un hôtel isolé pendant l\'hiver, un écrivain sombre peu à peu dans la folie sous les yeux de sa femme et de son fils.', autresTitres: ['The Shining']),
    Film(id: 'd37', titre: 'Your Name', annee: 2016, dureeMinutes: 106, note: 8.4, genres: ['Animation', 'Romance', 'Fantasy'], pays: ['Japon'], realisateur: 'Makoto Shinkai', synopsis: 'Un lycéen de Tokyo et une lycéenne de la campagne se réveillent régulièrement dans le corps l\'un de l\'autre.'),
    Film(id: 'd38', titre: 'OSS 117 : Le Caire, nid d\'espions', annee: 2006, dureeMinutes: 99, note: 7.0, genres: ['Comedy'], pays: ['France'], realisateur: 'Michel Hazanavicius', synopsis: 'En 1955, un agent secret français aussi sûr de lui que maladroit enquête au Caire sur la disparition d\'un collègue.', autresTitres: ['OSS 117: Cairo, Nest of Spies']),
    Film(id: 'd39', titre: 'Le Cinquième Élément', annee: 1997, dureeMinutes: 126, note: 7.6, genres: ['Science Fiction', 'Adventure'], pays: ['France'], realisateur: 'Luc Besson', synopsis: 'Au XXIIIe siècle, un chauffeur de taxi doit protéger une mystérieuse jeune femme qui détient la clé du salut de la Terre.', autresTitres: ['The Fifth Element']),
    Film(id: 'd40', titre: '12 hommes en colère', annee: 1957, dureeMinutes: 96, note: 9.0, genres: ['Drama'], pays: ['États-Unis'], realisateur: 'Sidney Lumet', synopsis: 'Dans une salle de délibération, un juré tente de convaincre les onze autres que l\'accusé n\'est peut-être pas coupable.', autresTitres: ['12 Angry Men']),
    Film(id: 'd41', titre: 'Shoah', annee: 1985, dureeMinutes: 566, note: 8.6, genres: ['Documentary', 'History'], pays: ['France'], realisateur: 'Claude Lanzmann', synopsis: 'Neuf heures de témoignages de survivants, de témoins et d\'anciens bourreaux de l\'extermination des Juifs d\'Europe.'),
    Film(id: 'd42', titre: 'Le Goût des autres', annee: 2000, dureeMinutes: 112, note: 7.2, genres: ['Comedy', 'Drama', 'Romance'], pays: ['France'], realisateur: 'Agnès Jaoui', synopsis: 'Un chef d\'entreprise peu cultivé tombe amoureux d\'une comédienne et découvre, maladroitement, le théâtre et l\'art.', autresTitres: ['The Taste of Others']),
  ];
}
