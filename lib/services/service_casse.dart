import 'package:supabase_flutter/supabase_flutter.dart';

import 'ligues.dart';

/// Le Casse en ligue (R56), migration 0009.
class ServiceCasse {
  ServiceCasse(this.ligues);
  final ServiceLigues ligues;

  SupabaseClient get _db => ligues.client;

  /// Une graine stable pour la ligue et le mois (le hashCode des chaînes ne
  /// l'est pas d'un appareil à l'autre).
  static int graine(String ligueId, String mois) {
    var h = 7;
    for (final c in '$ligueId|$mois'.codeUnits) {
      h = (h * 31 + c) & 0x3fffffff;
    }
    return h;
  }

  /// Les ouvertures : serrure → (qui, pour de vrai ?).
  Future<List<({int serrure, String joueur, bool vraie})>> ouvertures(String ligueId, String mois) async {
    final rep = await _db.from('casse_ouvertures').select('serrure, joueur_id, vraie').eq('ligue_id', ligueId).eq('mois', mois);
    return [for (final r in rep) (serrure: (r['serrure'] as num).toInt(), joueur: '${r['joueur_id']}', vraie: r['vraie'] == true)];
  }

  Future<void> ouvrir(String ligueId, String mois, int serrure, {required bool vraie}) async {
    await _db.from('casse_ouvertures').upsert({'ligue_id': ligueId, 'mois': mois, 'serrure': serrure, 'joueur_id': ligues.monId, 'vraie': vraie}, ignoreDuplicates: true);
  }

  Future<Map<String, String>> votes(String ligueId, String mois) async {
    final rep = await _db.from('casse_votes').select('joueur_id, accuse').eq('ligue_id', ligueId).eq('mois', mois);
    return {for (final r in rep) '${r['joueur_id']}': '${r['accuse']}'};
  }

  Future<void> voter(String ligueId, String mois, String accuse) async {
    await _db.from('casse_votes').upsert({'ligue_id': ligueId, 'mois': mois, 'joueur_id': ligues.monId, 'accuse': accuse});
  }
}
