import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/modeles.dart';

/// D'où viennent les films proposés par le jeu.
abstract class SourceFilms {
  String get nom;

  /// Les films de la source. Sans [emotion], tous les genres. [duree] aide les
  /// sources qui filtrent côté serveur (TMDB) ; les autres l'ignorent, le
  /// tirage refiltre de toute façon. [auHasard] à faux donne toujours le même
  /// ordre (utile au Plan du jour et à l'Affiche).
  Future<List<Film>> catalogue({Emotion? emotion, Duree? duree, bool auHasard = true});
}

/// Réglages de connexion à Jellyfin (édition VJOD).
class ConnexionJellyfin {
  const ConnexionJellyfin({required this.adresse, required this.utilisateurId, required this.jeton});

  final String adresse;
  final String utilisateurId;
  final String jeton;

  bool get complete => adresse.isNotEmpty && utilisateurId.isNotEmpty && jeton.isNotEmpty;

  /// Les en-têtes d'un appel authentifié. Les Jellyfin récents refusent un
  /// « X-Emby-Token » seul : ils veulent l'en-tête « Authorization » des
  /// clients officiels, comme celui qu'envoie VJOD. L'ancien reste à côté
  /// pour les serveurs plus vieux.
  Map<String, String> get entetes => {
        'Authorization': enteteAuthorization(jeton: jeton),
        'X-Emby-Token': jeton,
        'Accept': 'application/json',
      };

