import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/modeles.dart';
import 'duel.dart';
import 'ligues.dart';
import 'bingo.dart';

/// La Soirée jeu : la télé est le plateau, les téléphones sont les manettes.
/// C'est le Duel du canapé, de 2 à 4 joueurs, chacun depuis son téléphone :
/// à son tour, on écarte en secret une carte d'un adversaire (ou une des
/// siennes quand les autres n'en ont plus qu'une), et au quiz on répond en
/// même temps.
///
/// L'état est un simple objet JSON tenu par la télé ([PartieSoiree]) ; les
/// téléphones le lisent et envoient leurs gestes, que la télé applique.
abstract final class PartieSoiree {
  static const nbQuestions = 5;

  /// Un code de 4 lettres faciles à lire (sans I, O, Q, ni L).
  static String code(Random hasard) {
    const lettres = 'ABCDEFGHJKMNPRSTUVWXYZ';
    return List.generate(4, (_) => lettres[hasard.nextInt(lettres.length)]).join();
  }

  static Map<String, dynamic> nouvelle() => {'phase': 'attente', 'joueurs': <Map<String, dynamic>>[]};

  static Map<String, dynamic> filmVersJson(Film f) => {
        'id': f.id,
        'titre': f.titre,
        if (f.annee != null) 'annee': f.annee,
        if (f.dureeMinutes != null) 'duree': f.dureeMinutes,
        if (f.note != null) 'note': f.note,
        if (f.realisateur != null) 'realisateur': f.realisateur,
        if (f.synopsis != null) 'synopsis': f.synopsis,
        if (f.serveurId != null) 'serveur': f.serveurId,
        if (f.tmdbId != null) 'tmdb': f.tmdbId,
        if (f.enVod != null) 'vod': f.enVod,
        if (f.genres.isNotEmpty) 'genres': f.genres,
        if (f.pays.isNotEmpty) 'pays': f.pays,
        'source': f.source.name,
      };

  static Film filmDepuisJson(Map<String, dynamic> j) => Film(
        id: j['id'] as String,
        titre: j['titre'] as String,
        annee: j['annee'] as int?,
        dureeMinutes: j['duree'] as int?,
        note: (j['note'] as num?)?.toDouble(),
        realisateur: j['realisateur'] as String?,
        synopsis: j['synopsis'] as String?,
        serveurId: j['serveur'] as String?,
        tmdbId: j['tmdb'] as int?,
        enVod: j['vod'] as bool?,
        genres: [for (final g in (j['genres'] as List? ?? const [])) '$g'],
        pays: [for (final p in (j['pays'] as List? ?? const [])) '$p'],
        source: SourceFilm.values.firstWhere((s) => s.name == j['source'], orElse: () => SourceFilm.demo),
      );

  static const minJoueurs = 2;
  static const maxJoueurs = 4;

  /// La télé distribue : 3 cartes par joueur (de 2 à 4), et le quiz.
  static Map<String, dynamic> distribuer(
    List<Map<String, dynamic>> joueurs,
    List<List<CarteDefi>> mains,
    List<Question> questions,
    Random hasard, {
    List<Map<String, dynamic>> public = const [],
  }) =>
      {
        'phase': 'table',
        'joueurs': joueurs,
        'public': [for (final p in public) {'id': p['id'], 'pseudo': p['pseudo']}],
        'cartes': [
          for (final (j, main) in mains.indexed)
            for (final c in main)
              {
                'j': j,
                'type': c.type.name,
                'defi': c.defi,
                'indice': c.indice,
                'cases': c.cases,
                'film': filmVersJson(c.film),
                'ecartee': false,
                'protegee': false,
              },
        ],
        'tour': 0,
        'veto': [for (final _ in joueurs) true],
        'questions': [
          for (final q in questions) {'texte': q.texte, 'reponses': [...q.reponses]..shuffle(hasard), 'bonne': q.bonne},
        ],
        'question': 0,
        'reponses': <String, String>{},
        'revele': false,
        'points': [for (final _ in joueurs) 0],
        'message': '${joueurs[0]['pseudo']} commence : sur ton téléphone, écarte une carte d\'un adversaire.',
      };

