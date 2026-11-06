import 'package:flutter/material.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/etat.dart';
import '../services/ligues.dart';
import '../services/plan_du_jour.dart';
import '../services/sources.dart';
import '../services/tirage.dart';
import '../services/vjod_lien.dart';
import '../theme/aura_theme.dart';
import '../widgets/animations.dart';
import '../widgets/aura_widgets.dart';
import 'duel.dart';
import 'plan_du_jour.dart';
import 'reglages.dart';

enum _Etape { envie, cartes, pronostic, billet }

/// Ce soir : l'envie, le tirage des trois cartes, le pronostic, le billet.
class CeSoirEcran extends StatefulWidget {
  const CeSoirEcran({super.key, required this.versPlateau});
  final VoidCallback versPlateau;

  @override
  State<CeSoirEcran> createState() => _CeSoirEcranState();
}

class _CeSoirEcranState extends State<CeSoirEcran> {
  _Etape _etape = _Etape.envie;
  Emotion _emotion = Emotion.frissonner;
  Duree _duree = Duree.moyenne;
  List<CarteDefi> _cartes = const [];
  int _choisie = 0;
  int _pronostic = 4;
  int? _note;
  bool _chargement = false;
  String? _message;
  final _verdict = TextEditingController();
  final _tirage = Tirage();

  CarteDefi get _carte => _cartes[_choisie];

  @override
  void dispose() {
    _verdict.dispose();
    super.dispose();
  }

