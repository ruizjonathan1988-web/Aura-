import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/modeles.dart';
import 'sources.dart';

/// Tout le cinéma que VJOD sait trouver, au-delà du serveur : les films
/// reconnus de TMDB. VJOD décide ensuite, à l'ouverture de la fiche, s'il
/// les a en VOD chez le fournisseur IPTV ou s'il faut les demander (Seerr).
///
/// Zéro navet dès la requête : note 6/10 ou plus, et assez d'avis.
class SourceTmdb implements SourceFilms {
  SourceTmdb(this.cle, {http.Client? client, Random? hasard})
      : _client = client ?? http.Client(),
        _hasard = hasard ?? Random();

  final String cle;
  final http.Client _client;
  final Random _hasard;

  static const votesMinimum = 300;

  /// Les genres TMDB, sous les noms anglais que les envies connaissent.
  static const genres = <int, String>{
    28: 'Action',
    12: 'Adventure',
    16: 'Animation',
    35: 'Comedy',
    80: 'Crime',
    99: 'Documentary',
    18: 'Drama',
    10751: 'Family',
    14: 'Fantasy',
    36: 'History',
    27: 'Horror',
    10402: 'Music',
    9648: 'Mystery',
    10749: 'Romance',
    878: 'Science Fiction',
    53: 'Thriller',
    10752: 'War',
    37: 'Western',
  };

  static Iterable<int> _ids(List<String> noms) {
    final bas = noms.map((n) => n.toLowerCase()).toSet();
    return genres.entries.where((e) => bas.contains(e.value.toLowerCase())).map((e) => e.key);
  }

  @override
  String get nom => 'tout le cinéma de VJOD';

  /// Les paramètres de la recherche TMDB pour cette envie et cette durée.
  static Map<String, String> parametres({Emotion? emotion, Duree? duree, Epoque? epoque, required int page, bool classiques = false}) => {
        'language': 'fr-FR',
        'region': 'FR',
        'include_adult': 'false',
        'sort_by': classiques ? 'vote_average.desc' : 'popularity.desc',
        'vote_average.gte': '6',
        'vote_count.gte': '$votesMinimum',
        'with_runtime.gte': '40',
        if (duree != null && duree != Duree.soiree) 'with_runtime.lte': '${duree.minutesMax}',
        if (emotion != null) 'with_genres': _ids(emotion.genres).join('|'),
        if (emotion != null && emotion.exclus.isNotEmpty) 'without_genres': _ids(emotion.exclus).join(','),
        if (epoque?.depuis != null) 'primary_release_date.gte': '${epoque!.depuis}-01-01',
        if (epoque?.jusqua != null) 'primary_release_date.lte': '${epoque!.jusqua}-12-31',
        'page': '$page',
      };

  @override
  Future<List<Film>> catalogue({Emotion? emotion, Duree? duree, Epoque? epoque, bool auHasard = true}) async {
    if (cle.isEmpty) return const [];
    // Deux pages : des films populaires et des grands classiques. Sans hasard
    // (Plan du jour, Affiche), toujours les mêmes pages.
    // Une seule décennie : moins de films, donc des pages moins lointaines.
    final etroit = epoque != null && epoque != Epoque.toutes;
    final pages = [
      parametres(emotion: emotion, duree: duree, epoque: epoque, page: auHasard ? 1 + _hasard.nextInt(etroit ? 2 : 5) : 1),
      parametres(emotion: emotion, duree: duree, epoque: epoque, page: auHasard ? 1 + _hasard.nextInt(etroit ? 2 : 3) : 1, classiques: true),
    ];
    final films = <String, Film>{};
    for (final p in pages) {
      final rep = await _client.get(Uri.https('api.themoviedb.org', '/3/discover/movie', {'api_key': cle, ...p}));
      if (rep.statusCode != 200) continue;
      final json = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
      for (final r in (json['results'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        final f = filmDepuisTmdb(r);
        if (f != null) films[f.id] = f;
      }
    }
    return films.values.toList();
  }

  static Film? filmDepuisTmdb(Map<String, dynamic> r) {
    final id = r['id'];
    final titre = (r['title'] as String?)?.trim();
    if (id is! int || titre == null || titre.isEmpty) return null;
    final date = r['release_date'] as String? ?? '';
    final original = (r['original_title'] as String?)?.trim();
    final synopsis = (r['overview'] as String?)?.trim();
    return Film(
      id: 'tmdb:$id',
      titre: titre,
      annee: date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null,
      note: (r['vote_average'] as num?)?.toDouble(),
      nombreVotes: r['vote_count'] as int?,
      genres: [for (final g in (r['genre_ids'] as List? ?? const [])) if (genres[g] != null) genres[g]!],
      synopsis: synopsis == null || synopsis.isEmpty ? null : synopsis,
      autresTitres: [if (original != null && original.isNotEmpty && original != titre) original],
      tmdbId: id,
      source: SourceFilm.catalogueVjod,
    );
  }
}

/// L'édition VJOD complète : ta bibliothèque d'abord, puis tout le reste du
/// cinéma que VJOD peut lancer ou demander. Un film présent sur le serveur
/// n'apparaît qu'une fois, en version serveur (lecture directe, « vu »
/// détecté). Si TMDB ne répond pas, la bibliothèque suffit.
class SourceToutVjod implements SourceFilms {
  SourceToutVjod(this.serveur, this.reste);

  final SourceFilms serveur;
  final SourceFilms reste;

  @override
  String get nom => 'ta bibliothèque et tout le cinéma de VJOD';

  @override
  Future<List<Film>> catalogue({Emotion? emotion, Duree? duree, Epoque? epoque, bool auHasard = true}) async {
    final (chez, ailleurs) = await (
      serveur.catalogue(emotion: emotion, duree: duree, epoque: epoque, auHasard: auHasard),
      reste.catalogue(emotion: emotion, duree: duree, epoque: epoque, auHasard: auHasard).catchError((_) => <Film>[]),
    ).wait;
    final surLeServeur = {for (final f in chez) if (f.tmdbId != null) f.tmdbId!};
    return [...chez, ...ailleurs.where((f) => !surLeServeur.contains(f.tmdbId))];
  }
}