  /// Le public (Jackbox) : ceux qui ne jouent pas mais votent. Au quiz,
  /// chacun soutient un joueur ; au Pitch, il devine aussi.
  static List<Map<String, dynamic>> publicDe(Map<String, dynamic> e) => [...((e['public'] as List?) ?? const []).cast<Map<String, dynamic>>()];

  static int indexPublic(Map<String, dynamic> e, String id) => publicDe(e).indexWhere((p) => p['id'] == id);

  /// Les gestes de ceux qui ne sont pas joueurs : entrer dans le public,
  /// soutenir un joueur, répondre au quiz, voter au Pitch.
  static Map<String, dynamic>? _geste(Map<String, dynamic> e, String id, Map<String, dynamic> action) {
    final phase = e['phase'];
    if (phase == 'attente' || phase == 'fin') return null;
    final k = indexPublic(e, id);
    switch (action['type']) {
      case 'public':
        if (k >= 0) return null;
        final pseudo = '${action['pseudo'] ?? 'Public'}'.trim();
        e['public'] = [...publicDe(e), {'id': id, 'pseudo': pseudo.isEmpty ? 'Public' : (pseudo.length > 24 ? pseudo.substring(0, 24) : pseudo)}];
        return e;
      case 'soutenir' when k >= 0:
        final j = action['joueur'];
        if (j is! int || j < 0 || j >= nbJoueurs(e)) return null;
        final p = publicDe(e);
        p[k] = {...p[k], 'soutien': j};
        e['public'] = p;
        return e;
      case 'reponse' when k >= 0 && phase == 'quiz' && e['revele'] != true:
        if (action['question'] != e['question']) return null;
        final r = {...((e['reponses_public'] as Map?) ?? const {}).cast<String, String>()};
        if (r.containsKey(id)) return null;
        r[id] = '${action['choix']}';
        e['reponses_public'] = r;
        return e;
      case 'vote' when k >= 0:
        return Pitch.voteDuPublic(e, id, action);
      default:
        return null;
    }
  }

  static List<Map<String, dynamic>> cartes(Map<String, dynamic> e) => [...((e['cartes'] as List?) ?? const []).cast<Map<String, dynamic>>()];

  static int nbJoueurs(Map<String, dynamic> e) => ((e['joueurs'] as List?) ?? const []).length;

  static int indexDe(Map<String, dynamic> e, String joueurId) =>
      ((e['joueurs'] as List?) ?? const []).cast<Map<String, dynamic>>().indexWhere((j) => j['id'] == joueurId);

  static int restantes(Map<String, dynamic> e, int j) => cartes(e).where((c) => c['j'] == j && c['ecartee'] != true).length;

  static bool tableFinie(Map<String, dynamic> e) => [for (var j = 0; j < nbJoueurs(e); j++) restantes(e, j)].every((n) => n <= 1);

  /// Vrai quand tous les adversaires n'ont plus qu'une carte : le joueur du
  /// tour doit alors écarter une des siennes.
  static bool doitEcarterLaSienne(Map<String, dynamic> e) {
    final tour = e['tour'] as int;
    return [for (var j = 0; j < nbJoueurs(e); j++) if (j != tour) restantes(e, j)].every((n) => n <= 1);
  }

  static bool peutEcarter(Map<String, dynamic> e, int i) {
    if (e['phase'] != 'table' || tableFinie(e)) return false;
    final c = cartes(e)[i];
    final tour = e['tour'] as int;
    final proprietaire = c['j'] as int;
    if (c['ecartee'] == true) return false;
    if (proprietaire == tour) return doitEcarterLaSienne(e) && restantes(e, tour) > 1;
    return !doitEcarterLaSienne(e) && restantes(e, proprietaire) > 1 && c['protegee'] != true;
  }

  static bool peutProteger(Map<String, dynamic> e, int i) {
    if (e['phase'] != 'table' || tableFinie(e)) return false;
    final c = cartes(e)[i];
    final tour = e['tour'] as int;
    return (e['veto'] as List)[tour] == true && c['j'] == tour && c['ecartee'] != true && c['protegee'] != true;
  }

