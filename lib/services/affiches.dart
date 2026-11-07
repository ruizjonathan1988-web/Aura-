import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/modeles.dart';
import 'config.dart';

/// Les vraies images des films (TMDB) : une image large du film (sinon
/// l'affiche), pour la carte révélée. Gardées en mémoire le temps de la
/// partie. Jamais pendant les tests, et rien si TMDB ne répond pas : la
/// carte garde alors son illustration.
abstract final class Affiches {
  static final Map<String, Future<String?>> _cache = {};

  static bool get _enTest {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  static Future<String?> fond(Film f) {
    if (_enTest || Config.tmdbCle.isEmpty) return Future.value(null);
    return _cache.putIfAbsent('${f.tmdbId ?? ''}|${f.titre}|${f.annee ?? ''}', () => _chercher(f));
  }

  static String? depuisJson(Map j) {
    final chemin = (j['backdrop_path'] ?? j['poster_path']) as String?;
    return chemin == null ? null : 'https://image.tmdb.org/t/p/w780$chemin';
  }

  static Future<String?> _chercher(Film f) async {
    try {
      if (f.tmdbId != null) {
        final r = await http.get(Uri.https('api.themoviedb.org', '/3/movie/${f.tmdbId}', {'api_key': Config.tmdbCle})).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) return depuisJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map);
      }
      final r = await http.get(Uri.https('api.themoviedb.org', '/3/search/movie', {
        'api_key': Config.tmdbCle,
        'query': f.titre,
        'language': 'fr-FR',
        if (f.annee != null) 'year': '${f.annee}',
      })).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final res = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['results'] as List? ?? const [];
      return res.isEmpty ? null : depuisJson(res.first as Map);
    } catch (_) {
      return null;
    }
  }
}
