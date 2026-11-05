import 'etat.dart';

/// Les régions de la carte des genres. Un film peut compter pour plusieurs.
enum Region {
  polar('Polar', ['crime', 'thriller', 'mystery', 'policier', 'mystère']),
  comedie('Comédie', ['comedy', 'comédie']),
  drame('Drame', ['drama', 'romance', 'drame']),
  evasion('Évasion', ['adventure', 'fantasy', 'science fiction', 'aventure', 'fantastique', 'science-fiction']),
  animation('Animation', ['animation']),
  frissons('Frissons', ['horror', 'horreur']),
  classiques('Classiques', []),
  ailleurs('Cinéma d\'ailleurs', []);

  const Region(this.libelle, this.genres);
  final String libelle;
  final List<String> genres;

  static const _paysProches = {'france', 'états-unis', 'etats-unis', 'united states of america', 'usa', 'us'};

  bool contient(Billet b) => switch (this) {
        Region.classiques => b.annee != null && b.annee! < 1980,
        Region.ailleurs => b.pays.isNotEmpty && b.pays.every((p) => !_paysProches.contains(p.toLowerCase())),
        _ => b.genres.any((g) => genres.contains(g.toLowerCase())),
      };
}

enum Proprio { libre, joueur, pop }

/// La carte des genres du mois, en solo contre Pop.
///
/// - Une région est à toi dès que tu y valides une séance.
/// - Chaque lundi, Pop vise une région libre. Si tu n'y as rien vu avant
///   dimanche soir, il la prend.
/// - Une région prise par Pop se reprend en y regardant un film.
/// - Chaque région tenue par Pop lui vaut une case d'avance.
///
/// Tout se recalcule à partir des billets : rien de caché, même résultat
/// sur la télé et le téléphone.
class CarteDesGenres {
  CarteDesGenres._(this.proprios, this.cible, this.prisesCetteSemaine);

  final Map<Region, Proprio> proprios;

  /// La région visée par Pop cette semaine (null s'il n'y a rien à prendre).
  final Region? cible;

  /// Les régions que Pop a prises au dernier dimanche écoulé.
  final List<Region> prisesCetteSemaine;

  int get regionsDePop => proprios.values.where((p) => p == Proprio.pop).length;
  int get regionsDuJoueur => proprios.values.where((p) => p == Proprio.joueur).length;

  static DateTime _lundiDe(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  static int _numero(DateTime lundi) => DateTime.utc(lundi.year, lundi.month, lundi.day).millisecondsSinceEpoch ~/ 86400000 ~/ 7;

  static CarteDesGenres de(DateTime maintenant, List<Billet> billets) {
    final debutMois = DateTime(maintenant.year, maintenant.month, 1);
    final duMois = billets.where((b) => !b.date.isBefore(debutMois) && !b.date.isAfter(maintenant)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final proprios = {for (final r in Region.values) r: Proprio.libre};
    void appliquer(Iterable<Billet> lot) {
      for (final b in lot) {
        for (final r in Region.values) {
          if (r.contient(b)) proprios[r] = Proprio.joueur;
        }
      }
    }

    // Les jours avant le premier lundi du mois : pas encore de cible.
    var lundi = _lundiDe(debutMois);
    if (lundi.isBefore(debutMois)) lundi = DateTime(lundi.year, lundi.month, lundi.day + 7);
    appliquer(duMois.where((b) => b.date.isBefore(lundi)));

    Region? cible;
    var prises = <Region>[];
    while (!lundi.isAfter(maintenant)) {
      final fin = DateTime(lundi.year, lundi.month, lundi.day + 7);
      final libres = Region.values.where((r) => proprios[r] == Proprio.libre).toList();
      cible = libres.isEmpty ? null : libres[_numero(lundi) % libres.length];
      final semaine = duMois.where((b) => !b.date.isBefore(lundi) && b.date.isBefore(fin)).toList();
      appliquer(semaine);
      final finie = !fin.isAfter(maintenant);
      if (finie) {
        prises = [];
        if (cible != null && proprios[cible] == Proprio.libre) {
          proprios[cible] = Proprio.pop;
          prises.add(cible);
        }
        cible = null;
      }
      lundi = fin;
    }
    return CarteDesGenres._(proprios, cible, prises);
  }
}
