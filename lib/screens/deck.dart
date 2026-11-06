import 'package:flutter/material.dart';

import '../app.dart';
import '../services/apres_seance.dart' show Rarete;
import '../services/collection.dart';
import '../services/deck.dart';
import '../services/etat.dart';
import '../theme/aura_theme.dart';
import '../widgets/animations.dart';
import '../widgets/aura_widgets.dart';

Color couleurDeRarete(Rarete r) => switch (r) {
      Rarete.commune => AuraCouleurs.creme,
      Rarete.rare => AuraCouleurs.caseBleu,
      Rarete.epique => AuraCouleurs.violet,
      Rarete.legendaire => AuraCouleurs.jaune,
    };

/// Mon deck (R49) : le booster du jour, les atouts posés, et la collection
/// série par série (ce qui manque reste en silhouette).
class DeckEcran extends StatefulWidget {
  const DeckEcran({super.key});

  @override
  State<DeckEcran> createState() => _DeckEcranState();
}

class _DeckEcranState extends State<DeckEcran> {
  ({List<Atout> cartes, Set<String> nouveaux, List<Serie> series})? _ouvert;
  bool _ouverture = false;
  String? _message;

  Future<void> _ouvrir(EtatJeu etat) async {
    setState(() => _ouverture = true);
    final r = await etat.ouvrirBooster();
    if (!mounted) return;
    setState(() {
      _ouverture = false;
      _ouvert = r;
      _message = null;
    });
    if (r.series.isNotEmpty) await celebrer(context);
  }

