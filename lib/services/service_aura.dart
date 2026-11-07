import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/modeles.dart';
import 'aura.dart';
import 'ligues.dart';
import 'sources.dart';
import 'veille.dart';

/// L'aura côté serveur (R47, R48) : relier le joueur à sa maison Jellyfin,
/// trouver à qui proposer, proposer, et dire ce qui a été vu ou aimé.
/// Partage la connexion des ligues.
class ServiceAura {
  ServiceAura(this.ligues, {http.Client? client}) : _http = client ?? http.Client();

  final ServiceLigues ligues;
  final http.Client _http;

  SupabaseClient get _db => ligues.client;

  /// Le serveur Jellyfin (son identifiant) et la personne de ce profil.
  String? maison;
  String? personne;

  /// En édition VJOD : relie le joueur au serveur Jellyfin et à son
  /// utilisateur, comme VJOD le fait, pour que l'aura se cumule.
  Future<void> relier(ConnexionJellyfin c) async {
    if (!c.complete || ligues.monId == null) return;
    try {
      final rep = await _http.get(c.url('/System/Info/Public', const {}), headers: c.entetes);
      if (rep.statusCode != 200) return;
      final id = '${(jsonDecode(utf8.decode(rep.bodyBytes)) as Map)['Id'] ?? ''}';
      if (id.isEmpty) return;
      maison = id;
      personne = '$id:${c.utilisateurId}';
      await _db.from('joueurs').update({'maison': maison, 'personne': personne}).eq('id', ligues.monId!);
      await (await SharedPreferences.getInstance()).setString(Veille.clePersonne, personne!);
    } catch (_) {
      // Hors ligne : on réessaiera à la prochaine ouverture.
    }
  }

  Future<List<Destinataire>> destinataires() => _proteger(() async {
        final maisonListe = <({String pseudo, String? personne})>[];
        if (maison != null) {
          final rep = await _db.from('joueurs').select('pseudo, personne').eq('maison', maison!);
          for (final j in rep) {
            maisonListe.add((pseudo: '${j['pseudo'] ?? '?'}', personne: j['personne'] as String?));
          }
        }
        final amis = <({String joueur, String pseudo, String? personne, String ligueId})>[];
        for (final l in ligues.ligues) {
          final rep = await _db.from('membres').select('joueur_id, joueurs(pseudo, personne)').eq('ligue_id', l.id);
          for (final m in rep) {
            final j = m['joueurs'];
            if (j is! Map) continue;
            amis.add((joueur: '${m['joueur_id']}', pseudo: '${j['pseudo'] ?? '?'}', personne: j['personne'] as String?, ligueId: l.id));
          }
        }
        return Destinataire.liste(maison: maisonListe, amis: amis, moiPersonne: personne, moiJoueur: ligues.monId ?? '');
      });

  Future<List<Proposition>> propositions() => _proteger(() async {
        final rep = await _db.from('propositions').select().order('cree_le', ascending: false).limit(300);
        return [
          for (final j in rep)
            if (Proposition.depuisJson(j) case final p?) p,
        ];
      });

  Future<void> proposer(Destinataire d, Film f, {String? mot, DateTime? ouvrirLe}) => _proteger(() async {
        await _db.from('propositions').insert(Proposition.nouvelle(
          dePersonne: personne,
          deNom: ligues.pseudo ?? '?',
          pourPersonne: d.personne,
          pourJoueur: d.personne == null ? d.joueur : null,
          pourNom: d.nom,
          maison: d.maison ? maison : null,
          ligueId: d.ligueId,
          titre: f.titre,
          annee: f.annee,
          tmdb: f.tmdbId,
          jellyfin: f.source == SourceFilm.jellyfin ? f.id : null,
          mot: mot,
          ouvrirLe: ouvrirLe,
        ));
      });

  /// Celui qui reçoit dit s'il a vu, aimé, et sa note.
  Future<void> marquer(Proposition p, {bool? aime, int? note}) => _proteger(() async {
        await _db.from('propositions').update({
          if (!p.vu) 'vu_le': DateTime.now().toUtc().toIso8601String(),
          if (aime != null) 'aime': aime,
          if (note != null) 'note': note,
        }).eq('id', p.id);
      });

  /// Regarde dans Jellyfin si ce qu'on m'a proposé a été vu ou aimé.
  /// Renvoie vrai quand quelque chose a été écrit.
  Future<bool> verifierJellyfin(ConnexionJellyfin c, List<Proposition> recues) async {
    if (!c.complete) return false;
    var change = false;
    for (final p in recues) {
      if (p.vu && p.aime) continue;
      try {
        final params = <String, String>{
          'Recursive': 'true',
          'Limit': '1',
          'IncludeItemTypes': p.serie ? 'Series' : 'Movie',
          if (p.jellyfin != null && p.jellyfin!.isNotEmpty) 'Ids': p.jellyfin! else if (p.tmdb != null) 'AnyProviderIdEquals': 'tmdb.${p.tmdb}',
        };
        if (!params.containsKey('Ids') && !params.containsKey('AnyProviderIdEquals')) continue;
        final rep = await _http.get(c.url('/Users/${c.utilisateurId}/Items', params), headers: c.entetes);
        if (rep.statusCode != 200) continue;
        final items = ((jsonDecode(utf8.decode(rep.bodyBytes)) as Map)['Items'] as List?) ?? const [];
        if (items.isEmpty || items.first is! Map) continue;
        final maj = majDepuisJellyfin((items.first as Map)['UserData'] as Map<String, dynamic>?, p, DateTime.now());
        if (maj == null) continue;
        await _db.from('propositions').update(maj).eq('id', p.id);
        change = true;
      } catch (_) {}
    }
    return change;
  }

  /// Vrai si la proposition m'est adressée (sur ce joueur ou ma personne).
  bool pourMoi(Proposition p) => p.pourJoueur == ligues.monId || (personne != null && p.pourPersonne == personne);

  /// Vrai si c'est moi qui l'ai faite (depuis Aura ou depuis VJOD).
  bool deMoi(Proposition p) => p.de == ligues.monId || (personne != null && p.dePersonne == personne);

  /// Ma clé dans le classement.
  String get moi => personne ?? ligues.monId ?? '';

  Future<T> _proteger<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw const ErreurLigue('Tu lui as déjà proposé ce film.');
      throw ErreurLigue('Le serveur a refusé : ${e.message}');
    } on ErreurLigue {
      rethrow;
    } catch (_) {
      throw const ErreurLigue('Le serveur ne répond pas. Vérifie ta connexion.');
    }
  }
}
