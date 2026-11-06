import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'ligues.dart';

/// Le Relais (R57) : six degrés du cinéma, joué pour de vrai, au tour par
/// tour dans la ligue. Un membre voit un film et passe le relais au
/// suivant, qui a 48 heures pour voir un film relié au précédent : même
/// acteur (+1), même réalisateur (+2), même compositeur (+3). Pop coupe
/// la chaîne si l'on passe deux fois de suite par la même personne. Le
/// plus long relais est le record de la ligue.

/// Une personne d'un film : « Actor:Tom Hanks », « Director:… », « Composer:… ».
typedef Personne = String;

class Lien {
  const Lien(this.nom, this.metier);
  final String nom;
  final String metier;

  int get points => Relais.points(metier);

  String get phrase => switch (metier) {
        'Director' => 'même réalisateur : $nom',
        'Composer' => 'même compositeur : $nom',
        _ => 'même acteur : $nom',
      };

  Map<String, dynamic> versJson() => {'nom': nom, 'metier': metier};
  static Lien? depuisJson(Object? j) => j is Map && j['nom'] is String ? Lien('${j['nom']}', '${j['metier'] ?? 'Actor'}') : null;
}

class Maillon {
  const Maillon({required this.joueur, required this.pseudo, required this.titre, this.annee, required this.personnes, this.lien, required this.quand});
  final String joueur;
  final String pseudo;
  final String titre;
  final int? annee;
  final List<Personne> personnes;
  final Lien? lien;
  final DateTime quand;

  Map<String, dynamic> versJson() => {
        'joueur': joueur,
        'pseudo': pseudo,
        'titre': titre,
        if (annee != null) 'annee': annee,
        'personnes': personnes,
        if (lien != null) 'lien': lien!.versJson(),
        'quand': quand.toUtc().toIso8601String(),
      };

