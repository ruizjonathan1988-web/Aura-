import 'dart:math';

import '../models/modeles.dart';
import 'tirage.dart';

/// L'Affiche de la semaine : un film choisi par le Programmateur. En solo,
/// c'est Pop qui programme ; en ligue, ce sera chacun son tour.
class Affiche {
  const Affiche({required this.film, required this.semaine, required this.question});

  final Film film;

  /// Le lundi de la semaine, sous la forme 2026-11-02 : sert de clé.
  final String semaine;

  /// La question du Curseur, selon le genre du film.
  final String question;

  static DateTime lundiDe(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  static Affiche? de(DateTime jour, List<Film> catalogue, String Function(DateTime) cle) {
    final bons = catalogue.where((f) => Tirage.assezBon(f) && !f.dejaVu).toList()..sort((a, b) => a.id.compareTo(b.id));
    if (bons.isEmpty) return null;
    final lundi = lundiDe(jour);
    final film = bons[Random(lundi.millisecondsSinceEpoch ~/ 86400000).nextInt(bons.length)];
    return Affiche(film: film, semaine: cle(lundi), question: questionPour(film));
  }

  static String questionPour(Film f) {
    final g = f.genres.map((x) => x.toLowerCase()).toSet();
    bool a(List<String> l) => l.any(g.contains);
    if (a(['horror', 'horreur', 'thriller', 'mystery', 'mystère'])) return 'À quel point ça fait peur ?';
    if (a(['comedy', 'comédie'])) return 'À quel point ça fait rire ?';
    if (a(['drama', 'drame', 'romance'])) return 'À quel point ça bouleverse ?';
    if (a(['documentary', 'documentaire', 'history', 'histoire', 'war', 'guerre'])) return 'À quel point ça fait réfléchir ?';
    return 'À quel point ça fait voyager ?';
  }
}
