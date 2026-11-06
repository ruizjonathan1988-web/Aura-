import 'package:flutter/material.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/carte_genres.dart';
import '../services/coups.dart';
import '../services/etat.dart';
import '../services/pop.dart';
import '../services/retournements.dart';
import '../services/tirage.dart';
import '../theme/aura_theme.dart';
import '../widgets/animations.dart';
import '../widgets/aura_widgets.dart';
import 'generique.dart';

enum TypeCase {
  depart('Départ', AuraCouleurs.caseBleu),
  defi('Défi', AuraCouleurs.caseOrange),
  bluff('Bluff', AuraCouleurs.caseRose),
  curseur('Curseur', AuraCouleurs.caseVert),
  duel('Duel', AuraCouleurs.caseBleu),
  faussaire('Faussaire', AuraCouleurs.violet),
  cadeau('Cadeau', AuraCouleurs.creme),
  coup('Coup de théâtre', AuraCouleurs.jaune),
  etape('Étape bonus', AuraCouleurs.caseRouge),
  finale('Arrivée', AuraCouleurs.jaune);

  const TypeCase(this.libelle, this.couleur);
  final String libelle;
  final Color couleur;
}

/// Le circuit de la saison : 30 cases autour d'un panneau illustré.
abstract final class Circuit {
  static const _suite = [
    TypeCase.defi, TypeCase.bluff, TypeCase.defi, TypeCase.curseur, TypeCase.coup, TypeCase.defi,
    TypeCase.cadeau, TypeCase.duel, TypeCase.defi, TypeCase.faussaire,
  ];

  static TypeCase typeDe(int numero) {
    if (numero == 1) return TypeCase.depart;
    if (numero == Regles.taillePlateau) return TypeCase.finale;
    if (numero % 5 == 0) return TypeCase.etape;
    return _suite[numero % _suite.length];
  }

  /// Ligne et colonne (à partir de 0) de chaque case, en faisant le tour
  /// d'une grille de 6 colonnes sur 11 lignes.
  static List<(int, int)> positions() {
    final p = <(int, int)>[];
    for (var c = 0; c < 6; c++) {
      p.add((0, c));
    }
    for (var r = 1; r < 11; r++) {
      p.add((r, 5));
    }
    for (var c = 4; c >= 0; c--) {
      p.add((10, c));
    }
    for (var r = 9; r >= 1; r--) {
      p.add((r, 0));
    }
    return p;
  }
}

class PlateauEcran extends StatelessWidget {
  const PlateauEcran({super.key});

  static const _mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

