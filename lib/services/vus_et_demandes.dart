import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/modeles.dart';
import 'sources.dart';

/// R65 et R66 : Aura ne propose ni un film déjà vu, ni un film déjà demandé.
///
/// Les films vus sur Jellyfin sont reconnus partout, même quand ils viennent
/// de « tout le cinéma » (TMDB) : leur numéro TMDB suffit. Les films que le
/// joueur a demandés (Seerr, par le relais du serveur VJOD) ne sont pas tirés :
/// ils arrivent de toute façon, inutile d'en faire une carte.
class VusEtDemandes {
  VusEtDemandes(this.connexion, {http.Client? client}) : _client = client ?? http.Client();

  final ConnexionJellyfin connexion;
  final http.Client _client;

  /// Gardés ce temps-là : la liste bouge peu dans une soirée.
  static const garde = Duration(minutes: 10);

  ({DateTime le, Set<int> vus, Set<int> demandes})? _cache;

  /// Les numéros TMDB des films vus et des films demandés (vides si le
  /// serveur ne répond pas : le tirage continue comme avant).
  Future<({Set<int> vus, Set<int> demandes})> lire({DateTime? maintenant}) async {
    final now = maintenant ?? DateTime.now();
    final c = _cache;
    if (c != null && now.difference(c.le) < garde) return (vus: c.vus, demandes: c.demandes);
    final (vus, demandes) = await (_vus().catchError((_) => <int>{}), _demandes().catchError((_) => <int>{})).wait;
    _cache = (le: now, vus: vus, demandes: demandes);
    return (vus: vus, demandes: demandes);
  }

  Future<Set<int>> _vus() async {
    final rep = await _client.get(
      connexion.url('/Users/${connexion.utilisateurId}/Items', {
        'IncludeItemTypes': 'Movie',
        'Recursive': 'true',
        'IsPlayed': 'true',
        'Fields': 'ProviderIds',
        'EnableUserData': 'false',
        'EnableImages': 'false',
      }),
      headers: connexion.entetes,
    );
    if (rep.statusCode != 200) return {};
    final j = jsonDecode(utf8.decode(rep.bodyBytes));
    return numerosTmdbJellyfin(j);
  }

  Future<Set<int>> _demandes() async {
    final moi = await _seerr('/Moonfin/Seerr/Api/auth/me', const {});
    final id = moi is Map ? moi['id'] : null;
    if (id is! num) return {};
    final page = await _seerr('/Moonfin/Seerr/Api/request', {'take': '200', 'skip': '0', 'requestedBy': '${id.toInt()}'});
    return filmsDemandes(page);
  }

  Future<Object?> _seerr(String chemin, Map<String, String> params) async {
    final rep = await _client.get(connexion.url(chemin, params), headers: connexion.entetes);
    if (rep.statusCode != 200) return null;
    return deballerSeerr(jsonDecode(utf8.decode(rep.bodyBytes)));
  }

  /// Le relais de VJOD peut emballer la réponse de Seerr (« FileContents »
  /// en base64) : on la déballe.
  static Object? deballerSeerr(Object? j) {
    if (j is Map && j['FileContents'] is String) {
      try {
        return jsonDecode(utf8.decode(base64Decode(j['FileContents'] as String)));
      } catch (_) {
        return null;
      }
    }
    return j;
  }

  static Set<int> numerosTmdbJellyfin(Object? j) {
    final vus = <int>{};
    for (final it in (j is Map ? j['Items'] as List? ?? const [] : const [])) {
      if (it is! Map) continue;
      final n = int.tryParse('${(it['ProviderIds'] as Map?)?['Tmdb'] ?? ''}');
      if (n != null) vus.add(n);
    }
    return vus;
  }

  /// Les films (pas les séries) des demandes, sauf celles refusées.
  static Set<int> filmsDemandes(Object? page) => {
        for (final r in (page is Map ? page['results'] as List? ?? const [] : const []))
          if (r is Map && r['type'] == 'movie' && r['status'] != 3 && (r['media'] as Map?)?['tmdbId'] is num)
            ((r['media'] as Map)['tmdbId'] as num).toInt(),
      };

  /// Le catalogue sans les films demandés, et avec les films vus marqués.
  static List<Film> appliquer(List<Film> films, Set<int> vus, Set<int> demandes) => [
        for (final f in films)
          if (f.tmdbId == null || !demandes.contains(f.tmdbId))
            f.tmdbId != null && vus.contains(f.tmdbId) && !f.dejaVu ? f.vu() : f,
      ];
}

/// Une source qui applique [VusEtDemandes] à une autre.
class SourceSansVusNiDemandes implements SourceFilms {
  SourceSansVusNiDemandes(this.source, this.filtre);

  final SourceFilms source;
  final VusEtDemandes filtre;

  @override
  String get nom => source.nom;

  @override
  Future<List<Film>> catalogue({Emotion? emotion, Duree? duree, Epoque? epoque, bool auHasard = true}) async {
    final (films, connus) = await (
      source.catalogue(emotion: emotion, duree: duree, epoque: epoque, auHasard: auHasard),
      filtre.lire(),
    ).wait;
    return VusEtDemandes.appliquer(films, connus.vus, connus.demandes);
  }
}