  Future<void> _tirer(EtatJeu etat) async {
    setState(() {
      _chargement = true;
      _message = null;
    });
    try {
      final catalogue = await etat.source.catalogue(emotion: _emotion);
      final cartes = _tirage.tirer(catalogue: catalogue, emotion: _emotion, duree: _duree, profil: etat.profil);
      setState(() {
        _cartes = cartes;
        _choisie = 0;
        if (cartes.isEmpty) {
          _message = 'Aucun film à 3 étoiles ou plus ne correspond à cette envie et à cette durée. Change d\'envie ou accorde-toi plus de temps.';
        } else {
          _etape = _Etape.cartes;
        }
      });
    } on ErreurSource catch (e) {
      setState(() => _message = e.message);
    } catch (_) {
      setState(() => _message = 'Impossible de joindre ta bibliothèque. Vérifie l\'adresse dans les réglages.');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _lancerDansVjod(EtatJeu etat) async {
    await etat.commencerSeance(_carte, pronostic: _pronostic);
    final erreur = await VjodLien.ouvrir(_carte.film);
    if (!mounted) return;
    if (erreur != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erreur)));
    } else {
      setState(() => _etape = _Etape.billet);
    }
  }

  Future<void> _valider(EtatJeu etat) async {
    final gagnees = await etat.validerSeance(_carte, pronostic: _pronostic, note: _note, verdict: _verdict.text.trim());
    if (!mounted) return;
    await celebrer(context);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(gagnees > 0
          ? 'Ton pion avance de $gagnees case${gagnees > 1 ? 's' : ''} !'
          : 'Séance enregistrée dans tes billets. Ton pion a déjà avancé de 3 cases aujourd\'hui : c\'est le maximum.'),
    ));
    setState(() {
      _etape = _Etape.envie;
      _note = null;
      _verdict.clear();
    });
    widget.versPlateau();
  }

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _etape == _Etape.envie && estTele(context) ? 1180 : 560),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(
              key: ValueKey(_etape),
              child: switch (_etape) {
                _Etape.envie => _envie(etat),
                _Etape.cartes => _main(),
                _Etape.pronostic => _pronosticVue(),
                _Etape.billet => _billet(etat),
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Une colonne de blocs espacés de façon régulière.
  Widget _colonne(List<Widget> blocs) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, b) in blocs.indexed) ...[if (i > 0) const SizedBox(height: 18), b],
        ],
      );

  Widget _envie(EtatJeu etat) {
    // Ce qui attend une réponse passe avant tout.
    final alerte = <Widget>[
      if (etat.billetANoter != null)
        _ANoter(billet: etat.billetANoter!)
      else if (etat.enCoursAVoir.isNotEmpty)
        _AlorsCeFilm(seance: etat.enCoursAVoir.first),
    ];
    final haut = <Widget>[
      _CourseEtSerie(etat: etat),
      _CartePlanDuJour(resultat: etat.planDuJour),
    ];
    final principal = <Widget>[
      if (etat.bonRetour != null)
        PopQuiParle(
          texte: 'Te revoilà ! Ça faisait ${etat.bonRetour} jours. Pas de souci : j\'ai gardé ta place au chaud. Et voilà une carte de rattrapage pour repartir.',
        ),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
            height: 150,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 120, top: 8),
                  child: TitreCartoon('Envie de quoi ce soir ?', taille: 38),
                ),
                Positioned(
                  right: -4,
                  top: -6,
                  child: Transform.rotate(
                    angle: 0.1,
                    child: Image.asset('assets/marque/pop.png', height: 150, semanticLabel: 'Pop, la mascotte VJOD'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: [
              for (final e in Emotion.values)
                Pastille(
                  libelle: e.libelle,
                  choisie: e == _emotion,
                  autofocus: e == _emotion && etat.billetANoter == null && etat.enCoursAVoir.isEmpty,
                  onTap: () => setState(() => _emotion = e),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Panneau(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('COMBIEN DE TEMPS AS-TU ?', style: AuraTexte.titre(16)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 10, children: [
                  for (final d in Duree.values)
                    Pastille(libelle: d.libelle, choisie: d == _duree, onTap: () => setState(() => _duree = d)),
                ]),
                const SizedBox(height: 12),
                Text('Les cartes viennent de ${etat.source.nom}. Uniquement des films notés 3 étoiles ou plus.',
                    style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
              ],
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 14),
            Panneau(couleur: AuraCouleurs.jaune, child: Text(_message!, style: AuraTexte.corps(14, poids: FontWeight.w900))),
          ],
          const SizedBox(height: 20),
          AuraBouton(
            libelle: _chargement ? 'Pop mélange les cartes…' : 'Tirer mes 3 cartes',
            onPressed: _chargement ? null : () => _tirer(etat),
          ),
      ]),
      if (etat.carteRattrapage)
        Panneau(
          couleur: AuraCouleurs.vert,
          inclinaison: -0.012,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text('Carte de rattrapage en main : +2 cases sur ta prochaine séance.', style: AuraTexte.corps(14, poids: FontWeight.w900)),
        ),
      if (etat.jokerBluff)
        Panneau(
          couleur: AuraCouleurs.vert,
          inclinaison: 0.012,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text('Joker en main : +1 case sur ta prochaine séance.', style: AuraTexte.corps(14, poids: FontWeight.w900)),
        ),
    ];
    final bas = <Widget>[
      _PendantCeTemps(etat: etat),
      ChoixLarge(
        libelle: 'LE DUEL DU CANAPÉ · À deux sur la télé : chacun pose ses cartes, on élimine à tour de rôle, et le quiz désigne qui choisit le film.',
        couleur: AuraCouleurs.rose,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DuelEcran())),
      ),
      if (etat.mode == ModeJeu.demo)
        ChoixLarge(
          libelle: 'Tu utilises VJOD ? Branche ta bibliothèque : les cartes viendront de tes films, et ceux que tu termines seront validés automatiquement.',
          couleur: AuraCouleurs.bleu,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReglagesEcran())),
        ),
    ];
    if (!estTele(context)) return _colonne([...alerte, ...haut, ...principal, ...bas]);
    // Sur la télé : le jeu à gauche, le reste à droite.
    return _colonne([
      ...alerte,
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: _colonne(principal)),
        const SizedBox(width: 28),
        Expanded(flex: 2, child: _colonne([...haut, ...bas])),
      ]),
    ]);
  }

  Widget _main() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreCartoon('Choisis ta carte !', taille: 44),
        const SizedBox(height: 8),
        Text('${_emotion.libelle} · ${_duree.libelle}. Flèches gauche et droite pour choisir, OK pour jouer.',
            style: AuraTexte.corps(15)),
        const SizedBox(height: 10),
        PopQuiParle(texte: _carte.bulleDePop, taille: 76),
        const SizedBox(height: 6),
        MainDeCartes(
          cartes: _cartes,
          choisie: _choisie,
          onChoisir: (i) => setState(() => _choisie = i),
          onJouer: () => setState(() => _etape = _Etape.pronostic),
        ),
        Panneau(child: Text('${_carte.joker} Tous les films proposés sont notés 3 étoiles ou plus.', style: AuraTexte.corps(14))),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(flex: 2, child: AuraBouton(libelle: 'Changer d\'envie', principal: false, onPressed: () => setState(() => _etape = _Etape.envie))),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: AuraBouton(libelle: 'Jouer cette carte !', onPressed: () => setState(() => _etape = _Etape.pronostic))),
          ],
        ),
      ],
    );
  }

  Widget _pronosticVue() {
    final f = _carte.film;
    final vjod = VjodLien.disponible(f);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('CARTE RÉVÉLÉE !', style: AuraTexte.titre(20, couleur: AuraCouleurs.creme)),
        const SizedBox(height: 8),
        Transform.rotate(
          angle: -0.02,
          child: Retournement(
            dos: AspectRatio(
              aspectRatio: 1.6,
              child: Container(
                decoration: AuraTrait.panneau(couleur: _carte.type.couleur),
                alignment: Alignment.center,
                child: const TitreCartoon('?', taille: 90, inclinaison: 0),
              ),
            ),
            face: AfficheIllustree(film: f, type: _carte.type),
          ),
        ),
        if (f.synopsis != null) ...[
          const SizedBox(height: 12),
          Panneau(child: Text(f.synopsis!, style: AuraTexte.corps(14))),
        ],
        const SizedBox(height: 18),
        Panneau(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TON PRONOSTIC : COMBIEN D\'ÉTOILES LUI DONNERAS-TU ?', style: AuraTexte.titre(16)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var n = 1; n <= 5; n++)
                  Pastille(libelle: '$n', choisie: n == _pronostic, autofocus: n == _pronostic, onTap: () => setState(() => _pronostic = n)),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (vjod)
          AuraBouton(libelle: 'Lancer dans VJOD', icone: Icons.play_arrow_rounded, onPressed: () => _lancerDansVjod(PorteeEtat.of(context)))
        else
          AuraBouton(
            libelle: 'C\'est parti, je le regarde',
            onPressed: () async {
              await PorteeEtat.of(context).commencerSeance(_carte, pronostic: _pronostic);
              if (mounted) setState(() => _etape = _Etape.billet);
            },
          ),
        const SizedBox(height: 12),
        AuraBouton(libelle: 'Revoir ma main', principal: false, onPressed: () => setState(() => _etape = _Etape.cartes)),
      ],
    );
  }

  Widget _billet(EtatJeu etat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreCartoon('Alors, ce film ?', taille: 40),
        const SizedBox(height: 16),
        Transform.rotate(
          angle: 0.02,
          child: Container(
            decoration: AuraTrait.panneau(),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Billet n° ${(etat.billets.length + 1).toString().padLeft(3, '0')}', style: AuraTexte.corps(13, poids: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(_carte.film.titre.toUpperCase(), style: AuraTexte.titre(30)),
                      Text('${_emotion.libelle} · ${_carte.defi}', style: AuraTexte.corps(14, couleur: AuraCouleurs.texteDoux)),
                    ],
                  ),
                ),
                Container(
                  color: const Color(0xFFFFE9A8),
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                  child: Row(children: [
                    Expanded(child: _ligneBillet('Pronostic', '$_pronostic / 5')),
                    Expanded(child: _ligneBillet('Plateau', '+${_carte.cases}')),
                  ]),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Panneau(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TA NOTE APRÈS LE FILM (TU AVAIS PRÉDIT $_pronostic)', style: AuraTexte.titre(16)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var n = 1; n <= 5; n++)
                  Pastille(libelle: '$n', choisie: n == _note, onTap: () => setState(() => _note = n)),
              ]),
              const SizedBox(height: 6),
              Text('Pop va la comparer à ton pronostic. Prépare-toi.', style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Panneau(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TON VERDICT EN UNE PHRASE', style: AuraTexte.titre(16)),
              const SizedBox(height: 8),
              ChampAura(controleur: _verdict, indication: 'À voir seul, un soir de pluie', longueurMax: 120),
            ],
          ),
        ),
        const SizedBox(height: 18),
        AuraBouton(libelle: 'Valider et avancer mon pion', autofocus: true, onPressed: () => _valider(etat)),
        const SizedBox(height: 12),
        AuraBouton(libelle: 'Finalement, je ne l\'ai pas vu', principal: false, onPressed: () => setState(() => _etape = _Etape.cartes)),
      ],
    );
  }

  Widget _ligneBillet(String a, String b) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(a, style: AuraTexte.corps(12, poids: FontWeight.w900)), Text(b, style: AuraTexte.titre(24))],
      );
}

