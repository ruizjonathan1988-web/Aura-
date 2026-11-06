import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/modeles.dart';
import 'sources.dart';

/// L'adresse et la clé de Ma TV, le serveur d'IPTV Checker sur la seedbox.
/// IPTV Checker les écrit dans la description de la collection Jellyfin
/// « VJOD – TV » (marqueur `VJOD-TV:` suivi d'un JSON en base64), là où VJOD
/// les lit aussi.
class ServeurMaTv {
  const ServeurMaTv({required this.adresse, required this.cle});

  final String adresse;
  final String cle;

  static ServeurMaTv? depuisJson(Object? json) {
    if (json is! Map) return null;
    var adresse = (json['url']?.toString() ?? '').trim();
    while (adresse.endsWith('/')) {
      adresse = adresse.substring(0, adresse.length - 1);
    }
    final cle = (json['key']?.toString() ?? '').trim();
    final uri = Uri.tryParse(adresse);
    if (uri == null || uri.host.isEmpty || !(uri.isScheme('http') || uri.isScheme('https')) || cle.isEmpty) return null;
    return ServeurMaTv(adresse: adresse, cle: cle);
  }

  /// Le serveur caché dans la description d'une collection, ou nul.
  static ServeurMaTv? depuisDescription(String? description) {
    final m = RegExp(r'VJOD-TV:([A-Za-z0-9_\-+/=]+)').firstMatch(description ?? '');
    if (m == null) return null;
    try {
      final brut = m.group(1)!.replaceAll('+', '-').replaceAll('/', '_');
      return depuisJson(jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(brut)))));
    } catch (_) {
      return null;
    }
  }

  ServeurMaTv avecCle(String autre) => ServeurMaTv(adresse: adresse, cle: autre);

  Uri point(String chemin, [Map<String, String> params = const {}]) =>
      Uri.parse('$adresse$chemin').replace(queryParameters: {...params, 'k': cle});
}

/// Demande à Ma TV si les films hors serveur sont en VOD chez le fournisseur
/// IPTV, comme le fait VJOD : par identifiant TMDB, 150 à la fois. Ma TV ne
/// répond pas, la seedbox dort, la collection n'existe pas : on ne sait
/// rien, et les cartes restent « en VOD ou à demander ». Jamais d'erreur.
class MaTv {
  MaTv(this.connexion, {http.Client? client, this.delai = const Duration(seconds: 8)}) : _client = client ?? http.Client();

  final ConnexionJellyfin connexion;
  final Duration delai;
  final http.Client _client;

  static const parLot = 150;

  Future<ServeurMaTv?>? _serveur;
  final _reponses = <int, bool>{};

  /// L'adresse de Ma TV, lue une fois dans Jellyfin. Avec Ma TV 3.60, la clé
  /// commune ne sert qu'à demander la clé du profil, que Ma TV fait vérifier
  /// à Jellyfin ; un Ma TV plus ancien répond 404 et la clé commune suffit.
  Future<ServeurMaTv?> serveur() => _serveur ??= _chercher().then((s) {
        if (s == null) _serveur = null; // On réessaiera au prochain tirage.
        return s;
      });

  Future<ServeurMaTv?> _chercher() async {
    try {
      final rep = await _client
          .get(
            connexion.url('/Users/${connexion.utilisateurId}/Items', {
              'IncludeItemTypes': 'BoxSet',
              'Recursive': 'true',
              'SearchTerm': 'VJOD',
              'Fields': 'Overview',
              'Limit': '20',
            }),
            headers: connexion.entetes,
          )
          .timeout(delai);
      if (rep.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(rep.bodyBytes));
      final items = json is Map ? json['Items'] : null;
      if (items is! List) return null;
      for (final item in items) {
        if (item is! Map) continue;
        final commun = ServeurMaTv.depuisDescription(item['Overview']?.toString());
        if (commun != null) return await _clePerso(commun);
      }
    } catch (_) {}
    return null;
  }

  Future<ServeurMaTv?> _clePerso(ServeurMaTv commun) async {
    try {
      final rep = await _client
          .post(commun.point('/tv/api/enroll'), headers: const {'Content-Type': 'application/json'}, body: jsonEncode({'token': connexion.jeton}))
          .timeout(delai);
      if (rep.statusCode == 200) {
        final j = jsonDecode(utf8.decode(rep.bodyBytes));
        final cle = j is Map ? (j['key']?.toString() ?? '') : '';
        if (cle.isNotEmpty) return commun.avecCle(cle);
      }
      // L'administrateur a coupé l'accès de ce profil à Ma TV.
      if (rep.statusCode == 403) return null;
    } catch (_) {}
    return commun;
  }

  /// Pour chaque identifiant TMDB auquel Ma TV a répondu : en VOD ou non.
  Future<Map<int, bool>> statuts(Iterable<int> ids) async {
    final aDemander = ids.where((id) => !_reponses.containsKey(id)).toSet().toList();
    if (aDemander.isNotEmpty) {
      final s = await serveur();
      if (s != null) {
        for (var i = 0; i < aDemander.length; i += parLot) {
          final lot = aDemander.sublist(i, i + parLot > aDemander.length ? aDemander.length : i + parLot);
          try {
            final rep = await _client.get(s.point('/tv/api/vod/tmdb', {'kind': 'movie', 'ids': lot.join(',')})).timeout(delai);
            if (rep.statusCode != 200) continue;
            final json = jsonDecode(utf8.decode(rep.bodyBytes));
            if (json is! Map) continue;
            for (final id in lot) {
              final copies = json['$id'];
              _reponses[id] = copies is List && copies.isNotEmpty;
            }
          } catch (_) {
            // Ce lot reste inconnu ; on redemandera.
          }
        }
      }
    }
    return {for (final id in ids) if (_reponses.containsKey(id)) id: _reponses[id]!};
  }

  /// Les films hors serveur, marqués « en VOD » ou « à demander ».
  Future<List<Film>> marquer(List<Film> films) async {
    final ids = [for (final f in films) if (f.source == SourceFilm.catalogueVjod && f.tmdbId != null) f.tmdbId!];
    if (ids.isEmpty) return films;
    final connus = await statuts(ids);
    return [
      for (final f in films)
        if (f.source == SourceFilm.catalogueVjod && connus[f.tmdbId] != null) f.avecVod(connus[f.tmdbId]!) else f,
    ];
  }
}

/// Le reste du cinéma (TMDB), avec la réponse de Ma TV sur chaque film.
class SourceAvecMaTv implements SourceFilms {
  SourceAvecMaTv(this.base, this.maTv);

  final SourceFilms base;
  final MaTv maTv;

  @override
  String get nom => base.nom;

  @override
  Future<List<Film>> catalogue({Emotion? emotion, Duree? duree, bool auHasard = true}) async =>
      maTv.marquer(await base.catalogue(emotion: emotion, duree: duree, auHasard: auHasard));
}
