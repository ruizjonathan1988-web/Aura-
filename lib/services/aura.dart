/// L'aura (R47) : se proposer des films et des séries entre la maison (les
/// profils d'un même serveur Jellyfin) et les amis de ligue, depuis VJOD ou
/// Aura. Celui qui propose gagne de l'aura quand l'autre regarde (+1), aime
/// (+2 : un cœur ou une note de 4 ou 5), et quand plusieurs aiment le même
/// film (+3 de plus). VJOD calcule l'aura avec exactement la même règle.
abstract final class Aura {
  static const pointsVu = 1;
  static const pointsAime = 2;
  static const bonusPlusieurs = 3;

  /// La clé d'un film : « tmdb:603 » quand on la connaît (la même partout),
  /// sinon « jf:<id Jellyfin> ».
  static String cleFilm({int? tmdb, String? jellyfin}) => tmdb != null ? 'tmdb:$tmdb' : 'jf:${jellyfin ?? ''}';

  /// L'aura de chaque personne qui propose (sa « personne » quand elle en a
  /// une, sinon son joueur).
  static Map<String, int> scores(Iterable<Proposition> propositions) {
    final points = <String, int>{};
    final aimes = <String, Set<String>>{};
    for (final p in propositions) {
      final qui = p.auteur;
      var n = 0;
      if (p.vu) n += pointsVu;
      if (p.aimee) {
        n += pointsAime;
        (aimes['$qui|${p.filmCle}'] ??= <String>{}).add(p.destinataire);
      }
      points[qui] = (points[qui] ?? 0) + n;
    }
    for (final e in aimes.entries) {
      if (e.value.length >= 2) {
        final qui = e.key.substring(0, e.key.lastIndexOf('|'));
        points[qui] = (points[qui] ?? 0) + bonusPlusieurs;
      }
    }
    return points;
  }

  /// Le classement : de la plus forte aura à la plus faible, puis par nom.
  static List<({String qui, String nom, int aura})> classement(Iterable<Proposition> propositions) {
    final s = scores(propositions);
    final noms = <String, String>{for (final p in propositions) p.auteur: p.deNom};
    return [for (final e in s.entries) (qui: e.key, nom: noms[e.key] ?? '?', aura: e.value)]
      ..sort((a, b) => b.aura != a.aura ? b.aura.compareTo(a.aura) : a.nom.compareTo(b.nom));
  }
}

/// Une proposition, telle que la garde le serveur (table « propositions »).
class Proposition {
  const Proposition({
    required this.id,
    required this.de,
    this.dePersonne,
    required this.deNom,
    this.pourPersonne,
    this.pourJoueur,
    required this.pourNom,
    required this.filmCle,
    required this.titre,
    this.annee,
    this.tmdb,
    this.jellyfin,
    this.serie = false,
    this.mot,
    this.vuLe,
    this.aime = false,
    this.note,
    required this.creeLe,
    this.ouvrirLe,
  });

  final String id;
  final String de;
  final String? dePersonne;
  final String deNom;
  final String? pourPersonne;
  final String? pourJoueur;
  final String pourNom;
  final String filmCle;
  final String titre;
  final int? annee;
  final int? tmdb;
  final String? jellyfin;
  final bool serie;
  final String? mot;
  final DateTime? vuLe;
  final bool aime;
  final int? note;
  final DateTime creeLe;

  /// Un film cacheté (R60) : le titre reste caché chez celui qui le reçoit
  /// jusqu'à ce jour-là. Rangé dans « film » pour ne pas toucher à la table.
  final DateTime? ouvrirLe;

  /// Encore cacheté ce jour-là.
  bool cachetee(DateTime maintenant) => ouvrirLe != null && DateTime(maintenant.year, maintenant.month, maintenant.day).isBefore(ouvrirLe!);

  /// Qui gagne l'aura : la personne (tous ses appareils), sinon le joueur.
  String get auteur => dePersonne ?? de;

  /// Qui l'a reçue.
  String get destinataire => pourPersonne ?? pourJoueur ?? '';

  bool get vu => vuLe != null;

  /// Aimée : un cœur, ou une note de 4 ou 5.
  bool get aimee => aime || (note ?? 0) >= 4;

  static Proposition? depuisJson(Map<String, dynamic> j) {
    final film = j['film'];
    if (j['id'] is! String || j['de'] is! String || film is! Map || film['titre'] is! String) return null;
    return Proposition(
      id: j['id'] as String,
      de: j['de'] as String,
      dePersonne: j['de_personne'] as String?,
      deNom: (j['de_nom'] as String?) ?? '?',
      pourPersonne: j['pour_personne'] as String?,
      pourJoueur: j['pour_joueur'] as String?,
      pourNom: (j['pour_nom'] as String?) ?? '?',
      filmCle: (j['film_cle'] as String?) ?? '',
      titre: film['titre'] as String,
      annee: (film['annee'] as num?)?.toInt(),
      tmdb: (film['tmdb'] as num?)?.toInt(),
      jellyfin: film['jellyfin'] as String?,
      serie: film['type'] == 'series',
      mot: j['mot'] as String?,
      vuLe: j['vu_le'] == null ? null : DateTime.tryParse('${j['vu_le']}'),
      aime: j['aime'] == true,
      note: (j['note'] as num?)?.toInt(),
      creeLe: DateTime.tryParse('${j['cree_le']}') ?? DateTime.now(),
      ouvrirLe: film['ouvrir_le'] == null ? null : DateTime.tryParse('${film['ouvrir_le']}'),
    );
  }

