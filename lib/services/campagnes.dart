import '../models/modeles.dart';
import 'etat.dart';
import 'historique.dart';
import 'tirage.dart';

/// Une campagne : une liste de films à voir absolument, jouée comme une
/// suite de cartes. On la termine film après film ; la boucler rapporte un
/// exploit.
class Campagne {
  const Campagne(this.id, this.titre, this.description, this._filtre, {this.paysDifferents = false});

  final String id;
  final String titre;
  final String description;
  final bool Function(Film) _filtre;

  /// Un film par pays (le Tour du monde).
  final bool paysDifferents;

  bool garde(Film f) => _filtre(f);
}

abstract final class Campagnes {
  static const taille = 5;

  static bool _genre(Film f, List<String> g) => f.genres.any((x) => g.contains(x.toLowerCase()));

  static final liste = <Campagne>[
    Campagne('noir', 'Le polar en cinq films', 'Enquêtes, trahisons et nuits sans sommeil.', (f) => _genre(f, ['crime', 'thriller', 'mystery', 'policier', 'mystère'])),
    Campagne('classiques', 'Les grands classiques', 'Cinq films d\'avant 1970 que tout le monde cite.', (f) => (f.annee ?? 3000) < 1970),
    Campagne('monde', 'Le tour du monde', 'Cinq films, cinq pays, sans quitter le canapé.', (f) => f.pays.isNotEmpty, paysDifferents: true),
    Campagne('rire', 'Cinq fous rires', 'Les comédies qui ne vieillissent pas.', (f) => _genre(f, ['comedy', 'comédie'])),
    Campagne('emotion', 'Cinq films qui bouleversent', 'Prévoir les mouchoirs.', (f) => _genre(f, ['drama', 'drame', 'romance'])),
    Campagne('animation', 'L\'animation des maîtres', 'Ghibli, Pixar et les autres.', (f) => _genre(f, ['animation'])),
    Campagne('frissons', 'Cinq nuits blanches', 'Pour ceux qui dorment la lumière allumée.', (f) => _genre(f, ['horror', 'horreur'])),
  ];

  /// Les films de la campagne : les mieux notés qui lui correspondent.
  static List<Film> films(Campagne c, List<Film> catalogue) {
    final bons = catalogue.where((f) => Tirage.assezBon(f) && c.garde(f)).toList()
      ..sort((a, b) {
        final n = (b.note ?? 0).compareTo(a.note ?? 0);
        return n != 0 ? n : a.id.compareTo(b.id);
      });
    if (!c.paysDifferents) return bons.take(taille).toList();
    final pays = <String>{};
    return [
      for (final f in bons)
        if (pays.add(f.pays.first)) f,
    ].take(taille).toList();
  }

  /// Vrai si le film a déjà été vu dans Aura (un billet porte son titre).
  static bool vu(Film f, List<Billet> billets) =>
      billets.any((b) => Historique.normaliser(b.titre) == Historique.normaliser(f.titre));

  static int avancee(List<Film> films, List<Billet> billets) => films.where((f) => vu(f, billets)).length;

  static bool terminee(List<Film> films, List<Billet> billets) => films.length >= 3 && avancee(films, billets) == films.length;

  /// La carte pour jouer le prochain film de la campagne.
  static CarteDefi carte(Campagne c, Film f) => CarteDefi(
        type: TypeCarte.campagne,
        defi: 'Campagne : ${c.titre}',
        indice: c.description,
        cases: 2,
        joker: 'Une campagne : 2 cases.',
        film: f,
        bulleDePop: 'Un film de plus dans ta campagne. Je compte les points.',
      );
}
