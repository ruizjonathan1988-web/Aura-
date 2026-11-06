import '../models/modeles.dart';
import 'coups.dart';
import 'tirage.dart';

/// Les rivaux robots (R43) : Bobine et Pellicule courent avec toi et Pop sur
/// le plateau du mois, même quand tu joues seul. Comme Pop, tout se calcule
/// à partir de la date : pas de hasard caché, même résultat partout.
enum Rival {
  bobine('Bobine', 'Régulière comme une horloge : une case par jour, repos le dimanche.'),
  pellicule('Pellicule', 'Imprévisible : zéro, une ou deux cases par jour, selon son humeur.');

  const Rival(this.nom, this.caractere);

  final String nom;
  final String caractere;
}

abstract final class Rivaux {
  static int _graine(DateTime d) => d.year * 372 + d.month * 31 + d.day;

  /// La case d'un rival au jour [jour], avant ses retours de crasse.
  static int position(Rival r, DateTime jour) {
    var p = 1;
    for (var j = 1; j <= jour.day; j++) {
      final d = DateTime(jour.year, jour.month, j);
      p += switch (r) {
        Rival.bobine => d.weekday == DateTime.sunday ? 0 : 1,
        Rival.pellicule => (_graine(d) * 7 + 3) % 3,
      };
    }
    return p.clamp(1, Regles.taillePlateau);
  }

  /// La crasse qu'un rival te fait cette semaine : chaque semaine, l'un des
  /// deux, un jour de la semaine fixé par la date. Null si son jour n'est pas
  /// encore arrivé.
  static ({Rival rival, Crasse crasse})? crasseDeLaSemaine(DateTime maintenant) {
    final lundi = DateTime(maintenant.year, maintenant.month, maintenant.day).subtract(Duration(days: maintenant.weekday - 1));
    final g = _graine(lundi);
    final jour = 1 + g % 5; // du lundi au vendredi
    if (maintenant.weekday < jour) return null;
    return (rival: Rival.values[g % Rival.values.length], crasse: Crasse.values[g % Crasse.values.length]);
  }

  /// Une crasse renvoyée fait reculer le rival de 2 cases.
  static const reculRenvoi = 2;
}

/// La figurine du mois (R43), choisie la première semaine : ton pouvoir,
/// l'œuf mystère, ou le Figurant.
enum FigurineDuMois {
  pouvoir('Mon pouvoir', 'Tu gardes le pouvoir de ta figurine.'),
  oeuf('L\'œuf mystère', 'Pas de pouvoir au début. À ta 3e séance du mois, l\'œuf éclot : tu reçois le pouvoir d\'une autre figurine, au hasard.'),
  figurant('Le Figurant', 'Pas de pouvoir à armer. Mais chaque fois qu\'il se passe quelque chose (coup de théâtre, crasse reçue ou envoyée), tu avances d\'une case, une fois par jour.');

  const FigurineDuMois(this.nom, this.explication);

  final String nom;
  final String explication;

  static FigurineDuMois depuisNom(String? n) => values.firstWhere((f) => f.name == n, orElse: () => pouvoir);
}

abstract final class Oeuf {
  static const seancesPourEclore = 3;

  /// Le pouvoir qui sort de l'œuf : celui d'une autre figurine, fixé par le mois.
  static Profil eclosion(Profil moi, DateTime mois) {
    final autres = Profil.values.where((p) => p != moi).toList();
    return autres[(mois.year * 12 + mois.month) % autres.length];
  }
}