  /// Le corps d'une nouvelle proposition, pour l'insertion.
  static Map<String, dynamic> nouvelle({
    String? dePersonne,
    required String deNom,
    String? pourPersonne,
    String? pourJoueur,
    required String pourNom,
    String? maison,
    String? ligueId,
    required String titre,
    int? annee,
    int? tmdb,
    String? jellyfin,
    bool serie = false,
    String? mot,
    DateTime? ouvrirLe,
  }) =>
      {
        if (dePersonne != null) 'de_personne': dePersonne,
        'de_nom': deNom,
        if (pourPersonne != null) 'pour_personne': pourPersonne,
        if (pourJoueur != null) 'pour_joueur': pourJoueur,
        'pour_nom': pourNom,
        if (maison != null) 'maison': maison,
        if (ligueId != null) 'ligue_id': ligueId,
        'film_cle': Aura.cleFilm(tmdb: tmdb, jellyfin: jellyfin),
        'film': {
          'titre': titre,
          if (annee != null) 'annee': annee,
          if (tmdb != null) 'tmdb': tmdb,
          if (jellyfin != null) 'jellyfin': jellyfin,
          'type': serie ? 'series' : 'movie',
          if (ouvrirLe != null) 'ouvrir_le': '${ouvrirLe.year.toString().padLeft(4, '0')}-${ouvrirLe.month.toString().padLeft(2, '0')}-${ouvrirLe.day.toString().padLeft(2, '0')}',
        },
        if (mot != null && mot.trim().isNotEmpty) 'mot': mot.trim(),
      };
}

/// À qui proposer : un profil de la maison (même serveur Jellyfin) ou un ami
/// de ligue. Un ami qui joue aussi depuis VJOD est visé par sa « personne »,
/// pour qu'il voie la proposition sur tous ses appareils.
class Destinataire {
  const Destinataire({required this.nom, this.personne, this.joueur, this.ligueId});

  final String nom;
  final String? personne;
  final String? joueur;
  final String? ligueId;

  bool get maison => ligueId == null;

  /// Les profils de la maison d'abord (un par personne), puis les amis des
  /// ligues qui n'y sont pas déjà ; jamais soi-même.
  static List<Destinataire> liste({
    required List<({String pseudo, String? personne})> maison,
    required List<({String joueur, String pseudo, String? personne, String ligueId})> amis,
    String? moiPersonne,
    required String moiJoueur,
  }) {
    final vus = <String>{if (moiPersonne != null) moiPersonne};
    final joueurs = <String>{moiJoueur};
    final out = <Destinataire>[];
    for (final m in maison) {
      final p = m.personne;
      if (p == null || !vus.add(p)) continue;
      out.add(Destinataire(nom: m.pseudo, personne: p));
    }
    out.sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
    final ligue = <Destinataire>[];
    for (final a in amis) {
      if (!joueurs.add(a.joueur)) continue;
      if (a.personne != null && !vus.add(a.personne!)) continue;
      ligue.add(Destinataire(nom: a.pseudo, personne: a.personne, joueur: a.personne == null ? a.joueur : null, ligueId: a.ligueId));
    }
    ligue.sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
    return [...out, ...ligue];
  }
}

/// Ce que Jellyfin dit d'un titre proposé (son UserData), traduit en ce
/// qu'il faut écrire sur la proposition. Même règle que VJOD : vu dès qu'il
/// a été joué (une série dès un épisode), aimé en favori, pouce levé ou 8/10 ;
/// on n'enlève jamais.
Map<String, dynamic>? majDepuisJellyfin(Map<String, dynamic>? u, Proposition p, DateTime maintenant) {
  if (u == null) return null;
  final fois = (u['PlayCount'] as num?)?.toInt() ?? 0;
  final pourcent = (u['PlayedPercentage'] as num?)?.toDouble() ?? 0;
  final vu = u['Played'] == true || fois > 0 || (u['UnplayedItemCount'] != null && pourcent > 0);
  final aime = u['IsFavorite'] == true || u['Likes'] == true || ((u['Rating'] as num?)?.toDouble() ?? 0) >= 8;
  final maj = <String, dynamic>{
    if ((vu || aime) && !p.vu) 'vu_le': maintenant.toUtc().toIso8601String(),
    if (aime && !p.aime) 'aime': true,
  };
  return maj.isEmpty ? null : maj;
}
