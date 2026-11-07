import 'aura.dart';
import 'cadeaux.dart';

/// Une ligne des films proposés, prête à afficher (R61).
class LigneProposee {
  const LigneProposee({required this.p, required this.titre, required this.etat, required this.cachetee});

  final Proposition p;

  /// Le titre, ou « Film cacheté » tant qu'il l'est pour celui qui regarde.
  final String titre;

  /// « à voir », « vu », « aimé ! », « à ouvrir vendredi »…
  final String etat;
  final bool cachetee;
}

/// Les films proposés (R61) : la liste de chacun (« Pour moi ») et le mur que
/// toute la maison et les ligues voient.
abstract final class FilmsProposes {
  static String _titre(Proposition p) => '${p.titre}${p.annee != null ? ' (${p.annee})' : ''}';

  static String _etat(Proposition p) => p.aimee ? 'aimé !' : p.vu ? 'vu' : 'à voir';

  /// Ce qu'on m'a proposé : les cachetés d'abord (la surprise qui arrive),
  /// puis ce qui reste à voir, puis ce qui est vu ; les plus récents d'abord.
  static List<LigneProposee> pourMoi(Iterable<Proposition> toutes, bool Function(Proposition) estPourMoi, DateTime maintenant) {
    int rang(Proposition p) => p.cachetee(maintenant) ? 0 : p.vu ? 2 : 1;
    final l = toutes.where(estPourMoi).toList()
      ..sort((a, b) => rang(a) != rang(b) ? rang(a).compareTo(rang(b)) : b.creeLe.compareTo(a.creeLe));
    return [
      for (final p in l)
        p.cachetee(maintenant)
            ? LigneProposee(p: p, titre: 'Film cacheté', etat: Cadeaux.quand(p.ouvrirLe!, maintenant), cachetee: true)
            : LigneProposee(p: p, titre: _titre(p), etat: _etat(p), cachetee: false),
    ];
  }

  /// Le mur : tout ce qui circule, du plus récent au plus ancien. Un film
  /// cacheté garde son titre caché pour tout le monde, sauf pour celui qui
  /// l'a envoyé.
  static List<LigneProposee> mur(Iterable<Proposition> toutes, bool Function(Proposition) deMoi, DateTime maintenant, {int limite = 30}) {
    final l = toutes.toList()..sort((a, b) => b.creeLe.compareTo(a.creeLe));
    return [
      for (final p in l.take(limite))
        p.cachetee(maintenant)
            ? LigneProposee(p: p, titre: deMoi(p) ? _titre(p) : 'Film cacheté', etat: 'cacheté, ${Cadeaux.quand(p.ouvrirLe!, maintenant)}', cachetee: true)
            : LigneProposee(p: p, titre: _titre(p), etat: _etat(p), cachetee: false),
    ];
  }
}
