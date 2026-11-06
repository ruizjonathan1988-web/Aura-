import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/modeles.dart';

/// Où voir un film en France : abonnements, location, achat. Données
/// JustWatch, fournies par l'API TMDB (mention obligatoire à l'écran).
class Plateformes {
  const Plateformes({this.abonnement = const [], this.location = const [], this.achat = const [], this.gratuit = const [], this.lien});

  final List<String> abonnement;
  final List<String> location;
  final List<String> achat;
  final List<String> gratuit;

  /// La page TMDB « Où regarder » du film.
  final String? lien;

  bool get vide => abonnement.isEmpty && location.isEmpty && achat.isEmpty && gratuit.isEmpty;

  /// Lit la réponse de /movie/{id}/watch/providers pour un pays.
  static Plateformes depuisJson(Map<String, dynamic> j, {String pays = 'FR'}) {
    final p = (j['results'] as Map?)?[pays] as Map?;
    if (p == null) return const Plateformes();
    List<String> noms(String cle) => [
          for (final x in (p[cle] as List? ?? const []))
            if ((x as Map)['provider_name'] is String) x['provider_name'] as String,
        ];
    return Plateformes(
      abonnement: noms('flatrate'),
      gratuit: [...noms('free'), ...noms('ads')],
      location: noms('rent'),
      achat: noms('buy'),
      lien: p['link'] as String?,
    );
  }

  /// « En abonnement : Netflix, Canal+ · En location : Apple TV »
  String get resume => [
        if (abonnement.isNotEmpty) 'En abonnement : ${abonnement.take(4).join(', ')}',
        if (gratuit.isNotEmpty) 'Gratuit : ${gratuit.take(3).join(', ')}',
        if (location.isNotEmpty) 'En location : ${location.take(3).join(', ')}',
        if (abonnement.isEmpty && location.isEmpty && achat.isNotEmpty) 'À l\'achat : ${achat.take(3).join(', ')}',
      ].join(' · ');
}

class ServicePlateformes {
  ServicePlateformes(this.cle, {http.Client? client}) : _client = client ?? http.Client();

  final String cle;
  final http.Client _client;
  final _cache = <String, Plateformes?>{};

  static const mention = 'Données JustWatch, via TMDB. Ce produit utilise l\'API TMDB sans être approuvé ni certifié par TMDB.';

  Uri _url(String chemin, [Map<String, String> params = const {}]) =>
      Uri.https('api.themoviedb.org', '/3$chemin', {'api_key': cle, ...params});

  /// L'identifiant TMDB du film : celui de la source, sinon une recherche
  /// par titre (puis titre original) et année.
  Future<int?> idTmdb(Film f) async {
    if (f.tmdbId != null) return f.tmdbId;
    for (final titre in [f.titre, ...f.autresTitres]) {
      final rep = await _client.get(_url('/search/movie', {
        'query': titre,
        'language': 'fr-FR',
        if (f.annee != null) 'year': '${f.annee}',
      }));
      if (rep.statusCode != 200) return null;
      final resultats = (jsonDecode(utf8.decode(rep.bodyBytes))['results'] as List?) ?? const [];
      if (resultats.isNotEmpty) return ((resultats.first as Map)['id'] as num).toInt();
    }
    return null;
  }

  /// Où voir ce film en France (null si TMDB ne répond pas ou ne le connaît pas).
  Future<Plateformes?> pour(Film f) async {
    final cleCache = '${f.titre}|${f.annee}';
    if (_cache.containsKey(cleCache)) return _cache[cleCache];
    try {
      final id = await idTmdb(f);
      if (id == null) return _cache[cleCache] = null;
      final rep = await _client.get(_url('/movie/$id/watch/providers'));
      if (rep.statusCode != 200) return null;
      return _cache[cleCache] = Plateformes.depuisJson(jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