/// L'accès au Plan du jour, en haut de Ce soir.
class _CartePlanDuJour extends StatelessWidget {
  const _CartePlanDuJour({required this.resultat});
  final ResultatPlan? resultat;

  @override
  Widget build(BuildContext context) {
    final r = resultat;
    final cases = [
      for (var i = 0; i < 3; i++)
        r == null
            ? [AuraCouleurs.vert, AuraCouleurs.jaune, AuraCouleurs.creme][i]
            : i < r.indices - 1
                ? AuraCouleurs.jaune
                : i == r.indices - 1
                    ? (r.trouve ? AuraCouleurs.vert : AuraCouleurs.caseRouge)
                    : AuraCouleurs.creme,
    ];
    return Touchable(
      etiquette: 'Le Plan du jour',
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlanDuJourEcran())),
      builder: (context, focus, appui) => AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        transform: Matrix4.translationValues(appui ? 3 : 0, appui ? 3 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: AuraTrait.panneau(ombre: appui ? 0 : 4).copyWith(
          boxShadow: [
            if (focus) const BoxShadow(color: AuraCouleurs.jaune, spreadRadius: 5),
            if (!appui) const BoxShadow(color: AuraCouleurs.noir, offset: Offset(4, 4)),
          ],
        ),
        child: Row(children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final c in cases)
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3), border: Border.all(width: 1.5)),
              ),
          ]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('LE PLAN DU JOUR', style: AuraTexte.titre(16)),
              Text(
                r == null
                    ? 'Un film à deviner, 3 indices, 1 essai'
                    : r.trouve
                        ? 'Trouvé au ${r.indices == 1 ? '1er' : '${r.indices}e'} indice. À demain !'
                        : 'Raté pour aujourd\'hui. Revanche demain !',
                style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: AuraCouleurs.jaune, borderRadius: BorderRadius.circular(10), border: Border.all(width: 2.5)),
            child: Text(r == null ? 'JOUER' : 'PARTAGER', style: AuraTexte.titre(15)),
          ),
        ]),
      ),
    );
  }
}