  /// L'en-tête « Authorization: MediaBrowser … » de Jellyfin.
  static String enteteAuthorization({String? jeton, String appareil = 'aura', String version = '0.3.0'}) =>
      'MediaBrowser Client="Aura", Device="Aura", DeviceId="$appareil", Version="$version"'
      '${jeton == null || jeton.isEmpty ? '' : ', Token="$jeton"'}';

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
  Future<List<Film>> catalogue({Emotion? emotion, Duree? duree, bool auHasard = true}) async {
    final uri = connexion.url('/Users/${connexion.utilisateurId}/Items', {
      'IncludeItemTypes': 'Movie',
      'Recursive': 'true',
      'MinCommunityRating': '6',
      'SortBy': auHasard ? 'Random' : 'SortName',
      'Limit': auHasard ? '120' : '400',
      'Fields': 'Genres,ProductionLocations,People,ProductionYear,RunTimeTicks,CommunityRating,UserData,Overview,OriginalTitle,ProviderIds',
      if (emotion != null) 'Genres': emotion.genres.join('|'),
    });
    final rep = await _client.get(uri, headers: connexion.entetes);
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
    final rep = await _client.get(connexion.url('/Users/${connexion.utilisateurId}/Items/$itemId', const {}), headers: connexion.entetes);
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
      tmdbId: int.tryParse('${(j['ProviderIds'] as Map?)?['Tmdb'] ?? ''}'),
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
  Future<List<Film>> catalogue({Emotion? emotion, Duree? duree, bool auHasard = true}) async => _films;

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
    Film(id: 'd43', titre: 'Duel', annee: 1971, dureeMinutes: 89, note: 7.6, genres: ['Thriller'], pays: ['États-Unis'], realisateur: 'Steven Spielberg', synopsis: 'Sur une route déserte de Californie, un représentant de commerce est pris en chasse par le chauffeur invisible d\'un camion-citerne.'),
    Film(id: 'd44', titre: 'Cube', annee: 1997, dureeMinutes: 90, note: 7.2, genres: ['Horror', 'Science Fiction', 'Mystery'], pays: ['Canada'], realisateur: 'Vincenzo Natali', synopsis: 'Six inconnus se réveillent dans un dédale de salles cubiques piégées, sans savoir qui les y a enfermés ni pourquoi.'),
    Film(id: 'd45', titre: 'Cours, Lola, cours', annee: 1998, dureeMinutes: 81, note: 7.6, genres: ['Thriller', 'Crime'], pays: ['Allemagne'], realisateur: 'Tom Tykwer', synopsis: 'Lola a vingt minutes pour trouver 100 000 marks et sauver son petit ami, et l\'histoire recommence trois fois.', autresTitres: ['Run Lola Run', 'Lola rennt']),
    Film(id: 'd46', titre: 'Les Yeux sans visage', annee: 1960, dureeMinutes: 90, note: 7.6, genres: ['Horror', 'Drama'], pays: ['France'], realisateur: 'Georges Franju', synopsis: 'Un chirurgien enlève des jeunes femmes pour rendre un visage à sa fille, défigurée dans un accident.', autresTitres: ['Eyes Without a Face']),
    Film(id: 'd47', titre: 'Y a-t-il un pilote dans l\'avion ?', annee: 1980, dureeMinutes: 88, note: 7.7, genres: ['Comedy'], pays: ['États-Unis'], realisateur: 'Jim Abrahams, David et Jerry Zucker', synopsis: 'L\'équipage d\'un avion de ligne tombe malade, et un ancien pilote traumatisé doit reprendre les commandes sous une avalanche de gags.', autresTitres: ['Airplane!']),
    Film(id: 'd48', titre: 'Le père Noël est une ordure', annee: 1982, dureeMinutes: 87, note: 7.3, genres: ['Comedy'], pays: ['France'], realisateur: 'Jean-Marie Poiré', synopsis: 'Le soir de Noël, les bénévoles d\'une permanence téléphonique pour personnes en détresse voient défiler les pires visiteurs.', autresTitres: ['Santa Claus Is a Stinker']),
    Film(id: 'd49', titre: 'Toy Story', annee: 1995, dureeMinutes: 81, note: 8.3, genres: ['Animation', 'Comedy', 'Family'], pays: ['États-Unis'], realisateur: 'John Lasseter', synopsis: 'Woody, le cow-boy préféré d\'un petit garçon, voit sa place menacée par un astronaute en plastique très sûr de lui.'),
    Film(id: 'd50', titre: 'Le Grand Blond avec une chaussure noire', annee: 1972, dureeMinutes: 90, note: 7.0, genres: ['Comedy'], pays: ['France'], realisateur: 'Yves Robert', synopsis: 'Pris pour un espion, un violoniste distrait se retrouve au cœur d\'une guerre entre services secrets sans rien y comprendre.', autresTitres: ['The Tall Blond Man with One Black Shoe']),
    Film(id: 'd51', titre: 'Docteur Folamour', annee: 1964, dureeMinutes: 95, note: 8.4, genres: ['Comedy', 'War'], pays: ['Royaume-Uni'], realisateur: 'Stanley Kubrick', synopsis: 'Un général paranoïaque lance une attaque nucléaire contre l\'URSS, et la salle de guerre du Pentagone tente d\'éviter la fin du monde.', autresTitres: ['Dr. Strangelove']),
    Film(id: 'd52', titre: 'Le Tombeau des lucioles', annee: 1988, dureeMinutes: 89, note: 8.5, genres: ['Animation', 'Drama', 'War'], pays: ['Japon'], realisateur: 'Isao Takahata', synopsis: 'En 1945, un adolescent et sa petite sœur tentent de survivre seuls après le bombardement de Kobe.', autresTitres: ['Grave of the Fireflies']),
    Film(id: 'd53', titre: 'Brève Rencontre', annee: 1945, dureeMinutes: 86, note: 8.0, genres: ['Drama', 'Romance'], pays: ['Royaume-Uni'], realisateur: 'David Lean', synopsis: 'Au buffet d\'une gare de province, une mère de famille et un médecin, mariés chacun de leur côté, tombent amoureux semaine après semaine.', autresTitres: ['Brief Encounter']),
    Film(id: 'd54', titre: 'Cléo de 5 à 7', annee: 1962, dureeMinutes: 90, note: 7.8, genres: ['Drama'], pays: ['France'], realisateur: 'Agnès Varda', synopsis: 'Une jeune chanteuse erre dans Paris pendant deux heures, en attendant le résultat d\'un examen médical qui l\'angoisse.', autresTitres: ['Cleo from 5 to 7']),
    Film(id: 'd55', titre: 'Ma vie de Courgette', annee: 2016, dureeMinutes: 66, note: 7.7, genres: ['Animation', 'Drama'], pays: ['Suisse'], realisateur: 'Claude Barras', synopsis: 'Après la mort de sa mère, un garçon de neuf ans surnommé Courgette arrive dans un foyer et s\'y fait des amis.', autresTitres: ['My Life as a Zucchini']),
    Film(id: 'd56', titre: 'Le Roi lion', annee: 1994, dureeMinutes: 88, note: 8.5, genres: ['Animation', 'Adventure', 'Family'], pays: ['États-Unis'], realisateur: 'Roger Allers, Rob Minkoff', synopsis: 'Chassé par l\'oncle qui a tué son père, le jeune lion Simba grandit en exil avant de revenir réclamer sa place.', autresTitres: ['The Lion King']),
    Film(id: 'd57', titre: 'Fantastic Mr. Fox', annee: 2009, dureeMinutes: 87, note: 7.9, genres: ['Animation', 'Adventure', 'Comedy'], pays: ['États-Unis'], realisateur: 'Wes Anderson', synopsis: 'Un renard rangé retombe dans le vol de poules et déclenche une guerre avec trois fermiers redoutables.'),
    Film(id: 'd58', titre: 'Kirikou et la Sorcière', annee: 1998, dureeMinutes: 74, note: 7.4, genres: ['Animation', 'Adventure', 'Family'], pays: ['France'], realisateur: 'Michel Ocelot', synopsis: 'Dans un village d\'Afrique, un tout petit garçon tient tête à la sorcière Karaba, qui a asséché la source et fait disparaître les hommes.', autresTitres: ['Kirikou and the Sorceress']),
    Film(id: 'd59', titre: 'Les Triplettes de Belleville', annee: 2003, dureeMinutes: 80, note: 7.7, genres: ['Animation', 'Adventure', 'Comedy'], pays: ['France'], realisateur: 'Sylvain Chomet', synopsis: 'Une grand-mère et son chien traversent l\'océan pour sauver son petit-fils cycliste, enlevé pendant le Tour de France.', autresTitres: ['The Triplets of Belleville']),
    Film(id: 'd60', titre: 'Les Glaneurs et la Glaneuse', annee: 2000, dureeMinutes: 82, note: 7.7, genres: ['Documentary'], pays: ['France'], realisateur: 'Agnès Varda', synopsis: 'Caméra à la main, Agnès Varda part à la rencontre de ceux qui ramassent ce que les autres jettent, aux champs comme en ville.', autresTitres: ['The Gleaners and I']),
    Film(id: 'd61', titre: 'Microcosmos : Le Peuple de l\'herbe', annee: 1996, dureeMinutes: 80, note: 7.3, genres: ['Documentary'], pays: ['France'], realisateur: 'Claude Nuridsany, Marie Pérennou', synopsis: 'Une journée dans une prairie à hauteur d\'insecte : combats de scarabées, éclosions, et gouttes de pluie qui tombent comme des bombes.', autresTitres: ['Microcosmos']),
    Film(id: 'd62', titre: 'Valse avec Bachir', annee: 2008, dureeMinutes: 90, note: 8.0, genres: ['Animation', 'Documentary', 'War'], pays: ['Israël'], realisateur: 'Ari Folman', synopsis: 'Un ancien soldat israélien interroge ses camarades pour retrouver le souvenir perdu de la guerre du Liban de 1982.', autresTitres: ['Waltz with Bashir']),
    Film(id: 'd63', titre: 'Les Sentiers de la gloire', annee: 1957, dureeMinutes: 88, note: 8.4, genres: ['Drama', 'War'], pays: ['États-Unis'], realisateur: 'Stanley Kubrick', synopsis: 'En 1916, un colonel français défend devant un tribunal militaire trois soldats accusés de lâcheté après une attaque impossible.', autresTitres: ['Paths of Glory']),
    Film(id: 'd64', titre: 'Le Peuple migrateur', annee: 2001, dureeMinutes: 98, note: 7.8, genres: ['Documentary'], pays: ['France'], realisateur: 'Jacques Perrin', synopsis: 'Au plus près des oiseaux, le film suit leurs grandes migrations au-dessus des océans, des déserts et des villes.', autresTitres: ['Winged Migration']),
    Film(id: 'd65', titre: 'Être et avoir', annee: 2002, dureeMinutes: 104, note: 7.4, genres: ['Documentary'], pays: ['France'], realisateur: 'Nicolas Philibert', synopsis: 'Une année dans la classe unique d\'une école de campagne d\'Auvergne, auprès d\'un instituteur et de ses élèves de 4 à 11 ans.', autresTitres: ['To Be and to Have']),
  ];
}
