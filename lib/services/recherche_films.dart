import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/modeles.dart';
import 'source_tmdb.dart';
import 'sources.dart';

/// R67 : chercher le film qu'on veut proposer, au lieu de prendre l'une des
/// idées d'Aura. La bibliothèque d'abord (lecture directe), puis tout le
/// cinéma (TMDB), sans doublon.
class RechercheFilms {
  RechercheFilms({this.connexion, this.cleTmdb = '', http.Client? client}) : _client = client ?? http.Client();

  final ConnexionJellyfin? connexion;
  final String cleTmdb;
  final http.Client _client;

  static const maximum = 12;

  /// Assez de lettres pour chercher.
  static String? aChercher(String texte) {
    final t = texte.trim();
    return t.length < 2 ? null : t;
  }

  Future<List<Film>> chercher(String texte) async {
    final q = aChercher(texte);
    if (q == null) return const [];
    final (chez, ailleurs) = await (
      _serveur(q).catchError((_) => <Film>[]),
      _tmdb(q).catchError((_) => <Film>[]),
    ).wait;
    return fusionner(chez, ailleurs);
  }

  static List<Film> fusionner(List<Film> chez, List<Film> ailleurs) {
    final surLeServeur = {for (final f in chez) if (f.tmdbId != null) f.tmdbId!};
    return [
      ...chez,
      for (final f in ailleurs)
        if (f.tmdbId == null || !surLeServeur.contains(f.tmdbId)) f,
    ].take(maximum).toList();
  }

  Future<List<Film>> _serveur(String q) async {
    final c = connexion;
    if (c == null || !c.complete) return const [];
    final rep = await _client.get(
      c.url('/Users/${c.utilisateurId}/Items', {
        'SearchTerm': q,
        'IncludeItemTypes': 'Movie',
        'Recursive': 'true',
        'Limit': '8',
        'Fields': 'Genres,ProductionLocations,People,ProductionYear,RunTimeTicks,CommunityRating,UserData,Overview,OriginalTitle,ProviderIds',
      }),
      headers: c.entetes,
    );
    if (rep.statusCode != 200) return const [];
    final j = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
    return [for (final it in (j['Items'] as List? ?? const []).cast<Map<String, dynamic>>()) SourceJellyfin.filmDepuisJellyfin(it)];
  }

  Future<List<Film>> _tmdb(String q) async {
    if (cleTmdb.isEmpty) return const [];
    final rep = await _client.get(Uri.https('api.themoviedb.org', '/3/search/movie', {
      'api_key': cleTmdb,
      'query': q,
      'language': 'fr-FR',
      'include_adult': 'false',
    }));
    if (rep.statusCode != 200) return const [];
    final j = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final r in (j['results'] as List? ?? const []).cast<Map<String, dynamic>>())
        if (SourceTmdb.filmDepuisTmdb(r) case final f?) f,
    ];
  }
}
