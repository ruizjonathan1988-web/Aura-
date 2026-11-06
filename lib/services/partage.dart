import 'deck.dart' show ContexteAtout;

/// Le Défi de la semaine (R52) : un objectif commun à tout le monde, le même
/// toute la semaine (pas par jour : personne ne regarde un film chaque soir).
/// Réussi une fois : 3 d'audace et un booster.
class DefiSemaine {
  const DefiSemaine(this.id, this.texte, this.condition);
  final String id;
  final String texte;
  final bool Function(ContexteAtout c) condition;
}

abstract final class DefisSemaine {
  static const audace = 3;

  static const _asie = {'Japon', 'Corée du Sud', 'Chine', 'Hong Kong', 'Inde', 'Iran', 'Taïwan', 'Thaïlande', 'Japan', 'South Korea', 'China', 'India'};
  static const _europe = {'Espagne', 'Italie', 'Allemagne', 'Royaume-Uni', 'Belgique', 'Danemark', 'Suède', 'Norvège', 'Pologne', 'Irlande', 'Spain', 'Italy', 'Germany', 'United Kingdom'};

  static final tous = <DefiSemaine>[
    DefiSemaine('avant1970', 'Un film d\'avant 1970.', (c) => (c.billet.annee ?? 3000) < 1970),
    DefiSemaine('asie', 'Un film d\'Asie.', (c) => c.billet.pays.any(_asie.contains)),
    DefiSemaine('coup_de_coeur', 'Mettre 5 à un film.', (c) => c.billet.note == 5),
    DefiSemaine('niveau6', 'Une carte de niveau 6 ou plus.', (c) => (c.billet.niveau ?? 0) >= 6),
    DefiSemaine('deux_soirs', 'Deux films dans la semaine.', (c) {
      DateTime lundi(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
      return c.avant.any((b) => lundi(b.date) == lundi(c.billet.date));
    }),
    DefiSemaine('docu_animation', 'Un documentaire ou un film d\'animation.', (c) => c.genre(const ['Documentary', 'Documentaire', 'Animation'])),
    DefiSemaine('europe', 'Un film européen, hors France.', (c) => c.billet.pays.any(_europe.contains)),
    DefiSemaine('devin', 'Ta note tombe pile sur ton pronostic.', (c) => c.billet.note != null && c.billet.note == c.billet.pronostic),
  ];

  static DateTime lundi(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  static String cle(DateTime d) {
    final l = lundi(d);
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  /// Le défi de la semaine, le même pour tout le monde.
  static DefiSemaine de(DateTime d) {
    final l = lundi(d);
    final semaines = DateTime.utc(l.year, l.month, l.day).difference(DateTime.utc(2026, 1, 5)).inDays ~/ 7;
    return tous[(semaines * 3 + 1) % tous.length];
  }

  static DefiSemaine? parId(String id) => tous.where((d) => d.id == id).firstOrNull;

  static int numeroDeSemaine(DateTime d) {
    final jeudi = DateTime.utc(d.year, d.month, d.day).add(Duration(days: 4 - d.weekday));
    final premier = DateTime.utc(jeudi.year, 1, 1);
    return jeudi.difference(premier).inDays ~/ 7 + 1;
  }
}

/// La soirée telle qu'on la partage : jamais le titre du film.
class SoireePartagee {
  const SoireePartagee({
    required this.date,
    required this.defi,
    required this.pronostic,
    this.note,
    required this.cases,
    required this.position,
    required this.pop,
    this.atouts = const [],
    this.defiSemaine = false,
    this.festival,
  });

  final DateTime date;
  final String defi;
  final int pronostic;
  final int? note;
  final int cases;
  final int position;
  final int pop;
  final List<String> atouts;
  final bool defiSemaine;
  final String? festival;

  Map<String, dynamic> versJson() => {
        'date': date.toIso8601String(),
        'defi': defi,
        'pronostic': pronostic,
        if (note != null) 'note': note,
        'cases': cases,
        'position': position,
        'pop': pop,
        'atouts': atouts,
        'defi_semaine': defiSemaine,
        if (festival != null) 'festival': festival,
      };

  static SoireePartagee? depuisJson(Object? j) {
    if (j is! Map) return null;
    final date = DateTime.tryParse('${j['date']}');
    if (date == null) return null;
    return SoireePartagee(
      date: date,
      defi: '${j['defi'] ?? ''}',
      pronostic: (j['pronostic'] as num?)?.toInt() ?? 3,
      note: (j['note'] as num?)?.toInt(),
      cases: (j['cases'] as num?)?.toInt() ?? 0,
      position: (j['position'] as num?)?.toInt() ?? 1,
      pop: (j['pop'] as num?)?.toInt() ?? 1,
      atouts: [for (final a in (j['atouts'] as List? ?? const [])) '$a'],
      defiSemaine: j['defi_semaine'] == true,
      festival: j['festival'] as String?,
    );
  }

  static String etoiles(int n) => '${'★' * n.clamp(0, 5)}${'☆' * (5 - n.clamp(0, 5))}';

  /// Le texte à envoyer, façon Wordle : on montre le parcours, pas la réponse.
  String texte({String lien = 'https://github.com/ruizjonathan1988-web/Aura-/releases/download/derniere/aura.apk'}) {
    final avance = position - pop;
    return [
      'Aura · semaine ${DefisSemaine.numeroDeSemaine(date)}',
      if (defi.isNotEmpty) '🎬 $defi',
      '🔮 ${etoiles(pronostic)}${note != null ? ' → ${etoiles(note!)}' : ''}${note != null && note == pronostic ? ' pile !' : ''}',
      '${cases > 0 ? '🟨' * cases : '⬛'} +$cases case${cases > 1 ? 's' : ''} · case $position/30',
      avance > 0 ? '🍿 $avance d\'avance sur Pop' : avance < 0 ? '🍿 Pop mène de ${-avance}' : '🍿 À égalité avec Pop',
      if (atouts.isNotEmpty) '🃏 ${atouts.join(' + ')}',
      if (festival != null) '🎪 $festival',
      if (defiSemaine) '🏆 Défi de la semaine réussi',
      'Joue avec moi : $lien',
    ].join('\n');
  }
}