  /// Applique le geste d'un joueur. Renvoie le nouvel état, ou null si le
  /// geste n'est pas permis (pas son tour, carte interdite…).
  static Map<String, dynamic>? appliquer(Map<String, dynamic> etat, String joueurId, Map<String, dynamic> action) {
    final e = Map<String, dynamic>.from(etat);
    if (e['phase'] == 'bingo') return BingoSoiree.appliquer(e, joueurId, action);
    final j = indexDe(e, joueurId);
    if (j < 0) return _geste(e, joueurId, action);
    final n = nbJoueurs(e);
    final noms = ((e['joueurs'] as List).cast<Map<String, dynamic>>()).map((x) => x['pseudo'] as String).toList();
    switch (action['type']) {
      case 'ecarter' || 'veto' when e['phase'] == 'table':
        if (e['tour'] != j) return null;
        final i = action['carte'] as int;
        if (i < 0 || i >= cartes(e).length) return null;
        final veto = action['type'] == 'veto';
        if (veto ? !peutProteger(e, i) : !peutEcarter(e, i)) return null;
        final cs = cartes(e);
        final victime = cs[i]['j'] as int;
        cs[i] = {...cs[i], (veto ? 'protegee' : 'ecartee'): true};
        e['cartes'] = cs;
        if (veto) e['veto'] = [for (var k = 0; k < n; k++) k == j ? false : (e['veto'] as List)[k]];
        e['tour'] = (j + 1) % n;
        e['message'] = veto
            ? '${noms[j]} pose son Veto sur une de ses cartes. Malin…'
            : (victime == j ? '${noms[j]} se sépare d\'une de ses cartes.' : '${noms[j]} écarte une carte de ${noms[victime]} !');
        if (tableFinie(e)) {
          e['phase'] = 'quiz';
          e['message'] = 'Il reste une carte chacun. Place au quiz : répondez sur vos téléphones !';
        } else {
          e['message'] = '${e['message']} À ${noms[e['tour'] as int]} de jouer.';
        }
        return e;
      case 'mots' || 'vote':
        return Pitch.appliquer(e, j, joueurId, action);
      case 'reponse' when e['phase'] == 'quiz' && e['revele'] != true:
        if (action['question'] != e['question']) return null;
        final reponses = {...(e['reponses'] as Map).cast<String, String>()};
        if (reponses.containsKey(joueurId)) return null;
        reponses[joueurId] = action['choix'] as String;
        e['reponses'] = reponses;
        if (reponses.length >= n) _reveler(e);
        return e;
      default:
        return null;
    }
  }

  static void _reveler(Map<String, dynamic> e) {
    final q = (e['questions'] as List)[e['question'] as int] as Map;
    final reponses = (e['reponses'] as Map).cast<String, String>();
    final pts = [...(e['points'] as List).cast<int>()];
    final bons = <int>{};
    for (final r in reponses.entries) {
      final j = indexDe(e, r.key);
      if (j >= 0 && r.value == q['bonne']) {
        pts[j]++;
        bons.add(j);
      }
    }
    // Le public souffle : un joueur qui s'est trompé gagne quand même le
    // point si quelqu'un qui le soutient a trouvé.
    final publicRep = ((e['reponses_public'] as Map?) ?? const {}).cast<String, String>();
    final souffles = <int>{};
    for (final p in publicDe(e)) {
      final soutien = p['soutien'];
      if (soutien is int && soutien < pts.length && !bons.contains(soutien) && publicRep[p['id']] == q['bonne']) souffles.add(soutien);
    }
    for (final k in souffles) {
      pts[k]++;
    }
    e['souffles'] = souffles.toList();
    e['points'] = pts;
    e['revele'] = true;
  }

