import '../models/modeles.dart';
import 'soiree.dart';

/// Un Cadeau cacheté : un film offert par un ami, à ouvrir tel jour.
class Cadeau {
  const Cadeau({
    required this.id,
    required this.de,
    required this.pour,
    required this.film,
    required this.ouvrirLe,
    this.mot,
    this.ouvert = false,
    this.note,
  });

  final String id;
  final String de;
  final String pour;
  final Film film;
  final DateTime ouvrirLe;
  final String? mot;
  final bool ouvert;
  final int? note;

  /// On peut l'ouvrir à partir du jour prévu.
  bool ouvrable(DateTime maintenant) => !DateTime(maintenant.year, maintenant.month, maintenant.day).isBefore(ouvrirLe);

  static Cadeau depuisJson(Map<String, dynamic> j) => Cadeau(
        id: j['id'] as String,
        de: j['de'] as String,
        pour: j['pour'] as String,
        film: PartieSoiree.filmDepuisJson((j['film'] as Map).cast<String, dynamic>()),
        ouvrirLe: DateTime.parse(j['ouvrir_le'] as String),
        mot: j['mot'] as String?,
        ouvert: (j['ouvert'] as bool?) ?? false,
        note: (j['note'] as num?)?.toInt(),
      );
}

abstract final class Cadeaux {
  static const jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

  /// Les dates d'ouverture proposées : ce soir, demain, et les prochains
  /// vendredi, samedi et dimanche.
  static List<(String, DateTime)> dates(DateTime maintenant) {
    final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
    final liste = <(String, DateTime)>[('Ce soir', aujourdhui), ('Demain', aujourdhui.add(const Duration(days: 1)))];
    for (final jour in [DateTime.friday, DateTime.saturday, DateTime.sunday]) {
      var d = aujourdhui;
      while (d.weekday != jour) {
        d = d.add(const Duration(days: 1));
      }
      if (!liste.any((x) => x.$2 == d)) liste.add(('${jours[jour - 1][0].toUpperCase()}${jours[jour - 1].substring(1)}', d));
    }
    return liste;
  }

  /// « à ouvrir vendredi », « à ouvrir ce soir », « à ouvrir le 14 ».
  static String quand(DateTime ouvrirLe, DateTime maintenant) {
    final a = DateTime(maintenant.year, maintenant.month, maintenant.day);
    final ecart = ouvrirLe.difference(a).inDays;
    if (ecart <= 0) return 'à ouvrir dès maintenant';
    if (ecart == 1) return 'à ouvrir demain';
    if (ecart < 7) return 'à ouvrir ${jours[ouvrirLe.weekday - 1]}';
    return 'à ouvrir le ${ouvrirLe.day}';
  }

  /// Le Flair de chacun : la part de ses cadeaux notés 4 ou 5 (null s'il
  /// n'a encore aucun cadeau noté).
  static Map<String, (int, int)> flair(List<Cadeau> cadeaux) {
    final f = <String, (int, int)>{};
    for (final c in cadeaux.where((c) => c.note != null)) {
      final (plu, total) = f[c.de] ?? (0, 0);
      f[c.de] = (plu + (c.note! >= 4 ? 1 : 0), total + 1);
    }
    return f;
  }

  static String pourcentage((int, int) f) => '${(100 * f.$1 / f.$2).round()} %';

  /// La carte pour jouer un cadeau ouvert.
  static CarteDefi carte(Cadeau c, String deQui) => CarteDefi(
        type: TypeCarte.cadeau,
        defi: 'Cadeau de $deQui',
        indice: c.mot ?? '',
        cases: 2,
        joker: 'Un cadeau : 2 cases.',
        film: c.film,
        bulleDePop: '$deQui a pensé à toi. Moi aussi, mais moins.',
      );
}
