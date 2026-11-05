import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/modeles.dart';
import 'etat.dart';

/// Une ligue dont le joueur fait partie.
class Ligue {
  const Ligue({required this.id, required this.nom, required this.code});

  final String id;
  final String nom;
  final String code;

  static Ligue depuisJson(Map<String, dynamic> j) =>
      Ligue(id: j['id'] as String, nom: j['nom'] as String, code: j['code_invitation'] as String);
}

/// Une ligne du classement du mois dans une ligue.
class Classe {
  const Classe({required this.joueurId, required this.pseudo, required this.profil, required this.position, required this.seances});

  final String joueurId;
  final String pseudo;
  final Profil profil;
  final int position;
  final int seances;

  static Classe depuisJson(Map<String, dynamic> j) => Classe(
        joueurId: j['joueur_id'] as String,
        pseudo: j['pseudo'] as String,
        profil: Profil.depuisNom(j['profil'] as String?),
        position: (j['case_actuelle'] as num?)?.toInt() ?? 1,
        seances: (j['seances'] as num?)?.toInt() ?? 0,
      );
}

/// Le jeu partagé : compte, ligues par code d'invitation, séances envoyées
/// au serveur. Le compte est anonyme : un pseudo suffit, pas d'e-mail.
/// N'existe que si les clés Supabase ont été fournies à la compilation.
class ServiceLigues extends ChangeNotifier {
  ServiceLigues(this._client);

  final SupabaseClient _client;

  String? pseudo;
  List<Ligue> ligues = [];
  bool charge = false;

  String? get monId => _client.auth.currentUser?.id;
  bool get inscrit => monId != null && pseudo != null;

  /// Retrouve le joueur et ses ligues si un compte existe déjà sur l'appareil.
  Future<void> demarrer() async {
    try {
      final id = monId;
      if (id != null) {
        final j = await _client.from('joueurs').select('pseudo').eq('id', id).maybeSingle();
        pseudo = j?['pseudo'] as String?;
        if (pseudo != null) await _chargerLigues();
      }
    } catch (_) {
      // Hors ligne : on réessaiera à la prochaine ouverture de la Ligue.
    } finally {
      charge = true;
      notifyListeners();
    }
  }

  Future<void> inscrire(String nom, Profil profil) async {
    final p = nom.trim();
    if (p.length < 2 || p.length > 24) throw const ErreurLigue('Ton pseudo doit faire entre 2 et 24 lettres.');
    await _proteger(() async {
      if (monId == null) await _client.auth.signInAnonymously();
      await _client.from('joueurs').upsert({'id': monId, 'pseudo': p, 'profil': profil.name});
    });
    pseudo = p;
    notifyListeners();
  }

  Future<void> changerProfil(Profil profil) async {
    if (!inscrit) return;
    try {
      await _client.from('joueurs').update({'profil': profil.name}).eq('id', monId!);
    } catch (_) {}
  }

  Future<Ligue> creer(String nom) async {
    final n = nom.trim();
    if (n.length < 2 || n.length > 40) throw const ErreurLigue('Le nom de la ligue doit faire entre 2 et 40 lettres.');
    final ligue = await _proteger(() async {
      final j = await _client.from('ligues').insert({'nom': n, 'cree_par': monId}).select().single();
      return Ligue.depuisJson(j);
    });
    await _chargerLigues();
    notifyListeners();
    return ligue;
  }

  Future<void> rejoindre(String code) async {
    final c = code.trim().toUpperCase();
    if (c.length != 6) throw const ErreurLigue('Le code d\'invitation fait 6 caractères.');
    await _proteger(() async {
      await _client.rpc('rejoindre_ligue', params: {'code': c});
    });
    await _chargerLigues();
    notifyListeners();
  }

  Future<void> quitter(Ligue l) async {
    await _proteger(() async {
      await _client.from('membres').delete().match({'ligue_id': l.id, 'joueur_id': monId!});
    });
    ligues = ligues.where((x) => x.id != l.id).toList();
    notifyListeners();
  }

  Future<List<Classe>> classement(Ligue l) => _proteger(() async {
        final rep = (await _client.rpc('classement', params: {'ligue': l.id})) as List;
        return rep.cast<Map<String, dynamic>>().map(Classe.depuisJson).toList();
      });

  /// Envoie une séance au serveur. Le plafond de 3 cases par jour y est
  /// appliqué une seconde fois. Renvoie vrai si la séance est bien partie.
  Future<bool> envoyerSeance(Billet b) async {
    if (!inscrit) return false;
    try {
      await _client.from('seances').insert({
        'titre': b.titre,
        'type_carte': b.type,
        'pronostic': b.pronostic,
        if (b.note != null) 'note': b.note,
        if (b.verdict.isNotEmpty) 'verdict': b.verdict,
        'cases': b.cases,
        'vu_le': b.date.toUtc().toIso8601String(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _chargerLigues() async {
    final rep = await _client.from('membres').select('ligues(id, nom, code_invitation)').eq('joueur_id', monId!);
    ligues = rep
        .map((m) => m['ligues'])
        .whereType<Map<String, dynamic>>()
        .map(Ligue.depuisJson)
        .toList()
      ..sort((a, b) => a.nom.compareTo(b.nom));
  }

  Future<T> _proteger<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      if (e.message.contains('Code de ligue inconnu')) throw const ErreurLigue('Ce code ne correspond à aucune ligue.');
      throw ErreurLigue('Le serveur a refusé : ${e.message}');
    } on AuthException catch (e) {
      throw ErreurLigue('Connexion impossible : ${e.message}. Les comptes anonymes sont-ils activés dans Supabase ?');
    } on ErreurLigue {
      rethrow;
    } catch (_) {
      throw const ErreurLigue('Le serveur ne répond pas. Vérifie ta connexion.');
    }
  }
}

class ErreurLigue implements Exception {
  const ErreurLigue(this.message);
  final String message;
  @override
  String toString() => message;
}