/// Un billet créé tout seul : il ne manque que la note, en un geste.
class _ANoter extends StatelessWidget {
  const _ANoter({required this.billet});
  final Billet billet;

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    return Panneau(
      couleur: AuraCouleurs.vert,
      inclinaison: -0.012,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(billet.cases > 0 ? 'BILLET VALIDÉ AUTOMATIQUEMENT : +${billet.cases} !' : 'BILLET VALIDÉ AUTOMATIQUEMENT !', style: AuraTexte.titre(16)),
        const SizedBox(height: 4),
        Text('Alors, ${billet.titre} ?', style: AuraTexte.titre(26)),
        const SizedBox(height: 4),
        Text('Donne ta note : Pop la comparera à ton pronostic (${billet.pronostic} sur 5).', style: AuraTexte.corps(13)),
        const SizedBox(height: 10),
        _Etoiles(autofocus: true, onNote: (n) => etat.noterBillet(billet, n)),
      ]),
    );
  }
}

/// Une carte jouée sans billet : « Alors, ce film ? ». Une note valide tout.
class _AlorsCeFilm extends StatelessWidget {
  const _AlorsCeFilm({required this.seance});
  final SeanceEnCours seance;

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    return Panneau(
      couleur: AuraCouleurs.jaune,
      inclinaison: -0.012,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Alors, ${seance.titre} ?', style: AuraTexte.titre(26)),
        const SizedBox(height: 4),
        Text('Tu l\'as vu ? Donne ta note, et ton pion avance de ${seance.cases} case${seance.cases > 1 ? 's' : ''}.', style: AuraTexte.corps(13)),
        const SizedBox(height: 10),
        _Etoiles(
          autofocus: true,
          onNote: (n) async {
            final gagnees = await etat.validerEnCours(seance, note: n);
            if (context.mounted) await celebrer(context);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(gagnees > 0 ? 'Billet validé : +$gagnees !' : 'Billet validé. Ton pion avait déjà avancé de 3 cases ce jour-là.'),
              ));
            }
          },
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pastille(libelle: 'Pas encore', choisie: false, onTap: () => etat.reporterSeance(seance)),
          Pastille(libelle: 'Je ne le regarderai pas', choisie: false, onTap: () => etat.abandonnerSeance(seance)),
        ]),
      ]),
    );
  }
}

/// Cinq étoiles à toucher (ou à atteindre aux flèches) : la note en un geste.
class _Etoiles extends StatelessWidget {
  const _Etoiles({required this.onNote, this.autofocus = false});
  final ValueChanged<int> onNote;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (var n = 1; n <= 5; n++)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Touchable(
            etiquette: '$n étoile${n > 1 ? 's' : ''}',
            autofocus: autofocus && n == 4,
            onTap: () => onNote(n),
            builder: (context, focus, appui) => AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: 48,
              height: 48,
              transform: Matrix4.translationValues(appui ? 2 : 0, appui ? 2 : 0, 0),
              decoration: BoxDecoration(
                color: focus ? AuraCouleurs.ambre : AuraCouleurs.creme,
                shape: BoxShape.circle,
                border: Border.all(width: 2.5),
                boxShadow: [
                  if (focus) const BoxShadow(color: AuraCouleurs.creme, spreadRadius: 3),
                  if (!appui) const BoxShadow(color: AuraCouleurs.noir, offset: Offset(2, 2)),
                ],
              ),
              alignment: Alignment.center,
              child: Text('$n', style: AuraTexte.titre(20)),
            ),
          ),
        ),
    ]);
  }
}