  /// La télé passe à la question suivante (ou à la fin). Si quelqu'un n'a
  /// pas répondu, on révèle quand même.
  static Map<String, dynamic> suivante(Map<String, dynamic> etat) {
    if (etat['phase'] == 'bingo') return BingoSoiree.suivante(etat);
    if (etat['mode'] == 'pitch') return Pitch.suivante(etat);
    final e = Map<String, dynamic>.from(etat);
    if (e['phase'] != 'quiz') return e;
    if (e['revele'] != true) {
      _reveler(e);
      return e;
    }
    final suivanteQuestion = (e['question'] as int) + 1;
    if (suivanteQuestion >= (e['questions'] as List).length) {
      final pts = (e['points'] as List).cast<int>();
      final n = nbJoueurs(e);
      final restes = [for (var j = 0; j < n; j++) cartes(e).firstWhere((c) => c['j'] == j && c['ecartee'] != true)];
      double note(Map c) => ((c['film'] as Map)['note'] as num?)?.toDouble() ?? 0;
      final meilleur = pts.reduce(max);
      // À égalité de points, le film le mieux noté l'emporte.
      final exAequo = [for (var j = 0; j < n; j++) if (pts[j] == meilleur) j];
      final gagnant = exAequo.reduce((a, b) => note(restes[b]) > note(restes[a]) ? b : a);
      e['phase'] = 'fin';
      e['gagnant'] = gagnant;
      e['film'] = restes[gagnant]['film'];
      return e;
    }
    e['question'] = suivanteQuestion;
    e['reponses'] = <String, String>{};
    e['reponses_public'] = <String, String>{};
    e['souffles'] = <int>[];
    e['revele'] = false;
    return e;
  }
}

/// « Le Pitch » (façon Dixit) : à chaque manche, un conteur reçoit en
/// secret un film parmi quatre et le décrit en trois mots choisis parmi
/// douze. Les autres votent. Si tout le monde ou personne ne trouve, le
/// conteur ne marque rien et les autres prennent 2 points ; sinon le conteur
/// et ceux qui ont trouvé prennent 3 points. Si le public trouve en
/// majorité, le conteur gagne 1 point de plus. Chacun raconte une fois ;
/// le gagnant lance le film qu'il a décrit.
abstract final class Pitch {
  static const parManche = 4;
  static const nbMots = 3;
  static const motsProposes = 12;

  static const mots = [
    'Vengeance', 'Pluie', 'Fuite', 'Amour impossible', 'Monstre', 'Famille', 'Désert', 'Trahison', 'Fou rire', 'Nuit',
    'Voyage', 'Secret', 'Enfance', 'Guerre', 'Musique', 'Argent', 'Espace', 'Folie', 'Prison', 'Mer',
    'Train', 'Neige', 'Robot', 'Fantôme', 'Mariage', 'Enquête', 'Course', 'Danse', 'Magie', 'Ville',
    'Campagne', 'Hiver', 'Été', 'Chien', 'Héros', 'Mensonge', 'Révolution', 'Rêve', 'Feu', 'Cuisine',
  ];

  static Map<String, dynamic> nouvelle(List<Map<String, dynamic>> joueurs, List<Film> films, Random hasard, {List<Map<String, dynamic>> public = const []}) {
    final n = joueurs.length;
    assert(films.length >= n * parManche);
    return {
      'mode': 'pitch',
      'phase': 'pitch_mots',
      'joueurs': joueurs,
      'public': [for (final p in public) {'id': p['id'], 'pseudo': p['pseudo']}],
      'manches': [
        for (var k = 0; k < n; k++)
          {
            'conteur': k,
            'films': [for (final f in films.skip(k * parManche).take(parManche)) PartieSoiree.filmVersJson(f)],
            'cible': hasard.nextInt(parManche),
            'proposes': ([...mots]..shuffle(hasard)).take(motsProposes).toList(),
            'mots': <String>[],
            'votes': <String, int>{},
            'votes_public': <String, int>{},
          },
      ],
      'manche': 0,
      'points': [for (final _ in joueurs) 0],
      'message': '${joueurs[0]['pseudo']} raconte : sur ton téléphone, décris ton film en trois mots.',
    };
  }

  static Map<String, dynamic> mancheDe(Map<String, dynamic> e) => ((e['manches'] as List)[e['manche'] as int] as Map).cast<String, dynamic>();

  static void _remplacerManche(Map<String, dynamic> e, Map<String, dynamic> m) {
    final ms = [...(e['manches'] as List)];
    ms[e['manche'] as int] = m;
    e['manches'] = ms;
  }