  Future<void> _basculer(EtatJeu etat, Atout a) async {
    final ok = await etat.basculerAtout(a.id);
    if (!mounted) return;
    setState(() => _message = ok ? null : 'Ton deck est plein : retire un atout pour poser celui-là.');
  }

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    final collection = etat.atouts;
    final deck = etat.deck;
    final dispo = etat.boostersDispo();
    final ouvert = _ouvert;
    return Scaffold(
      body: FondTrame(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const EnTeteRetour(titre: 'Mon deck'),
                  const SizedBox(height: 14),
                  PopQuiParle(
                    texte: collection.isEmpty
                        ? 'Un booster gratuit par jour, trois atouts dedans. Pose-les dans ton deck : quand ton film remplit leur défi, ils te rapportent de l\'audace, et les plus rares une case.'
                        : 'Ton deck : ${deck.length} atout${deck.length > 1 ? 's' : ''} sur ${etat.emplacements}. Moi, je n\'ai pas besoin d\'atouts. J\'ai du talent.',
                  ),
                  const SizedBox(height: 16),
                  if (ouvert != null && ouvert.cartes.isNotEmpty) ...[
                    Text('TON BOOSTER', style: AuraTexte.titre(18)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                      for (final (i, a) in ouvert.cartes.indexed)
                        Entree(
                          delai: Duration(milliseconds: 250 * i),
                          child: Retournement(
                            dos: const _Dos(),
                            face: _CarteAtout(atout: a, exemplaires: collection[a.id] ?? 1, nouveau: ouvert.nouveaux.contains(a.id), posee: deck.contains(a.id)),
                          ),
                        ),
                    ]),
                    for (final s in ouvert.series) ...[
                      const SizedBox(height: 10),
                      Panneau(
                        couleur: AuraCouleurs.jaune,
                        child: Text('Série « ${s.nom} » complète ! Nouvel exploit : ${Collection.nomDe(s.exploit)}.', style: AuraTexte.corps(15, poids: FontWeight.w900)),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                  if (dispo > 0)
                    AuraBouton(
                      libelle: _ouverture ? 'Pop déchire l\'emballage…' : 'Ouvrir mon booster${dispo > 1 ? ' ($dispo en réserve)' : ''}',
                      icone: Icons.style_rounded,
                      autofocus: true,
                      onPressed: _ouverture ? null : () => _ouvrir(etat),
                    )
                  else
                    Panneau(
                      couleur: AuraCouleurs.creme,
                      child: Text('Prochain booster demain. Jusqu\'à deux t\'attendent si tu ne passes pas un jour.', style: AuraTexte.corps(14, poids: FontWeight.w900)),
                    ),
                  if (_message != null) ...[
                    const SizedBox(height: 10),
                    Panneau(couleur: AuraCouleurs.jaune, child: Text(_message!, style: AuraTexte.corps(14, poids: FontWeight.w900))),
                  ],
                  const SizedBox(height: 20),
                  Text('TON DECK · ${deck.length}/${etat.emplacements}', style: AuraTexte.titre(18)),
                  const SizedBox(height: 4),
                  Text(
                    'Touche un atout pour le poser ou le retirer. Une 4e place s\'ouvre à ${Deck.grandeCollection} atouts différents. Le deck donne une case au plus par film, et le plafond de 3 cases par jour tient toujours.',
                    style: AuraTexte.corps(13, couleur: AuraCouleurs.creme),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    for (var i = 0; i < etat.emplacements; i++)
                      if (i < deck.length && Deck.de(deck[i]) != null)
                        _CarteAtout(atout: Deck.de(deck[i])!, exemplaires: collection[deck[i]] ?? 1, posee: true, onTap: () => _basculer(etat, Deck.de(deck[i])!))
                      else
                        const _PlaceVide(),
                  ]),
                  for (final s in Serie.values) ...[
                    const SizedBox(height: 22),
                    Text(
                      '${s.nom.toUpperCase()} · ${Deck.dela(s).where((a) => collection.containsKey(a.id)).length}/${Deck.dela(s).length}',
                      style: AuraTexte.titre(18),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      for (final a in Deck.dela(s))
                        collection.containsKey(a.id)
                            ? _CarteAtout(atout: a, exemplaires: collection[a.id]!, posee: deck.contains(a.id), onTap: () => _basculer(etat, a))
                            : _Silhouette(rarete: a.rarete),
                    ]),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _largeur = 150.0;
const _hauteur = 196.0;

class _CarteAtout extends StatelessWidget {
  const _CarteAtout({required this.atout, required this.exemplaires, this.nouveau = false, this.posee = false, this.onTap});

  final Atout atout;
  final int exemplaires;
  final bool nouveau;
  final bool posee;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final niveau = Deck.niveau(exemplaires);
    final carte = SizedBox(
      width: _largeur,
      height: _hauteur,
      child: Panneau(
        couleur: couleurDeRarete(atout.rarete),
        padding: const EdgeInsets.all(10),
        inclinaison: posee ? -0.02 : 0,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${niveau == 3 ? '✦ ' : ''}${atout.rarete.nom.toUpperCase()}', style: AuraTexte.corps(10, poids: FontWeight.w900))),
            if (nouveau) Text('NOUVEAU', style: AuraTexte.corps(10, poids: FontWeight.w900, couleur: AuraCouleurs.rouge)),
          ]),
          const SizedBox(height: 4),
          Text(atout.nom, maxLines: 2, overflow: TextOverflow.ellipsis, style: AuraTexte.titre(16)),
          const SizedBox(height: 4),
          Expanded(child: Text(atout.texte, maxLines: 4, overflow: TextOverflow.ellipsis, style: AuraTexte.corps(12, poids: FontWeight.w700))),
          Text(atout.gain, maxLines: 2, style: AuraTexte.corps(11, poids: FontWeight.w900)),
          Text('Niveau $niveau · ×$exemplaires${posee ? ' · posé' : ''}', style: AuraTexte.corps(10, couleur: AuraCouleurs.texteDoux)),
        ]),
      ),
    );
    if (onTap == null) return carte;
    return Touchable(
      etiquette: '${atout.nom}, ${atout.rarete.nom}. ${atout.texte} ${atout.gain}. ${posee ? 'Dans ton deck : toucher pour le retirer.' : 'Toucher pour le poser.'}',
      onTap: onTap,
      builder: (context, focus, appui) => AnimatedScale(scale: focus ? 1.06 : (appui ? .97 : 1), duration: const Duration(milliseconds: 120), child: carte),
    );
  }
}

class _Dos extends StatelessWidget {
  const _Dos();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: _largeur,
        height: _hauteur,
        child: Panneau(
          couleur: AuraCouleurs.rouge,
          child: Center(child: Text('AURA', style: AuraTexte.titre(26).copyWith(color: AuraCouleurs.creme))),
        ),
      );
}

class _Silhouette extends StatelessWidget {
  const _Silhouette({required this.rarete});
  final Rarete rarete;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: _largeur,
        height: _hauteur,
        child: Opacity(
          opacity: .45,
          child: Panneau(
            couleur: couleurDeRarete(rarete),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('?', style: AuraTexte.titre(44)),
              Text(rarete.nom, style: AuraTexte.corps(12, poids: FontWeight.w900)),
            ]),
          ),
        ),
      );
}

class _PlaceVide extends StatelessWidget {
  const _PlaceVide();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: _largeur,
        height: _hauteur,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AuraTrait.rayon),
            border: Border.all(color: AuraCouleurs.creme, width: AuraTrait.epais),
          ),
          child: Center(child: Text('Place libre', style: AuraTexte.corps(13, poids: FontWeight.w900, couleur: AuraCouleurs.creme))),
        ),
      );
}
