import 'carte_genres.dart';
import 'collection.dart';
import 'etat.dart';

/// Le générique de fin du mois : les films de la saison dans l'ordre
/// d'apparition, les chiffres, le duel contre Pop. Il défile à l'écran et se
/// partage en texte.
abstract final class Generique {
  static List<String> lignes({
    required DateTime mois,
    required List<Billet> billets,
    required int position,
    required int positionDePop,
    bool terminee = false,
  }) {
    final duMois = billets.where((b) => b.date.year == mois.year && b.date.month == mois.month).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final nom = '${Collection.mois[mois.month - 1]} ${mois.year}';
    final fin = DateTime(mois.year, mois.month + 1, 0, 23, 59);
    final carte = CarteDesGenres.de(fin, duMois);
    final verdict = duMois.where((b) => b.verdict.isNotEmpty).toList()
      ..sort((a, b) => (b.note ?? 0).compareTo(a.note ?? 0));
    final cases = duMois.fold<int>(0, (s, b) => s + b.cases);
    final devant = position > positionDePop;
    return [
      'AURA PRÉSENTE',
      'La saison de $nom',
      '',
      if (duMois.isEmpty) 'Un mois sans film… La prochaine saison sera la bonne.' else 'Avec, dans l\'ordre d\'apparition :',
      for (final b in duMois) b.titre,
      '',
      '${duMois.length} séance${duMois.length > 1 ? 's' : ''} · $cases case${cases > 1 ? 's' : ''} · ${carte.regionsDuJoueur} région${carte.regionsDuJoueur > 1 ? 's' : ''} de la carte',
      if (verdict.isNotEmpty) 'Meilleur Verdict : « ${verdict.first.verdict} »',
      '',
      if (terminee)
        (devant ? 'Champion de la saison : toi, case $position contre $positionDePop pour Pop !' : 'Pop termine devant, case $positionDePop contre $position. Revanche le mois prochain !')
      else
        (devant ? 'Pour l\'instant, tu mènes : case $position contre $positionDePop.' : 'Pour l\'instant, Pop mène : case $positionDePop contre $position.'),
      '',
      'Programmation : Pop',
      'Un jeu VJOD',
    ];
  }

  /// Le texte à partager (sans les lignes vides).
  static String partage(List<String> lignes) => lignes.where((l) => l.isNotEmpty).join('\n');
}