  static Map<String, dynamic>? appliquer(Map<String, dynamic> e, int j, String id, Map<String, dynamic> action) {
    if (e['mode'] != 'pitch') return null;
    final m = mancheDe(e);
    final noms = [for (final x in (e['joueurs'] as List).cast<Map>()) '${x['pseudo']}'];
    switch (action['type']) {
      case 'mots' when e['phase'] == 'pitch_mots' && m['conteur'] == j:
        final choisis = [for (final x in (action['mots'] as List? ?? const [])) '$x'];
        final proposes = (m['proposes'] as List).cast<String>();
        if (choisis.length != nbMots || choisis.toSet().length != nbMots || !choisis.every(proposes.contains)) return null;
        _remplacerManche(e, {...m, 'mots': choisis});
        e['phase'] = 'pitch_vote';
        e['message'] = '${noms[j]} a parlé : « ${choisis.join(' · ')} ». Votez sur vos téléphones !';
        return e;
      case 'vote' when e['phase'] == 'pitch_vote' && m['conteur'] != j:
        final f = action['film'];
        if (f is! int || f < 0 || f >= parManche) return null;
        final votes = {...(m['votes'] as Map).cast<String, int>()};
        if (votes.containsKey(id)) return null;
        votes[id] = f;
        _remplacerManche(e, {...m, 'votes': votes});
        if (votes.length >= PartieSoiree.nbJoueurs(e) - 1) _reveler(e);
        return e;
      default:
        return null;
    }
  }

  static Map<String, dynamic>? voteDuPublic(Map<String, dynamic> e, String id, Map<String, dynamic> action) {
    if (e['mode'] != 'pitch' || e['phase'] != 'pitch_vote') return null;
    final m = mancheDe(e);
    final f = action['film'];
    if (f is! int || f < 0 || f >= parManche) return null;
    final votes = {...((m['votes_public'] as Map?) ?? const {}).cast<String, int>()};
    if (votes.containsKey(id)) return null;
    votes[id] = f;
    _remplacerManche(e, {...m, 'votes_public': votes});
    return e;
  }

  static void _reveler(Map<String, dynamic> e) {
    final m = mancheDe(e);
    final n = PartieSoiree.nbJoueurs(e);
    final conteur = m['conteur'] as int;
    final cible = m['cible'] as int;
    final votes = (m['votes'] as Map).cast<String, int>();
    final trouveurs = [for (final v in votes.entries) if (v.value == cible) PartieSoiree.indexDe(e, v.key)].where((k) => k >= 0).toList();
    final pts = [...(e['points'] as List).cast<int>()];
    final noms = [for (final x in (e['joueurs'] as List).cast<Map>()) '${x['pseudo']}'];
    final autres = n - 1;
    String message;
    if (trouveurs.isEmpty || trouveurs.length == autres) {
      for (var k = 0; k < n; k++) {
        if (k != conteur) pts[k] += 2;
      }
      message = trouveurs.isEmpty ? 'Personne n\'a trouvé : ${noms[conteur]} ne marque rien, les autres prennent 2 points.' : 'Tout le monde a trouvé : trop facile ! ${noms[conteur]} ne marque rien, les autres prennent 2 points.';
    } else {
      pts[conteur] += 3;
      for (final k in trouveurs) {
        pts[k] += 3;
      }
      message = '${trouveurs.map((k) => noms[k]).join(' et ')} ${trouveurs.length > 1 ? 'ont' : 'a'} trouvé : 3 points pour eux et pour ${noms[conteur]}.';
    }
    final vp = ((m['votes_public'] as Map?) ?? const {}).cast<String, int>();
    if (vp.isNotEmpty && vp.values.where((v) => v == cible).length * 2 > vp.length) {
      pts[conteur] += 1;
      message = '$message Le public a compris : +1 pour ${noms[conteur]}.';
    }
    e['points'] = pts;
    e['phase'] = 'pitch_revele';
    e['message'] = message;
  }

