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
      'Fields': 'Genres,ProductionLocations,People,ProductionYear,RunTimeTicks,CommunityRating,UserData',
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
    Film(id: 'd1', titre: 'Le Samouraï', annee: 1967, dureeMinutes: 105, note: 7.9, genres: ['Crime', 'Thriller'], pays: ['France'], realisateur: 'Jean-Pierre Melville'),
    Film(id: 'd2', titre: 'La Isla Mínima', annee: 2014, dureeMinutes: 105, note: 7.2, genres: ['Thriller', 'Crime'], pays: ['Espagne'], realisateur: 'Alberto Rodríguez'),
    Film(id: 'd3', titre: 'Les Diaboliques', annee: 1955, dureeMinutes: 117, note: 8.0, genres: ['Thriller', 'Mystery'], pays: ['France'], realisateur: 'Henri-Georges Clouzot'),
    Film(id: 'd4', titre: 'Memories of Murder', annee: 2003, dureeMinutes: 132, note: 8.0, genres: ['Crime', 'Thriller'], pays: ['Corée du Sud'], realisateur: 'Bong Joon-ho'),
    Film(id: 'd5', titre: 'Le Dîner de cons', annee: 1998, dureeMinutes: 80, note: 7.5, genres: ['Comedy'], pays: ['France'], realisateur: 'Francis Veber'),
    Film(id: 'd6', titre: 'Le Voyage de Chihiro', annee: 2001, dureeMinutes: 125, note: 8.5, genres: ['Animation', 'Fantasy'], pays: ['Japon'], realisateur: 'Hayao Miyazaki'),
    Film(id: 'd7', titre: 'Intouchables', annee: 2011, dureeMinutes: 112, note: 8.3, genres: ['Comedy', 'Drama'], pays: ['France'], realisateur: 'Olivier Nakache, Éric Toledano'),
    Film(id: 'd8', titre: 'Les Temps modernes', annee: 1936, dureeMinutes: 87, note: 8.3, genres: ['Comedy', 'Drama'], pays: ['États-Unis'], realisateur: 'Charlie Chaplin'),
    Film(id: 'd9', titre: 'Une séparation', annee: 2011, dureeMinutes: 123, note: 7.9, genres: ['Drama'], pays: ['Iran'], realisateur: 'Asghar Farhadi'),
    Film(id: 'd10', titre: 'Les Parapluies de Cherbourg', annee: 1964, dureeMinutes: 91, note: 7.6, genres: ['Drama', 'Romance'], pays: ['France'], realisateur: 'Jacques Demy'),
    Film(id: 'd11', titre: 'Mad Max: Fury Road', annee: 2015, dureeMinutes: 120, note: 7.6, genres: ['Adventure', 'Science Fiction'], pays: ['Australie'], realisateur: 'George Miller'),
    Film(id: 'd12', titre: 'Le Salaire de la peur', annee: 1953, dureeMinutes: 131, note: 8.0, genres: ['Adventure', 'Thriller'], pays: ['France'], realisateur: 'Henri-Georges Clouzot'),
    Film(id: 'd13', titre: 'Shoah', annee: 1985, dureeMinutes: 566, note: 8.6, genres: ['Documentary', 'History'], pays: ['France'], realisateur: 'Claude Lanzmann'),
    Film(id: 'd14', titre: 'Persepolis', annee: 2007, dureeMinutes: 96, note: 7.8, genres: ['Animation', 'Drama'], pays: ['Iran', 'France'], realisateur: 'Marjane Satrapi, Vincent Paronnaud'),
    Film(id: 'd15', titre: 'Rec', annee: 2007, dureeMinutes: 78, note: 7.0, genres: ['Horror'], pays: ['Espagne'], realisateur: 'Jaume Balagueró, Paco Plaza'),
  ];
}