  /// Le saut du pion ne se joue qu'une fois, à la première visite du plateau
  /// après l'avancée.
  static bool _consommerSaut(EtatJeu etat) {
    final saute = etat.pionVientDAvancer;
    etat.pionVientDAvancer = false;
    return saute;
  }

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    final maintenant = DateTime.now();
    final pop = etat.positionDePop;
    final pari = Pop.pariDe(maintenant);
    final pariReleve = pari.releve(Pop.semaine(Pop.lundiDe(maintenant), maintenant, etat.billets));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TitreCartoon('Le plateau de ${_mois[maintenant.month - 1]}', taille: 38),
              const SizedBox(height: 8),
              Text('Pas de dé : on avance en regardant des films, 3 cases par jour au maximum. Pop avance d\'une case par jour et triche un peu. À toi de le dépasser !',
                  style: AuraTexte.corps(15)),
              if (etat.serie > 0) ...[
                const SizedBox(height: 10),
                Panneau(
                  couleur: AuraCouleurs.jaune,
                  inclinaison: -0.012,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    'Ta série : ${etat.serie} semaine${etat.serie > 1 ? 's' : ''} de cinéma. Une semaine sans film ne la casse pas.',
                    style: AuraTexte.corps(14, poids: FontWeight.w900),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              PopQuiParle(texte: etat.motDePop ?? Pop.surPlateau(joueur: etat.position, pop: pop, jour: maintenant), taille: 70),
              const SizedBox(height: 16),
              _Circuit(joueur: etat.profil, positionJoueur: etat.position, positionPop: pop, saute: _consommerSaut(etat)),
              if (etat.sisypheProposable) ...[
                const SizedBox(height: 14),
                Panneau(
                  couleur: AuraCouleurs.jaune,
                  inclinaison: -0.012,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('LE PARI DE SISYPHE', style: AuraTexte.titre(16)),
                    const SizedBox(height: 6),
                    Text('${Retournements.avanceSisyphe} cases d\'avance tout de suite. Mais si tu abandonnes un seul film ce mois-ci, retour à la case 1.',
                        style: AuraTexte.corps(14, poids: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('Proposé la première semaine du mois seulement.', style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      Pastille(libelle: 'Je tente !', choisie: false, onTap: etat.accepterSisyphe),
                      Pastille(libelle: 'Non merci', choisie: false, onTap: etat.refuserSisyphe),
                    ]),
                  ]),
                ),
              ],
              if (etat.sisypheActif) ...[
                const SizedBox(height: 10),
                Panneau(
                  couleur: AuraCouleurs.rose,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text('Pari de Sisyphe en cours : n\'abandonne aucun film ce mois-ci.', style: AuraTexte.corps(14, poids: FontWeight.w900)),
                ),
              ],
              if (etat.coupEnAttente != null) ...[
                const SizedBox(height: 14),
                _CoupDeTheatre(etat: etat, pop: pop),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (final t in [TypeCase.defi, TypeCase.bluff, TypeCase.curseur, TypeCase.faussaire, TypeCase.duel, TypeCase.cadeau, TypeCase.coup, TypeCase.etape])
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 14, height: 14, decoration: BoxDecoration(color: t.couleur, borderRadius: BorderRadius.circular(4), border: Border.all(width: 2))),
                      const SizedBox(width: 5),
                      Text(t.libelle, style: AuraTexte.corps(13, poids: FontWeight.w900)),
                    ]),
                ],
              ),
              const SizedBox(height: 18),
              Panneau(
                couleur: pariReleve ? AuraCouleurs.vert : AuraCouleurs.jaune,
                inclinaison: -0.015,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('LE PARI DE POP', style: AuraTexte.titre(16)),
                  const SizedBox(height: 4),
                  Text('« ${pari.texte} »', style: AuraTexte.corps(15, poids: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(
                    pariReleve
                        ? 'Pari relevé ! Pop recule de ${Pop.recul} cases.'
                        : 'Pour lui donner tort : ${pari.defi.toLowerCase()} avant dimanche soir. Il reculera alors de ${Pop.recul} cases.',
                    style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              _CarteDesGenresVue(carte: etat.carte, profil: etat.profil),
              if (etat.carte.cible != null && etat.bouclierCetteSemaine) ...[
                const SizedBox(height: 10),
                Panneau(
                  couleur: AuraCouleurs.vert,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text('Bouclier posé : Pop ne prendra pas la région ${etat.carte.cible!.libelle} cette semaine.', style: AuraTexte.corps(14, poids: FontWeight.w900)),
                ),
              ] else if (etat.carte.cible != null && etat.bouclierDispo) ...[
                const SizedBox(height: 10),
                AuraBouton(
                  libelle: 'Joker Bouclier : protéger ${etat.carte.cible!.libelle}',
                  icone: Icons.shield_rounded,
                  principal: false,
                  onPressed: etat.poserBouclier,
                ),
              ],
              if (etat.volteFaceDispo) ...[
                const SizedBox(height: 10),
                AuraBouton(
                  libelle: 'Joker Volte-face : prendre la place de Pop (1 par mois)',
                  icone: Icons.swap_horiz_rounded,
                  principal: false,
                  onPressed: etat.volteFace,
                ),
              ],
              if (etat.journal.isNotEmpty) ...[
                const SizedBox(height: 20),
                const TitreCartoon('Le journal du plateau', taille: 24, inclinaison: 0),
                const SizedBox(height: 10),
                Panneau(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final l in etat.journal.take(8))
                      Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $l', style: AuraTexte.corps(14))),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              AuraBouton(
                libelle: 'Le générique de ${_mois[maintenant.month - 1]}',
                icone: Icons.movie_creation_rounded,
                principal: false,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GeneriqueEcran(mois: DateTime(maintenant.year, maintenant.month)))),
              ),
              const SizedBox(height: 20),
              const TitreCartoon('Tes derniers billets', taille: 24, inclinaison: 0),
              const SizedBox(height: 10),
              if (etat.billets.isEmpty)
                Panneau(child: Text('Aucun billet pour l\'instant. Joue une carte ce soir pour lancer ta saison.', style: AuraTexte.corps(14)))
              else
                for (final b in etat.billets.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Panneau(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(b.titre, style: AuraTexte.corps(15, poids: FontWeight.w900)),
                            Text(b.verdict.isNotEmpty ? '« ${b.verdict} »' : 'Carte ${b.type} · pronostic ${b.pronostic}/5${b.note != null ? ' · note ${b.note}/5' : ''}${b.auto ? ' · validé automatiquement' : ''}',
                                style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
                          ]),
                        ),
                        Text('+${b.cases}', style: AuraTexte.titre(22)),
                      ]),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Circuit extends StatelessWidget {
  const _Circuit({required this.joueur, required this.positionJoueur, required this.positionPop, this.saute = false});

  final Profil joueur;
  final bool saute;
  final int positionJoueur;
  final int positionPop;

  @override
  Widget build(BuildContext context) {
    final cases = Circuit.positions();
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: AuraCouleurs.plateau,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(width: 3),
        boxShadow: AuraTrait.ombre(5),
      ),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AuraCouleurs.creme, width: 2.5),
        ),
        child: LayoutBuilder(builder: (context, c) {
          const gap = 3.0;
          const h = 44.0;
          final w = (c.maxWidth - gap * 5) / 6;
          return SizedBox(
            height: h * 11 + gap * 10,
            child: Stack(
              children: [
                for (var i = 0; i < cases.length; i++)
                  Positioned(
                    left: cases[i].$2 * (w + gap),
                    top: cases[i].$1 * (h + gap),
                    width: w,
                    height: h,
                    child: _Case(
                      numero: i + 1,
                      joueur: i + 1 == positionJoueur ? joueur : null,
                      pop: i + 1 == positionPop,
                      saute: saute && i + 1 == positionJoueur,
                    ),
                  ),
                Positioned(
                  left: w + gap + 5,
                  top: h + gap + 5,
                  width: 4 * w + 3 * gap - 10,
                  height: 9 * h + 8 * gap - 10,
                  child: _PanneauCentral(joueur: joueur, positionJoueur: positionJoueur, positionPop: positionPop),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _Case extends StatelessWidget {
  const _Case({required this.numero, this.joueur, this.pop = false, this.saute = false});
  final int numero;
  final Profil? joueur;
  final bool pop;

  /// Le pion du joueur vient d'arriver ici : trois petits sauts.
  final bool saute;

  @override
  Widget build(BuildContext context) {
    final type = Circuit.typeDe(numero);
    final marque = numero == 1 ? 'GO' : numero == Regles.taillePlateau ? 'FIN' : numero % 5 == 0 ? '$numero' : '';
    return Semantics(
      label: 'Case $numero, ${type.libelle}${joueur != null ? ', ton pion' : ''}${pop ? ', Pop' : ''}',
      child: Container(
        decoration: BoxDecoration(
          color: type.couleur,
          borderRadius: BorderRadius.circular(4),
          boxShadow: joueur != null ? const [BoxShadow(color: AuraCouleurs.creme, spreadRadius: 3)] : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (marque.isNotEmpty) Center(child: TitreCartoon(marque, taille: 17, inclinaison: 0)),
            Positioned(
              left: 2,
              bottom: 1,
              child: Row(children: [
                if (pop) const Figurine.pop(hauteur: 32),
                if (joueur != null)
                  Transform.translate(
                    offset: Offset(pop ? -10 : 0, 0),
                    child: Rebond(declencheur: numero, sauts: 3, hauteur: 12, auDemarrage: saute, child: Figurine.profil(joueur!, hauteur: 32)),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanneauCentral extends StatelessWidget {
  const _PanneauCentral({required this.joueur, required this.positionJoueur, required this.positionPop});
  final Profil joueur;
  final int positionJoueur;
  final int positionPop;

  @override
  Widget build(BuildContext context) {
    final enTete = positionJoueur >= positionPop;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AuraCouleurs.creme, width: 2.5),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Marche(rang: enTete ? '1er' : '2e', hauteur: enTete ? 46 : 32, figurine: Figurine.profil(joueur, hauteur: 48)),
              const SizedBox(width: 4),
              _Marche(rang: enTete ? '2e' : '1er', hauteur: enTete ? 32 : 46, figurine: const Figurine.pop(hauteur: 48)),
            ],
          ),
          Column(children: [
            const TitreCartoon('Saison', taille: 34, inclinaison: -0.06),
            const SizedBox(height: 6),
            Text(enTete ? 'Tu es devant Pop !' : 'Pop a ${positionPop - positionJoueur} case${positionPop - positionJoueur > 1 ? 's' : ''} d\'avance',
                textAlign: TextAlign.center, style: AuraTexte.corps(14, poids: FontWeight.w900, couleur: AuraCouleurs.creme)),
          ]),
          Image.asset('assets/marque/vjod-transparent.png', height: 26, semanticLabel: 'VJOD'),
        ],
      ),
    );
  }
}

class _Marche extends StatelessWidget {
  const _Marche({required this.rang, required this.hauteur, required this.figurine});
  final String rang;
  final double hauteur;
  final Widget figurine;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      figurine,
      const SizedBox(height: 3),
      Container(
        width: 48,
        height: hauteur,
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 3),
        decoration: BoxDecoration(
          color: rang == '1er' ? AuraCouleurs.jaune : AuraCouleurs.caseOrange,
          border: Border.all(width: 2),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
        child: Text(rang, style: AuraTexte.titre(14)),
      ),
    ]);
  }
}

/// La carte des genres : à qui est chaque région ce mois-ci, et ce que Pop vise.
class _CarteDesGenresVue extends StatelessWidget {
  const _CarteDesGenresVue({required this.carte, required this.profil});
  final CarteDesGenres carte;
  final Profil profil;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreCartoon('La carte des genres', taille: 24, inclinaison: 0),
        const SizedBox(height: 10),
        PopQuiParle(texte: Pop.surLaCarte(carte, bouclier: PorteeEtat.of(context).bouclierCetteSemaine), taille: 60),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in Region.values) _Region(region: r, proprio: carte.proprios[r]!, visee: carte.cible == r, profil: profil),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Regarde un film d\'une région pour la prendre. Chaque région tenue par Pop lui vaut une case d\'avance : reprends-la en y regardant un film.',
          style: AuraTexte.corps(13, couleur: AuraCouleurs.creme),
        ),
      ],
    );
  }
}

class _Region extends StatelessWidget {
  const _Region({required this.region, required this.proprio, required this.visee, required this.profil});
  final Region region;
  final Proprio proprio;
  final bool visee;
  final Profil profil;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (proprio) {
      Proprio.joueur => AuraCouleurs.jaune,
      Proprio.pop => AuraCouleurs.caseRouge,
      Proprio.libre => AuraCouleurs.creme,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: couleur,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(width: visee ? 3.5 : 2.5),
        boxShadow: AuraTrait.ombre(visee ? 4 : 2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(region.libelle, style: AuraTexte.corps(14, poids: FontWeight.w900)),
        const SizedBox(width: 6),
        switch (proprio) {
          Proprio.joueur => Figurine.profil(profil, hauteur: 26),
          Proprio.pop => const Figurine.pop(hauteur: 26),
          Proprio.libre => Text(visee ? 'VISÉE' : 'libre', style: visee ? AuraTexte.titre(13) : AuraTexte.corps(12, couleur: AuraCouleurs.texteDoux)),
        },
      ]),
    );
  }
}

