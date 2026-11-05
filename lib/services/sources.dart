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
  String get nom => 'Ta bibliothèque Jellyfin';

  @override
  Future<List<Film>> catalogue({Emotion? emotion, bool auHasard = true}) async {
    final uri = connexion.url('/Users/${connexion.utilisateurId}/Items', {
      'IncludeItemTypes': 'Movie',
      'Recursive': 'true',
      'MinCommunityRating': '6',
      'SortBy': auHasard ? 'Random' : 'SortName',
      'Limit': auHasard ? '120' : '400',
      'Fields': 'Genres,ProductionLocations,People,ProductionYear,RunTimeTicks,CommunityRating,UserData,Overview',
      if (emotion != null) 'Genres': emotion.genres.join('|'),
    });
    final rep = await _client.get(uri, headers: {
      'X-Emby-Token': connexion.jeton,
      'Accept': 'application/json',
    });
    if (rep.statusCode == 401) {
      throw const ErreurSource('Jellyfin refuse la connexion : vérifie le jeton dans les réglages.');
    }
    if (rep.statusCode != 200) {
      throw ErreurSource('Jellyfin a répondu ${rep.statusCode}. Réessaie dans un instant.');
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

/// Un petit catalogue d'exemple, pour jouer sans serveur. Les notes sont
/// arrondies et servent seulement à la démonstration.
class SourceDemo implements SourceFilms {
  @override
  String get nom => 'Catalogue de démonstration';

  @override
  Future<List<Film>> catalogue({Emotion? emotion, bool auHasard = true}) async => _films;

  static const _films = <Film>[
    Film(id: 'd1', titre: 'Le Samouraï', annee: 1967, dureeMinutes: 105, note: 7.9, genres: ['Crime', 'Thriller'], pays: ['France'], realisateur: 'Jean-Pierre Melville', synopsis: 'Un tueur à gages solitaire et méthodique se retrouve traqué à la fois par la police et par ceux qui l\'ont engagé.'),
    Film(id: 'd2', titre: 'La Isla Mínima', annee: 2014, dureeMinutes: 105, note: 7.2, genres: ['Thriller', 'Crime'], pays: ['Espagne'], realisateur: 'Alberto Rodríguez', synopsis: 'En 1980, deux policiers que tout oppose enquêtent sur la disparition de deux adolescentes dans les marais andalous.'),
    Film(id: 'd3', titre: 'Les Diaboliques', annee: 1955, dureeMinutes: 117, note: 8.0, genres: ['Thriller', 'Mystery'], pays: ['France'], realisateur: 'Henri-Georges Clouzot', synopsis: 'L\'épouse et la maîtresse d\'un directeur d\'école tyrannique s\'allient pour le tuer, mais le corps disparaît.'),
    Film(id: 'd4', titre: 'Memories of Murder', annee: 2003, dureeMinutes: 132, note: 8.0, genres: ['Crime', 'Thriller'], pays: ['Corée du Sud'], realisateur: 'Bong Joon-ho', synopsis: 'En 1986, dans la campagne coréenne, deux inspecteurs aux méthodes opposées traquent l\'auteur d\'une série de meurtres.'),
    Film(id: 'd5', titre: 'Le Dîner de cons', annee: 1998, dureeMinutes: 80, note: 7.5, genres: ['Comedy'], pays: ['France'], realisateur: 'Francis Veber', synopsis: 'Un éditeur qui invite chaque semaine un « con » à dîner pour s\'en moquer voit sa soirée tourner au désastre à cause de son invité.'),
    Film(id: 'd6', titre: 'Le Voyage de Chihiro', annee: 2001, dureeMinutes: 125, note: 8.5, genres: ['Animation', 'Fantasy'], pays: ['Japon'], realisateur: 'Hayao Miyazaki', synopsis: 'Une fillette piégée dans un monde d\'esprits doit travailler dans des bains publics pour sauver ses parents changés en cochons.'),
    Film(id: 'd7', titre: 'Intouchables', annee: 2011, dureeMinutes: 112, note: 8.3, genres: ['Comedy', 'Drama'], pays: ['France'], realisateur: 'Olivier Nakache, Éric Toledano', synopsis: 'Un riche aristocrate tétraplégique engage comme auxiliaire de vie un jeune homme de banlieue tout juste sorti de prison.'),
    Film(id: 'd8', titre: 'Les Temps modernes', annee: 1936, dureeMinutes: 87, note: 8.3, genres: ['Comedy', 'Drama'], pays: ['États-Unis'], realisateur: 'Charlie Chaplin', synopsis: 'Un ouvrier broyé par le travail à la chaîne enchaîne les mésaventures et croise la route d\'une jeune orpheline.'),
    Film(id: 'd9', titre: 'Une séparation', annee: 2011, dureeMinutes: 123, note: 7.9, genres: ['Drama'], pays: ['Iran'], realisateur: 'Asghar Farhadi', synopsis: 'À Téhéran, un couple en instance de divorce se retrouve pris dans un conflit avec l\'aide-soignante engagée pour le père malade.'),
    Film(id: 'd10', titre: 'Les Parapluies de Cherbourg', annee: 1964, dureeMinutes: 91, note: 7.6, genres: ['Drama', 'Romance'], pays: ['France'], realisateur: 'Jacques Demy', synopsis: 'Une jeune vendeuse de parapluies et un garagiste s\'aiment, mais la guerre d\'Algérie les sépare. Tout est chanté.'),
    Film(id: 'd11', titre: 'Mad Max: Fury Road', annee: 2015, dureeMinutes: 120, note: 7.6, genres: ['Adventure', 'Science Fiction'], pays: ['Australie'], realisateur: 'George Miller', synopsis: 'Dans un désert post-apocalyptique, Max et l\'impératrice Furiosa fuient un tyran à bord d\'un camion de guerre.'),
    Film(id: 'd12', titre: 'Le Salaire de la peur', annee: 1953, dureeMinutes: 131, note: 8.0, genres: ['Adventure', 'Thriller'], pays: ['France'], realisateur: 'Henri-Georges Clouzot', synopsis: 'En Amérique du Sud, quatre hommes sans le sou acceptent de transporter de la nitroglycérine sur des routes défoncées.'),
    Film(id: 'd13', titre: 'Shoah', annee: 1985, dureeMinutes: 566, note: 8.6, genres: ['Documentary', 'History'], pays: ['France'], realisateur: 'Claude Lanzmann', synopsis: 'Neuf heures de témoignages de survivants, de témoins et d\'anciens bourreaux de l\'extermination des Juifs d\'Europe.'),
    Film(id: 'd14', titre: 'Persepolis', annee: 2007, dureeMinutes: 96, note: 7.8, genres: ['Animation', 'Drama'], pays: ['Iran', 'France'], realisateur: 'Marjane Satrapi, Vincent Paronnaud', synopsis: 'Une jeune Iranienne grandit pendant la révolution islamique puis la guerre, avant de partir vivre en Europe.'),
    Film(id: 'd15', titre: 'Rec', annee: 2007, dureeMinutes: 78, note: 7.0, genres: ['Horror'], pays: ['Espagne'], realisateur: 'Jaume Balagueró, Paco Plaza', synopsis: 'Une journaliste et son caméraman suivent des pompiers dans un immeuble de Barcelone soudain placé en quarantaine.'),
  ];
}
