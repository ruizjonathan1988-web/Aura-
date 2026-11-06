import 'package:flutter/material.dart';

import '../app.dart';
import '../services/affiche.dart';
import '../services/carte_genres.dart';
import '../theme/aura_theme.dart';
import '../widgets/animations.dart';
import '../widgets/aura_widgets.dart';

/// La Révélation du dimanche, pensée pour la télé (et lisible au téléphone) :
/// on avance d'un tableau à l'autre avec OK. Le Curseur est dévoilé, Pop « le
/// Médium » tente de le deviner, on revoit le Bluff de la semaine et le plateau.
class RevelationEcran extends StatefulWidget {
  const RevelationEcran({super.key, required this.affiche});
  final Affiche affiche;

  @override
  State<RevelationEcran> createState() => _RevelationEcranState();
}

class _RevelationEcranState extends State<RevelationEcran> {
  int _tableau = 0;
  bool? _joker;

  Future<void> _suivant() async {
    final etat = PorteeEtat.lire(context);
    final a = widget.affiche;
    if (_tableau == 1) {
      final curseur = etat.curseurDe(a.semaine);
      if (curseur != null) {
        final j = await etat.terminerRevelation(a.semaine, pari: Affiche.pariDuMedium(a.semaine), curseur: curseur);
        _joker ??= j;
      }
    }
    if (_tableau >= 3) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (mounted) setState(() => _tableau++);
  }

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    final a = widget.affiche;
    final curseur = etat.curseurDe(a.semaine);
    final pari = Affiche.pariDuMedium(a.semaine);
    final bluff = etat.bluffDe(a.semaine);
    final carte = CarteDesGenres.de(DateTime.now(), etat.billets);
    final tele = estTele(context);
    final tableaux = <Widget>[
      // 1. Le lever de rideau.
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('LA RÉVÉLATION · DIMANCHE', style: AuraTexte.titre(tele ? 26 : 18, couleur: AuraCouleurs.creme)),
        const SizedBox(height: 10),
        TitreCartoon(a.film.titre, taille: tele ? 72 : 44),
        const SizedBox(height: 16),
        PopQuiParle(
          taille: tele ? 120 : 80,
          texte: 'Mesdames et messieurs, la semaine de cinéma touche à sa fin. Ce soir, je vais lire dans tes pensées. Appuie sur OK quand tu es prêt.',
        ),
      ]),
      // 2. Le Médium et le Curseur.
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TitreCartoon('Le Curseur : ${a.question}', taille: tele ? 44 : 30),
        const SizedBox(height: 16),
        PopQuiParle(
          taille: tele ? 110 : 76,
          texte: curseur == null
              ? 'Tu n\'as pas placé ton Curseur cette semaine… Je n\'ai rien à deviner. Tant pis, on passe !'
              : 'Je me concentre… Je vois… un $pari ! Tu as placé ton Curseur sur $pari. J\'en suis sûr.',
        ),
        if (curseur != null) ...[
          const SizedBox(height: 20),
          _Jauge(pari: pari, curseur: curseur, tele: tele),
          const SizedBox(height: 16),
          Entree(
            delai: const Duration(milliseconds: 1200),
            child: Panneau(
              couleur: Affiche.mediumRate(pari, curseur) ? AuraCouleurs.vert : AuraCouleurs.jaune,
              child: Text(
                Affiche.mediumRate(pari, curseur)
                    ? 'C\'était $curseur ! Pop s\'est trompé de ${(pari - curseur).abs()} crans : tu gagnes un Joker (+1 case sur ta prochaine séance).'
                    : (pari == curseur ? 'C\'était $curseur. Pile ! Pop lit vraiment dans les pensées…' : 'C\'était $curseur. Pop n\'était pas loin. Pas de Joker cette fois.'),
                style: AuraTexte.corps(tele ? 20 : 15, poids: FontWeight.w900),
              ),
            ),
          ),
        ],
      ]),
      // 3. Le Bluff de la semaine.
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TitreCartoon('Le Bluff de la semaine', taille: tele ? 48 : 32),
        const SizedBox(height: 16),
        PopQuiParle(
          taille: tele ? 110 : 76,
          texte: bluff == null
              ? 'Tu n\'as pas joué mon Bluff cette semaine. J\'avais pourtant écrit de si beaux mensonges.'
              : bluff
                  ? 'Tu as démasqué mon Bluff. Je ne m\'en remets pas. La semaine prochaine, je serai plus fourbe.'
                  : 'Je t\'ai eu avec mon faux résumé ! Je l\'encadre au-dessus de mon pot.',
        ),
      ]),
      // 4. Le plateau.
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TitreCartoon('Le plateau ce soir', taille: tele ? 48 : 32),
        const SizedBox(height: 16),
        _Bandeau(moi: etat.position, pop: etat.positionDePop, tele: tele),
        const SizedBox(height: 16),
        Panneau(
          child: Text(
            'Carte des genres : ${carte.regionsDuJoueur} région${carte.regionsDuJoueur > 1 ? 's' : ''} pour toi, ${carte.regionsDePop} pour Pop. Nouvelle Affiche lundi !',
            style: AuraTexte.corps(tele ? 20 : 15, poids: FontWeight.w900),
          ),
        ),
      ]),
    ];
    return Scaffold(
      body: FondTrame(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(tele ? 48 : 18, 18, tele ? 48 : 18, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const EnTeteRetour(titre: 'La Révélation'),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(key: ValueKey(_tableau), child: tableaux[_tableau]),
                  ),
                  const SizedBox(height: 24),
                  AuraBouton(
                    libelle: _tableau < 3 ? 'Suite' : 'À la semaine prochaine !',
                    autofocus: true,
                    onPressed: _suivant,
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La jauge du Curseur : le pari de Pop d'abord, puis la vraie valeur.
class _Jauge extends StatelessWidget {
  const _Jauge({required this.pari, required this.curseur, required this.tele});
  final int pari;
  final int curseur;
  final bool tele;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      double x(int v) => (c.maxWidth - 50) * v / 10;
      return SizedBox(
        height: 96,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            right: 0,
            top: 60,
            child: Container(
              height: 16,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(width: 3)),
            ),
          ),
          Positioned(left: x(pari), top: 0, child: const Figurine.pop(hauteur: 56)),
          Positioned(
            left: x(curseur),
            top: 46,
            child: Entree(
              delai: const Duration(milliseconds: 900),
              depuis: const Offset(0, -80),
              child: Container(
                width: 50,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AuraCouleurs.ambre, borderRadius: BorderRadius.circular(12), border: Border.all(width: 3)),
                child: Text('$curseur', style: AuraTexte.titre(24)),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

/// Le plateau en bandeau : toi et Pop sur une ligne de 30 cases.
class _Bandeau extends StatelessWidget {
  const _Bandeau({required this.moi, required this.pop, required this.tele});
  final int moi;
  final int pop;
  final bool tele;

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    return Panneau(
      couleur: AuraCouleurs.plateau,
      child: LayoutBuilder(builder: (context, c) {
        final h = tele ? 64.0 : 44.0;
        double x(int p) => (c.maxWidth - h / 1.36) * (p - 1) / 29;
        return SizedBox(
          height: h + 24,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: 0,
              right: 0,
              top: h + 6,
              child: Row(children: [
                for (var i = 1; i <= 30; i++)
                  Expanded(
                    child: Container(
                      height: 12,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: i % 5 == 0 ? AuraCouleurs.caseRouge : (i.isEven ? AuraCouleurs.caseOrange : AuraCouleurs.caseBleu),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ]),
            ),
            Positioned(left: x(pop), top: 0, child: Figurine.pop(hauteur: h)),
            Positioned(left: x(moi), top: 0, child: Rebond(declencheur: moi, sauts: 3, hauteur: 10, auDemarrage: true, child: Figurine.profil(etat.profil, hauteur: h))),
          ]),
        );
      }),
    );
  }
}