/// Case Coup de théâtre (R40) : le coup du sort, et sa parade s'il fait du tort.
class _CoupDeTheatre extends StatelessWidget {
  const _CoupDeTheatre({required this.etat, required this.pop});

  final EtatJeu etat;
  final int pop;

  @override
  Widget build(BuildContext context) {
    final c = etat.coupEnAttente!;
    final tort = CoupsDuSort.faitDuTort(c.coup, joueur: etat.position, pop: pop);
    return Panneau(
      couleur: AuraCouleurs.jaune,
      inclinaison: 0.012,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('COUP DE THÉÂTRE, CASE ${c.numero} : ${c.coup.nom.toUpperCase()}', style: AuraTexte.titre(16)),
        const SizedBox(height: 6),
        Text(c.coup.effet, style: AuraTexte.corps(15, poids: FontWeight.w900)),
        if (tort) ...[
          const SizedBox(height: 4),
          Text('Ça ne t\'arrange pas ? Tu peux le parer.', style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pastille(libelle: tort ? 'Encaisser' : 'D\'accord !', choisie: false, autofocus: true, onTap: () => etat.resoudreCoup()),
          if (tort && etat.peutParerAvecCharge) Pastille(libelle: 'Parer (1 charge de pouvoir)', choisie: false, onTap: () => etat.resoudreCoup(parade: 'charge')),
          if (tort && etat.bouclierDispo) Pastille(libelle: 'Parer avec le Bouclier du mois', choisie: false, onTap: () => etat.resoudreCoup(parade: 'bouclier')),
        ]),
      ]),
    );
  }
}
