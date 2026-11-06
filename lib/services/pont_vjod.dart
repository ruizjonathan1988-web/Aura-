import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/modeles.dart';
import 'sources.dart';

/// Le pont entre Aura et VJOD (R46). Les deux applis se parlent par le
/// serveur Jellyfin : Aura dépose son état dans les préférences d'affichage
/// de l'utilisateur (identifiant « aura », client « aura »), VJOD le lit et
/// y écrit en retour la carte jouée et la note donnée à la fin du film. Pas
/// de serveur en plus, rien à régler.
abstract final class PontVjod {
  static const prefsId = 'aura';
  static const client = 'aura';

  /// Ce qu'Aura écrit : son état, en JSON.
  static const cleEtat = 'etat';

  /// Ce que VJOD écrit : la carte jouée ({jour, index, quand}) et la note
  /// donnée à la fin du film ({film, note, quand}).
  static const cleJoue = 'joue';
  static const cleNote = 'note';

  /// Combien de soirs de cartes Aura publie d'avance.
  static const jours = 7;

  static String jourDe(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// L'envie du soir pour VJOD : une par jour, à tour de rôle.
  static Emotion envieDuJour(DateTime d) => Emotion.values[DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000 % Emotion.values.length];

  /// La graine du tirage d'un soir : le même tirage à chaque publication.
  static int graineDuJour(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static Map<String, dynamic> carteVersJson(CarteDefi c) => {
        'type': c.type.libelle,
        'defi': c.defi,
        'cases': c.cases,
        if (c.niveau != null) 'niveau': c.niveau,
        'film': {
          'id': c.film.id,
          'titre': c.film.titre,
          if (c.film.annee != null) 'annee': c.film.annee,
          if (c.film.dureeMinutes != null) 'duree': c.film.dureeMinutes,
          if (c.film.genres.isNotEmpty) 'genres': c.film.genres,
          if (c.film.pays.isNotEmpty) 'pays': c.film.pays,
          if (c.film.tmdbId != null) 'tmdb': c.film.tmdbId,
          'jellyfin': c.film.source == SourceFilm.jellyfin,
        },
      };

  /// Une carte relue depuis le JSON publié, pour la jouer quand VJOD le dit.
  static CarteDefi? carteDepuisJson(Object? j) {
    if (j is! Map) return null;
    final f = j['film'];
    if (f is! Map || f['id'] is! String || f['titre'] is! String) return null;
    final type = TypeCarte.values.where((t) => t.libelle == j['type']).firstOrNull ?? TypeCarte.envie;
    return CarteDefi(
      type: type,
      defi: (j['defi'] as String?) ?? '',
      indice: '',
      cases: (j['cases'] as num?)?.toInt() ?? 1,
      joker: '',
      bulleDePop: '',
      niveau: (j['niveau'] as num?)?.toInt(),
      film: Film(
        id: f['id'] as String,
        titre: f['titre'] as String,
        annee: (f['annee'] as num?)?.toInt(),
        dureeMinutes: (f['duree'] as num?)?.toInt(),
        genres: [for (final g in (f['genres'] as List? ?? const [])) '$g'],
        pays: [for (final p in (f['pays'] as List? ?? const [])) '$p'],
        tmdbId: (f['tmdb'] as num?)?.toInt(),
        source: f['jellyfin'] == true ? SourceFilm.jellyfin : SourceFilm.catalogueVjod,
      ),
    );
  }

  /// L'état publié pour VJOD.
  static Map<String, dynamic> etat({
    required DateTime maj,
    required int position,
    required int pop,
    int? niveau,
    String? pouvoir,
    bool charge = false,
    required Map<String, List<Map<String, dynamic>>> cartes,
    ({String filmId, String titre, int cases})? seance,
  }) =>
      {
        'v': 1,
        'maj': maj.toIso8601String(),
        'position': position,
        'pop': pop,
        if (niveau != null) 'niveau': niveau,
        if (pouvoir != null) 'pouvoir': pouvoir,
        'charge': charge,
        'cartes': cartes,
        if (seance != null) 'seance': {'film': seance.filmId, 'titre': seance.titre, 'cases': seance.cases},
      };

  static Map<String, dynamic>? _objet(String? t) {
    if (t == null || t.isEmpty) return null;
    try {
      final j = jsonDecode(t);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// La carte jouée dans VJOD : le soir, sa place dans la main, et quand.
  static ({String jour, int index, DateTime quand})? lireJoue(String? t) {
    final j = _objet(t);
    final jour = j?['jour'];
    final index = j?['index'];
    final quand = DateTime.tryParse('${j?['quand']}');
    if (jour is! String || index is! num || quand == null) return null;
    return (jour: jour, index: index.toInt(), quand: quand.toLocal());
  }

  /// La note donnée dans VJOD à la fin du film : de 1 à 5.
  static ({String filmId, int note, DateTime quand})? lireNote(String? t) {
    final j = _objet(t);
    final film = j?['film'];
    final note = j?['note'];
    final quand = DateTime.tryParse('${j?['quand']}');
    if (film is! String || note is! num || quand == null || note < 1 || note > 5) return null;
    return (filmId: film, note: note.toInt(), quand: quand.toLocal());
  }
}

/// Les appels au serveur Jellyfin pour le pont.
class ServicePontVjod {
  ServicePontVjod(this.connexion, {http.Client? client}) : _client = client ?? http.Client();

  final ConnexionJellyfin connexion;
  final http.Client _client;

  Uri get _uri => connexion.url('/DisplayPreferences/${PontVjod.prefsId}', {'userId': connexion.utilisateurId, 'client': PontVjod.client});

  /// Les préférences entières (pour les réécrire sans rien perdre), ou un
  /// objet neuf quand il n'y en a pas encore.
  Future<Map<String, dynamic>> lire() async {
    final rep = await _client.get(_uri, headers: connexion.entetes);
    if (rep.statusCode != 200) return {'Id': PontVjod.prefsId, 'Client': PontVjod.client, 'CustomPrefs': <String, String>{}};
    final j = jsonDecode(utf8.decode(rep.bodyBytes));
    return j is Map<String, dynamic> ? j : {'Id': PontVjod.prefsId, 'CustomPrefs': <String, String>{}};
  }

  static Map<String, String> prefsDe(Map<String, dynamic> tout) => {
        for (final e in ((tout['CustomPrefs'] as Map?) ?? const {}).entries)
          if (e.value != null) '${e.key}': '${e.value}',
      };

  /// Réécrit les préférences avec [prefs] à la place des anciennes.
  Future<bool> ecrire(Map<String, dynamic> tout, Map<String, String> prefs) async {
    final corps = {...tout, 'Id': PontVjod.prefsId, 'Client': PontVjod.client, 'CustomPrefs': prefs};
    final rep = await _client.post(_uri, headers: {...connexion.entetes, 'Content-Type': 'application/json'}, body: jsonEncode(corps));
    return rep.statusCode >= 200 && rep.statusCode < 300;
  }
}