/// Deux encarts en haut de Ce soir : la course contre Pop (qui mène ?) et
/// la série en semaines.
class _CourseEtSerie extends StatelessWidget {
  const _CourseEtSerie({required this.etat});
  final EtatJeu etat;

  @override
  Widget build(BuildContext context) {
    final moi = etat.position;
    final pop = etat.positionDePop;
    final ecart = moi - pop;
    final course = Panneau(
      inclinaison: -0.012,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TA COURSE CONTRE POP', style: AuraTexte.titre(15)),
        const SizedBox(height: 4),
        Text(
          ecart > 0
              ? 'Tu mènes de $ecart case${ecart > 1 ? 's' : ''} !'
              : ecart == 0
                  ? 'Coude à coude, case $moi.'
                  : 'Pop mène de ${-ecart} case${ecart < -1 ? 's' : ''}.',
          style: AuraTexte.corps(13, poids: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          double x(int p) => (c.maxWidth - 30) * (p - 1) / 29;
          return SizedBox(
            height: 46,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 0,
                right: 0,
                top: 32,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5), border: Border.all(width: 2)),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(widthFactor: (moi - 1) / 29, child: Container(color: AuraCouleurs.ambre)),
                ),
              ),
              Positioned(left: x(pop), top: 0, child: const Figurine.pop(hauteur: 36)),
              Positioned(left: x(moi), top: 0, child: Figurine.profil(etat.profil, hauteur: 36)),
            ]),
          );
        }),
      ]),
    );
    final serie = Panneau(
      couleur: AuraCouleurs.jaune,
      inclinaison: 0.012,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TA SÉRIE', style: AuraTexte.titre(15)),
        const SizedBox(height: 4),
        Text(etat.serie > 0 ? '${etat.serie}' : '0', style: AuraTexte.titre(40)),
        Text(etat.serie > 1 ? 'semaines de cinéma' : (etat.serie == 1 ? 'semaine de cinéma' : 'Lance-la ce soir !'), style: AuraTexte.corps(12, poids: FontWeight.w900)),
      ]),
    );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 3, child: course),
      const SizedBox(width: 10),
      Expanded(flex: 2, child: serie),
    ]);
  }
}

/// « Pendant ce temps, à la ligue » : ce que font les amis, sous le tirage.
class _PendantCeTemps extends StatefulWidget {
  const _PendantCeTemps({required this.etat});
  final EtatJeu etat;

  @override
  State<_PendantCeTemps> createState() => _PendantCeTempsState();
}

class _PendantCeTempsState extends State<_PendantCeTemps> {
  Future<List<Nouvelle>>? _fil;

  @override
  void initState() {
    super.initState();
    final l = widget.etat.ligues;
    if (l != null && l.inscrit && l.ligues.isNotEmpty) _fil = l.fil(l.ligues.first);
  }

  @override
  Widget build(BuildContext context) {
    final titre = Text('PENDANT CE TEMPS, À LA LIGUE', style: AuraTexte.titre(16, couleur: AuraCouleurs.creme));
    if (_fil == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        titre,
        const SizedBox(height: 8),
        const PopQuiParle(
          taille: 56,
          texte: 'Pour l\'instant, il n\'y a que toi et moi. Invite tes amis depuis l\'onglet Ligue : vous gagnerez chacun une figurine dorée.',
        ),
      ]);
    }
    return FutureBuilder<List<Nouvelle>>(
      future: _fil,
      builder: (context, snap) {
        final fil = (snap.data ?? const <Nouvelle>[]).where((n) => !n.moi).take(3).toList();
        if (fil.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          titre,
          const SizedBox(height: 8),
          for (final n in fil)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panneau(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  Figurine.profil(n.profil, hauteur: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      n.verdict != null && n.verdict!.isNotEmpty ? '${n.phrase} « ${n.verdict} »' : n.phrase,
                      style: AuraTexte.corps(13, poids: FontWeight.w900),
                    ),
                  ),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}
