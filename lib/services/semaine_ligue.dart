import 'dart:math';

/// Un geste d'un joueur pendant la semaine de ligue (voir la migration 0005).
class Geste {
  const Geste({required this.joueurId, required this.type, required this.valeur, required this.quand});

  final String joueurId;
  final String type;
  final Map<String, dynamic> valeur;
  final DateTime quand;

  static Geste depuisJson(Map<String, dynamic> j) => Geste(
        joueurId: j['joueur_id'] as String,
        type: j['type'] as String,
        valeur: (j['valeur'] as Map?)?.cast<String, dynamic>() ?? const {},
        quand: DateTime.tryParse((j['cree_le'] as String?) ?? '') ?? DateTime(2000),
      );
}

/// Le film de la semaine, choisi par le Programmateur (ou par Pop).
class FilmDeLigue {
  const FilmDeLigue({required this.titre, this.filmId, this.synopsis, this.infos = '', this.parPop = false});

  final String titre;
  final String? filmId;
  final String? synopsis;
  final String infos;
  final bool parPop;

  Map<String, dynamic> versJson() => {
        'titre': titre,
        if (filmId != null) 'film_id': filmId,
        if (synopsis != null) 'synopsis': synopsis,
        'infos': infos,
        'par_pop': parPop,
      };

  static FilmDeLigue depuisJson(Map<String, dynamic> j) => FilmDeLigue(
        titre: (j['titre'] as String?) ?? 'Film mystère',
        filmId: j['film_id'] as String?,
        synopsis: j['synopsis'] as String?,
        infos: (j['infos'] as String?) ?? '',
        parPop: (j['par_pop'] as bool?) ?? false,
      );
}

/// La semaine d'une ligue : qui programme, qui est le Faussaire, où en est
/// chacun, et les points de la Révélation. Tout se calcule à partir des
/// gestes : la télé et les téléphones voient la même chose.
///
/// Points :
///  - Bluff : trouver le vrai synopsis +2 ; chaque ami piégé par ton faux +1.
///  - Curseur : le plus proche de la moyenne +1 (à égalité, tous).
///  - Faussaire : le démasquer +2 ; chaque ami trompé rapporte +1 au Faussaire.
class SemaineDeLigue {
  SemaineDeLigue({required List<String> membres, required this.semaine, required this.gestes}) : membres = [...membres]..sort();

  /// Identifiants des membres, triés : l'ordre de passage est stable.
  final List<String> membres;

  /// Le lundi de la semaine, « 2026-11-02 ».
  final String semaine;
  final List<Geste> gestes;

  static const vrai = 'vrai';

  int get numero {
    final d = DateTime.parse(semaine);
    return DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000 ~/ 7;
  }

  /// Chacun son tour, une semaine chacun.
  String? get programmateur => membres.isEmpty ? null : membres[numero % membres.length];

  /// Le Faussaire de la semaine (jamais le Programmateur, s'il y a assez de
  /// monde). Son rôle n'apparaît que sur son téléphone.
  String? get faussaire {
    if (membres.length < 3) return null;
    var i = (numero * 7 + 3) % membres.length;
    if (membres[i] == programmateur) i = (i + 1) % membres.length;
    return membres[i];
  }

  Iterable<Geste> _de(String type) => gestes.where((g) => g.type == type && membres.contains(g.joueurId));

  Geste? _geste(String joueur, String type) => _de(type).where((g) => g.joueurId == joueur).firstOrNull;

  FilmDeLigue? get affiche {
    final a = gestes.where((g) => g.type == 'affiche').toList()..sort((x, y) => x.quand.compareTo(y.quand));
    return a.isEmpty ? null : FilmDeLigue.depuisJson(a.first.valeur);
  }

  Map<String, String> get bluffs => {
        for (final g in _de('bluff'))
          if ((g.valeur['texte'] as String?)?.trim().isNotEmpty ?? false) g.joueurId: (g.valeur['texte'] as String).trim(),
      };

  String? bluffDe(String j) => bluffs[j];
  String? voteBluffDe(String j) => _geste(j, 'vote_bluff')?.valeur['choix'] as String?;
  int? curseurDe(String j) => (_geste(j, 'curseur')?.valeur['valeur'] as num?)?.toInt();
  String? verdictDe(String j) => _geste(j, 'verdict')?.valeur['texte'] as String?;
  String? voteFaussaireDe(String j) => _geste(j, 'vote_faussaire')?.valeur['choix'] as String?;

  /// Les synopsis à départager pour [moi] : le vrai et les faux des autres,
  /// dans un ordre mélangé, le même pour tout le monde.
  List<(String, String)> synopsisPour(String moi) {
    final vraiTexte = affiche?.synopsis;
    final liste = <(String, String)>[
      if (vraiTexte != null && vraiTexte.isNotEmpty) (vrai, vraiTexte),
      for (final e in bluffs.entries)
        if (e.key != moi) (e.key, e.value),
    ];
    liste.sort((a, b) => a.$1.compareTo(b.$1));
    liste.shuffle(Random(numero));
    return liste;
  }

  double? get moyenneCurseur {
    final v = membres.map(curseurDe).whereType<int>().toList();
    if (v.isEmpty) return null;
    return v.reduce((a, b) => a + b) / v.length;
  }

  /// Combien de membres ont fait ce geste.
  int combien(String type) => membres.where((j) => _geste(j, type) != null).length;

  Map<String, int> get points {
    final p = {for (final j in membres) j: 0};
    for (final g in _de('vote_bluff')) {
      final choix = g.valeur['choix'] as String?;
      if (choix == vrai) {
        p[g.joueurId] = p[g.joueurId]! + 2;
      } else if (choix != null && choix != g.joueurId && p.containsKey(choix)) {
        p[choix] = p[choix]! + 1;
      }
    }
    final m = moyenneCurseur;
    final places = {for (final j in membres) j: curseurDe(j)}..removeWhere((_, v) => v == null);
    if (m != null && places.length >= 2) {
      final ecart = places.values.map((v) => (v! - m).abs()).reduce(min);
      for (final e in places.entries) {
        if ((e.value! - m).abs() == ecart) p[e.key] = p[e.key]! + 1;
      }
    }
    final f = faussaire;
    if (f != null) {
      for (final g in _de('vote_faussaire')) {
        if (g.joueurId == f) continue;
        if (g.valeur['choix'] == f) {
          p[g.joueurId] = p[g.joueurId]! + 2;
        } else {
          p[f] = p[f]! + 1;
        }
      }
    }
    return p;
  }
}
