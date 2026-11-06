import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'config.dart';
import 'rappels.dart';

/// Les nouvelles des amis (R54), sans serveur de notifications : sur
/// Android, Aura jette un œil au serveur des ligues environ toutes les
/// heures, appli fermée, et prévient quand un ami te propose un film,
/// t'offre un cadeau ou te fait une crasse. Coupable dans les Réglages.
abstract final class Veille {
  static const tache = 'aura_veille';
  static const cleDepuis = 'veille_depuis';
  static const cleActive = 'avis_amis';
  static const clePersonne = 'aura_personne';

  /// Ce qu'il faut dire, à partir de ce qui est arrivé depuis la dernière
  /// fois. Une seule notification : le détail s'il n'y a qu'une nouvelle,
  /// le compte sinon.
  static (String, String)? message({
    required List<Map<String, dynamic>> propositions,
    required List<Map<String, dynamic>> cadeaux,
    required List<Map<String, dynamic>> crasses,
    required Map<String, String> pseudos,
  }) {
    final lignes = <(String, String)>[
      for (final p in propositions)
        (
          '${p['de_nom'] ?? 'Un ami'} te propose « ${(p['film'] as Map?)?['titre'] ?? 'un film'} »',
          (p['mot'] as String?) != null ? '« ${p['mot']} » Pop : il a bon goût, pour une fois.' : 'Pop : il a bon goût, pour une fois. Regarde-le, son aura en dépend.',
        ),
      for (final c in cadeaux)
        ('Un cadeau cacheté de ${pseudos[c['de']] ?? 'un ami'}', 'Il s\'ouvrira le jour prévu. Pas avant : je surveille.'),
      for (final c in crasses)
        ('${pseudos[c['de']] ?? 'Un ami'} t\'a fait une crasse !', 'Ouvre Aura pour l\'encaisser, la parer… ou la lui renvoyer.'),
    ];
    if (lignes.isEmpty) return null;
    if (lignes.length == 1) return lignes.first;
    return ('${lignes.length} nouvelles de tes amis', lignes.map((l) => l.$1).join(' · '));
  }

  /// Lancée au démarrage de l'appli : une vérification par heure environ.
  static Future<void> demarrer() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || !Config.serveur) return;
    try {
      await Workmanager().initialize(veilleDesAmis);
      await Workmanager().registerPeriodicTask(
        tache,
        tache,
        frequency: const Duration(hours: 1),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {
      // Pas de tâche de fond sur cet appareil : les nouvelles attendront l'ouverture.
    }
  }

  /// Une vérification : ce qui est arrivé depuis la dernière fois.
  static Future<void> verifier() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(cleActive) ?? true)) return;
    try {
      await Supabase.initialize(url: Config.supabaseUrl, anonKey: Config.supabaseCle);
    } catch (_) {
      // Déjà fait dans ce processus.
    }
    final db = Supabase.instance.client;
    final moi = db.auth.currentUser?.id;
    if (moi == null) return;
    final maintenant = DateTime.now().toUtc();
    final depuis = DateTime.tryParse(prefs.getString(cleDepuis) ?? '') ?? maintenant.subtract(const Duration(hours: 1));
    final personne = prefs.getString(clePersonne);
    final apres = depuis.toIso8601String();
    final propositions = await db
        .from('propositions')
        .select()
        .gt('cree_le', apres)
        .or(personne == null ? 'pour_joueur.eq.$moi' : 'pour_joueur.eq.$moi,pour_personne.eq.$personne');
    final cadeaux = await db.from('cadeaux').select('de').eq('pour', moi).gt('cree_le', apres);
    final crasses = await db.from('crasses').select('de').eq('pour', moi).gt('cree_le', apres);
    final ids = {for (final c in [...cadeaux, ...crasses]) '${c['de']}'};
    final pseudos = <String, String>{};
    if (ids.isNotEmpty) {
      for (final j in await db.from('joueurs').select('id, pseudo').inFilter('id', ids.toList())) {
        pseudos['${j['id']}'] = '${j['pseudo']}';
      }
    }
    await prefs.setString(cleDepuis, maintenant.toIso8601String());
    final m = message(propositions: propositions, cadeaux: cadeaux, crasses: crasses, pseudos: pseudos);
    if (m == null) return;
    await Rappels.initialiser();
    await Rappels.nouvelleDesAmis(m.$1, m.$2);
  }
}

/// Le point d'entrée de la tâche de fond (Android).
@pragma('vm:entry-point')
void veilleDesAmis() {
  Workmanager().executeTask((tache, donnees) async {
    DartPluginRegistrant.ensureInitialized();
    try {
      await Veille.verifier();
    } catch (_) {}
    return true;
  });
}