  static Maillon? depuisJson(Object? j) {
    if (j is! Map || j['titre'] is! String) return null;
    return Maillon(
      joueur: '${j['joueur']}',
      pseudo: '${j['pseudo'] ?? '?'}',
      titre: j['titre'] as String,
      annee: (j['annee'] as num?)?.toInt(),
      personnes: [for (final p in (j['personnes'] as List? ?? const [])) '$p'],
      lien: Lien.depuisJson(j['lien']),
      quand: DateTime.tryParse('${j['quand']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class Chaine {
  const Chaine({required this.id, required this.maillons, this.porteur, this.echeance, this.cassee = false, this.points = 0});
  final String id;
  final List<Maillon> maillons;
  final String? porteur;
  final DateTime? echeance;
  final bool cassee;
  final int points;

  bool expiree(DateTime maintenant) => cassee || (echeance != null && maintenant.isAfter(echeance!));

  static Chaine? depuisJson(Map<String, dynamic> j) => Chaine(
        id: '${j['id']}',
        maillons: [
          for (final m in (j['maillons'] as List? ?? const []))
            if (Maillon.depuisJson(m) case final x?) x,
        ],
        porteur: j['porteur'] as String?,
        echeance: DateTime.tryParse('${j['echeance']}'),
        cassee: j['casse'] == true,
        points: (j['points'] as num?)?.toInt() ?? 0,
      );
}

abstract final class Relais {
  static const delai = Duration(hours: 48);
  static const audaceParMaillon = 2;

  static int points(String metier) => switch (metier) {
        'Director' => 2,
        'Composer' => 3,
        _ => 1,
      };

  /// Le meilleur lien entre deux films (le plus de points), en évitant la
  /// personne du lien précédent (Pop coupe sinon). Nul s'il n'y en a pas.
  static Lien? lien(List<Personne> avant, List<Personne> apres, {String? interdit}) {
    Lien? meilleur;
    final noms = {for (final p in avant) _nom(p): p};
    for (final p in apres) {
      final nom = _nom(p);
      if (nom == interdit || !noms.containsKey(nom)) continue;
      // Le métier qui compte : le plus rare des deux côtés.
      final metiers = {_metier(p), _metier(noms[nom]!)};
      final metier = metiers.contains('Composer') ? 'Composer' : (metiers.contains('Director') ? 'Director' : 'Actor');
      final l = Lien(nom, metier);
      if (meilleur == null || l.points > meilleur.points) meilleur = l;
    }
    return meilleur;
  }

  static String _nom(Personne p) => p.contains(':') ? p.substring(p.indexOf(':') + 1) : p;
  static String _metier(Personne p) => p.contains(':') ? p.substring(0, p.indexOf(':')) : 'Actor';

  /// Le membre suivant, dans l'ordre des identifiants.
  static String suivant(List<String> membres, String actuel) {
    final ids = [...membres]..sort();
    final i = ids.indexOf(actuel);
    return ids[(i + 1) % ids.length];
  }

  /// Le record de la ligue : le plus long relais.
  static int record(List<Chaine> chaines) => chaines.fold(0, (m, c) => c.maillons.length > m ? c.maillons.length : m);
}

/// Le Relais en ligue (migration 0009) et l'équipe des films (TMDB).
class ServiceRelais {
  ServiceRelais(this.ligues, {http.Client? client}) : _http = client ?? http.Client();
  final ServiceLigues ligues;
  final http.Client _http;

  SupabaseClient get _db => ligues.client;

  /// Acteurs (10 premiers), réalisateur et compositeur d'un film, d'après TMDB.
  Future<List<Personne>> personnes(String titre, int? annee) async {
    if (Config.tmdbCle.isEmpty) return const [];
    final r = await _http.get(Uri.https('api.themoviedb.org', '/3/search/movie', {
      'api_key': Config.tmdbCle,
      'query': titre,
      'language': 'fr-FR',
      if (annee != null) 'year': '$annee',
    }));
    if (r.statusCode != 200) return const [];
    final res = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['results'] as List? ?? const [];
    if (res.isEmpty) return const [];
    final id = (res.first as Map)['id'];
    final c = await _http.get(Uri.https('api.themoviedb.org', '/3/movie/$id/credits', {'api_key': Config.tmdbCle}));
    if (c.statusCode != 200) return const [];
    final j = jsonDecode(utf8.decode(c.bodyBytes)) as Map;
    return [
      for (final a in (j['cast'] as List? ?? const []).take(10)) 'Actor:${(a as Map)['name']}',
      for (final m in (j['crew'] as List? ?? const []))
        if ((m as Map)['job'] == 'Director') 'Director:${m['name']}' else if (m['job'] == 'Original Music Composer') 'Composer:${m['name']}',
    ];
  }

  Future<List<Chaine>> chaines(String ligueId) async {
    final rep = await _db.from('relais').select().eq('ligue_id', ligueId).order('cree_le', ascending: false).limit(30);
    return [
      for (final j in rep)
        if (Chaine.depuisJson(j) case final c?) c,
    ];
  }

  Future<void> lancer(String ligueId, Maillon premier, String porteur) async {
    await _db.from('relais').insert({
      'ligue_id': ligueId,
      'maillons': [premier.versJson()],
      'porteur': porteur,
      'echeance': DateTime.now().add(Relais.delai).toUtc().toIso8601String(),
    });
  }

  Future<void> passer(Chaine c, Maillon m, String porteur) async {
    await _db.from('relais').update({
      'maillons': [...c.maillons.map((x) => x.versJson()), m.versJson()],
      'porteur': porteur,
      'echeance': DateTime.now().add(Relais.delai).toUtc().toIso8601String(),
      'points': c.points + (m.lien?.points ?? 0),
      'maj': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', c.id);
  }

  Future<void> casser(Chaine c) async {
    await _db.from('relais').update({'casse': true}).eq('id', c.id);
  }
}