  /// La télé passe à la suite : révéler si quelqu'un traîne, manche
  /// suivante, ou fin.
  static Map<String, dynamic> suivante(Map<String, dynamic> etat) {
    final e = Map<String, dynamic>.from(etat);
    switch (e['phase']) {
      case 'pitch_vote':
        _reveler(e);
        return e;
      case 'pitch_revele':
        final suivante = (e['manche'] as int) + 1;
        if (suivante < (e['manches'] as List).length) {
          e['manche'] = suivante;
          e['phase'] = 'pitch_mots';
          final noms = [for (final x in (e['joueurs'] as List).cast<Map>()) '${x['pseudo']}'];
          e['message'] = '${noms[mancheDe(e)['conteur'] as int]} raconte : sur ton téléphone, décris ton film en trois mots.';
          return e;
        }
        final pts = (e['points'] as List).cast<int>();
        final meilleur = pts.reduce(max);
        final gagnant = pts.indexOf(meilleur);
        final sienne = (e['manches'] as List).cast<Map>().firstWhere((m) => m['conteur'] == gagnant);
        e['phase'] = 'fin';
        e['gagnant'] = gagnant;
        e['film'] = (sienne['films'] as List)[sienne['cible'] as int];
        return e;
      default:
        return e;
    }
  }
}

/// Le Bingo du film dans la Soirée jeu (R55) : joueurs et public, chacun
/// sa grille. Étapes : « jeu » (on coche), « generique » (on conteste),
/// « fin » (les points).
abstract final class BingoSoiree {
  static List<String> participants(Map<String, dynamic> e) => [
        for (final j in ((e['joueurs'] as List?) ?? const []).cast<Map>()) '${j['id']}',
        for (final p in PartieSoiree.publicDe(e)) '${p['id']}',
      ];

  static String nomDe(Map<String, dynamic> e, String id) {
    for (final j in [...((e['joueurs'] as List?) ?? const []).cast<Map>(), ...PartieSoiree.publicDe(e)]) {
      if (j['id'] == id) return '${j['pseudo']}';
    }
    return '?';
  }

  static Map<String, dynamic> demarrer(Map<String, dynamic> etat, List<String> genres, Random hasard) {
    final e = Map<String, dynamic>.from(etat);
    e['phase'] = 'bingo';
    e['bingo'] = {
      'etape': 'jeu',
      'grilles': {for (final id in participants(e)) id: Bingo.grille(genres, hasard)},
      'cochees': <String, List<int>>{},
      'contestes': <String, List<String>>{},
    };
    return e;
  }

  static Map<String, dynamic> _b(Map<String, dynamic> e) => (e['bingo'] as Map).cast<String, dynamic>();

  static Set<int> cocheesDe(Map<String, dynamic> e, String id) => {for (final x in (((_b(e)['cochees'] as Map?) ?? const {})[id] as List? ?? const [])) (x as num).toInt()};

  static int contestations(Map<String, dynamic> e, String id, int k) => (((_b(e)['contestes'] as Map?) ?? const {})['$id|$k'] as List? ?? const []).length;

  static Map<String, dynamic>? appliquer(Map<String, dynamic> e, String id, Map<String, dynamic> action) {
    final b = _b(e);
    final grilles = (b['grilles'] as Map).cast<String, dynamic>();
    if (!grilles.containsKey(id)) return null;
    switch (action['type']) {
      case 'cocher' when b['etape'] == 'jeu':
        final k = action['case'];
        if (k is! int || k < 0 || k >= Bingo.cases) return null;
        final mes = cocheesDe(e, id);
        if (!mes.remove(k)) mes.add(k);
        e['bingo'] = {...b, 'cochees': {...(b['cochees'] as Map).cast<String, dynamic>(), id: (mes.toList()..sort())}};
        return e;
      case 'contester' when b['etape'] == 'generique':
        final qui = '${action['qui']}';
        final k = action['case'];
        if (qui == id || k is! int || !cocheesDe(e, qui).contains(k)) return null;
        final contestes = (b['contestes'] as Map).cast<String, dynamic>();
        final cle = '$qui|$k';
        final deja = [for (final v in (contestes[cle] as List? ?? const [])) '$v'];
        if (deja.contains(id)) return null;
        e['bingo'] = {...b, 'contestes': {...contestes, cle: [...deja, id]}};
        return e;
      default:
        return null;
    }
  }

