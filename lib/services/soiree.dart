import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/modeles.dart';
import 'duel.dart';
import 'ligues.dart';

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
        source: SourceFilm.values.firstWhere((s) => s.name == j['source'], orElse: () => SourceFilm.demo),
      );

  static const minJoueurs = 2;
  static const maxJoueurs = 4;

  /// La télé distribue : 3 cartes par joueur (de 2 à 4), et le quiz.
  static Map<String, dynamic> distribuer(
    List<Map<String, dynamic>> joueurs,
    List<List<CarteDefi>> mains,
    List<Question> questions,
    Random hasard,
  ) =>
      {
        'phase': 'table',
        'joueurs': joueurs,
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
    final j = indexDe(e, joueurId);
    if (j < 0) return null;
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
    for (final r in reponses.entries) {
      final j = indexDe(e, r.key);
      if (j >= 0 && r.value == q['bonne']) pts[j]++;
    }
    e['points'] = pts;
    e['revele'] = true;
  }

  /// La télé passe à la question suivante (ou à la fin). Si quelqu'un n'a
  /// pas répondu, on révèle quand même.
  static Map<String, dynamic> suivante(Map<String, dynamic> etat) {
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
    e['revele'] = false;
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
