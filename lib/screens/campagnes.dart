import 'package:flutter/material.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/campagnes.dart';
import '../services/etat.dart';
import '../services/vjod_lien.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';

/// Les campagnes : des listes de films à voir absolument, à terminer film
/// après film. Chaque film joué vaut 2 cases ; boucler une campagne rapporte
/// un exploit.
class CampagnesEcran extends StatefulWidget {
  const CampagnesEcran({super.key});

  @override
  State<CampagnesEcran> createState() => _CampagnesEcranState();
}

class _CampagnesEcranState extends State<CampagnesEcran> {
  Future<List<Film>>? _catalogue;
  String? _ouverte;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalogue ??= PorteeEtat.lire(context).source.catalogue(auHasard: false);
  }

  Future<void> _jouer(EtatJeu etat, Campagne c, Film f) async {
    final carte = Campagnes.carte(c, f);
    await etat.commencerSeance(carte, pronostic: 3);
    if (VjodLien.disponible(f)) {
      final erreur = await VjodLien.ouvrir(f);
      if (erreur != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erreur)));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bonne séance ! Aura te demandera ta note au retour.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    return Scaffold(
      body: FondTrame(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const EnTeteRetour(titre: 'Les campagnes'),
                  const SizedBox(height: 14),
                  const PopQuiParle(texte: 'Des listes de films à voir absolument. Termine-en une, et je te décerne un exploit. Promis, je ne triche pas… sur celles-là.'),
                  const SizedBox(height: 16),
                  FutureBuilder<List<Film>>(
                    future: _catalogue,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) return const PopQuiParle(texte: 'Je prépare les listes…', taille: 60);
                      final catalogue = snap.data ?? const <Film>[];
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        for (final c in Campagnes.liste) ..._campagne(etat, c, Campagnes.films(c, catalogue)),
                      ]);
                    },
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _campagne(EtatJeu etat, Campagne c, List<Film> films) {
    if (films.length < 3) return const [];
    final faits = Campagnes.avancee(films, etat.billets);
    final finie = Campagnes.terminee(films, etat.billets);
    if (finie && !etat.collection.contains('campagne')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => etat.ajouterExploit('campagne'));
    }
    final ouverte = _ouverte == c.id;
    final prochain = films.where((f) => !Campagnes.vu(f, etat.billets)).firstOrNull;
    final enAttente = prochain != null && etat.enCours.any((s) => s.filmId == prochain.id);
    return [
      ChoixLarge(
        libelle: '${c.titre.toUpperCase()} · $faits / ${films.length}${finie ? ' · bouclée !' : ''}\n${c.description}',
        couleur: finie ? AuraCouleurs.vert : (ouverte ? AuraCouleurs.jaune : AuraCouleurs.creme),
        onTap: () => setState(() => _ouverte = ouverte ? null : c.id),
      ),
      if (ouverte) ...[
        const SizedBox(height: 8),
        Panneau(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final f in films)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Icon(Campagnes.vu(f, etat.billets) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: AuraCouleurs.noir),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${f.titre} (${f.annee ?? '?'})', style: AuraTexte.corps(15, poids: FontWeight.w900))),
                ]),
              ),
            const SizedBox(height: 8),
            if (prochain == null)
              Text('Campagne bouclée. Bravo !', style: AuraTexte.corps(15, poids: FontWeight.w900))
            else if (enAttente)
              Text('« ${prochain.titre} » est en cours : donne ta note dans Ce soir après la séance.', style: AuraTexte.corps(14, poids: FontWeight.w900))
            else
              AuraBouton(
                libelle: VjodLien.disponible(prochain) ? 'Lancer « ${prochain.titre} » dans VJOD' : 'Jouer « ${prochain.titre} »',
                autofocus: true,
                onPressed: () => _jouer(etat, c, prochain),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 10),
    ];
  }
}