  /// Les points de chacun, au générique.
  static Map<String, int> points(Map<String, dynamic> e) {
    final ids = participants(e);
    final autres = ids.length - 1;
    return {
      for (final id in ids)
        id: () {
          final cochees = cocheesDe(e, id);
          final rejetees = {for (final k in cochees) if (Bingo.rejetee(contestations(e, id, k), autres)) k};
          return Bingo.points(cochees: cochees, rejetees: rejetees);
        }(),
    };
  }

  static Map<String, dynamic> suivante(Map<String, dynamic> etat) {
    final e = Map<String, dynamic>.from(etat);
    final b = _b(e);
    switch (b['etape']) {
      case 'jeu':
        e['bingo'] = {...b, 'etape': 'generique'};
      case 'generique':
        e['bingo'] = {...b, 'etape': 'fin', 'points': points(e)};
    }
    return e;
  }
}

/// Les échanges avec le serveur pour la Soirée jeu (migration 0005).
class ServiceSoiree {
  ServiceSoiree(this._client);
  final SupabaseClient _client;

  String? get monId => _client.auth.currentUser?.id;

  Future<void> _connecte() async {
    if (_client.auth.currentUser == null) await _client.auth.signInAnonymously();
  }

  Future<T> _proteger<T>(Future<T> Function() f) async {
    try {
      await _connecte();
      return await f();
    } on PostgrestException catch (e) {
      throw ErreurLigue('Le serveur a refusé : ${e.message}. La migration 0005 est-elle installée ?');
    } on AuthException catch (e) {
      throw ErreurLigue('Connexion impossible : ${e.message}.');
    } catch (e) {
      if (e is ErreurLigue) rethrow;
      throw const ErreurLigue('Le serveur ne répond pas. Vérifie la connexion.');
    }
  }

  /// La télé ouvre une soirée et renvoie son code.
  Future<String> ouvrir() => _proteger(() async {
        final hasard = Random();
        for (var essai = 0; essai < 5; essai++) {
          final code = PartieSoiree.code(hasard);
          try {
            await _client.from('soirees').insert({'code': code, 'etat': PartieSoiree.nouvelle()});
            return code;
          } on PostgrestException catch (e) {
            if (e.code != '23505') rethrow; // code déjà pris : on retente
          }
        }
        throw const ErreurLigue('Impossible de créer la soirée. Réessaie.');
      });

  Future<void> rejoindre(String code, {required String pseudo, required Profil profil, required Emotion envie}) => _proteger(() async {
        final c = code.trim().toUpperCase();
        final soiree = await _client.from('soirees').select('code').eq('code', c).maybeSingle();
        if (soiree == null) throw const ErreurLigue('Aucune soirée avec ce code. Regarde l\'écran de la télé.');
        await _client.from('soiree_joueurs').upsert({'code': c, 'joueur_id': monId, 'pseudo': pseudo, 'profil': profil.name, 'envie': envie.name});
      });

  Future<List<Map<String, dynamic>>> joueurs(String code) =>
      _proteger(() async => (await _client.from('soiree_joueurs').select().eq('code', code).order('rejoint_le')).cast<Map<String, dynamic>>());

  Future<Map<String, dynamic>> etat(String code) => _proteger(() async {
        final r = await _client.from('soirees').select('etat').eq('code', code).single();
        return (r['etat'] as Map).cast<String, dynamic>();
      });

  Future<void> ecrireEtat(String code, Map<String, dynamic> etat) => _proteger<void>(() async {
        await _client.from('soirees').update({'etat': etat, 'maj': DateTime.now().toUtc().toIso8601String()}).eq('code', code);
      });

  Future<void> geste(String code, Map<String, dynamic> action) => _proteger<void>(() async {
        await _client.from('soiree_actions').insert({'code': code, 'joueur_id': monId, 'action': action});
      });

  /// Les gestes reçus après [depuis] (identifiant croissant).
  Future<List<(int, String, Map<String, dynamic>)>> gestes(String code, int depuis) => _proteger(() async {
        final rep = await _client.from('soiree_actions').select().eq('code', code).gt('id', depuis).order('id');
        return [
          for (final r in rep) ((r['id'] as num).toInt(), r['joueur_id'] as String, (r['action'] as Map).cast<String, dynamic>()),
        ];
      });
}
