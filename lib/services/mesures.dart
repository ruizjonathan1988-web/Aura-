import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Les mesures de rétention, anonymes : on compte les ouvertures (une par
/// jour), les cartes jouées, les billets validés et les parties. Les
/// événements attendent sur l'appareil tant que le serveur ne répond pas.
class ServiceMesures {
  ServiceMesures(this._client, this._prefs);

  final SupabaseClient _client;
  final SharedPreferences _prefs;

  static const types = {'ouverture', 'carte_jouee', 'billet', 'plan_du_jour', 'duel', 'bluff'};
  static const _cle = 'mesures_en_attente';
  static const maxEnAttente = 200;

  bool _envoi = false;

  /// Ajoute un événement à la file, puis tente l'envoi.
  /// Un type que le serveur refuse est ignoré : un seul suffisait à faire
  /// échouer tout l'envoi, et la file restait bloquée pour toujours.
  Future<void> noter(String type, [Map<String, Object?> donnees = const {}]) async {
    if (!types.contains(type)) return;
    final e = jsonEncode({'type': type, 'donnees': donnees, 'cree_le': DateTime.now().toUtc().toIso8601String()});
    await _prefs.setStringList(_cle, ajouter(enAttente(_prefs), e));
    envoyer();
  }

  /// L'ouverture ne compte qu'une fois par jour.
  Future<void> ouverture() async {
    final maintenant = DateTime.now();
    if (!premiereOuvertureDuJour(_prefs.getString('mesure_ouverture'), maintenant)) return;
    await _prefs.setString('mesure_ouverture', jour(maintenant));
    await noter('ouverture');
  }

  static List<String> enAttente(SharedPreferences prefs) => [...?prefs.getStringList(_cle)];

  static String jour(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static bool premiereOuvertureDuJour(String? derniere, DateTime maintenant) => derniere != jour(maintenant);

  /// Ajoute un événement à la file ; au-delà de [maxEnAttente], les plus
  /// anciens partent (le téléphone ne doit pas se remplir hors ligne).
  static List<String> ajouter(List<String> file, String evenement) {
    final f = [...file, evenement];
    return f.length > maxEnAttente ? f.sublist(f.length - maxEnAttente) : f;
  }

  /// Ce qui peut partir : les événements lisibles d'un type prévu. Les
  /// autres (restés d'une version qui en envoyait d'autres) sont jetés.
  static List<String> envoyables(List<String> file) => [
        for (final e in file)
          if (_typeDe(e) case final t? when types.contains(t)) e,
      ];

  static String? _typeDe(String e) {
    try {
      final j = jsonDecode(e);
      return j is Map && j['type'] is String ? j['type'] as String : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> envoyer() async {
    if (_envoi) return;
    _envoi = true;
    try {
      if (_client.auth.currentUser == null) await _client.auth.signInAnonymously();
      final file = enAttente(_prefs);
      if (file.isEmpty) return;
      final bons = envoyables(file);
      if (bons.isNotEmpty) await _client.from('evenements').insert(bons.map((e) => jsonDecode(e) as Map<String, dynamic>).toList());
      // On ne retire que ce qui est parti (d'autres ont pu arriver entre-temps).
      final actuel = enAttente(_prefs);
      final partis = file.length < actuel.length ? file.length : actuel.length;
      await _prefs.setStringList(_cle, actuel.sublist(partis));
    } catch (_) {
      // Hors ligne ou table absente : on garde la file pour plus tard.
    } finally {
      _envoi = false;
    }
  }
}
