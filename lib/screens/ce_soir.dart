import 'package:flutter/material.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/etat.dart';
import '../services/ligues.dart';
import '../services/niveau.dart';
import '../services/pouvoirs.dart';
import '../services/sources.dart';
import '../services/tirage.dart';
import '../services/vjod_lien.dart';
import '../theme/aura_theme.dart';
import '../widgets/animations.dart';
import '../widgets/aura_widgets.dart';
import '../widgets/ou_le_voir.dart';
import '../services/apres_seance.dart';
import '../services/cadeaux.dart';
import '../services/collection.dart';
import '../services/deblocage.dart';
import 'generique.dart';
import 'juste_un_film.dart';
import 'reglages.dart';
import 'soiree.dart';
import 'deck.dart';
import '../services/pop.dart';
import '../services/casse.dart';
import 'casse.dart';

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

  /// « Tu te mets combien ? » ; nul tant que le joueur garde le niveau proposé.
  int? _niveau;
  List<CarteDefi> _cartes = const [];
  int _choisie = 0;
  int _pronostic = 4;
  int? _note;
  bool _chargement = false;
  String? _message;

  /// Ce que Pop a changé pour éviter l'impasse (durée allongée…).
  String? _avisDePop;
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
      final catalogue = await etat.source.catalogue(emotion: _emotion, duree: _duree);
      final paysVus = {for (final b in etat.billets) ...b.pays};
      final pouvoir = await etat.pouvoirAuTirage();
      final tirage = _tirage.tirerSansImpasse(
        catalogue: catalogue,
        emotion: _emotion,
        duree: _duree,
        profil: etat.profil,
        paysVus: paysVus,
        niveau: etat.ouvert(Etape.niveaux) ? etat.niveauImpose ?? _niveau ?? etat.niveauPropose : null,
        nombre: pouvoir.nombre,
        revoir: pouvoir.revoir,
      );
      if (etat.niveauImpose != null && tirage.cartes.isNotEmpty) await etat.oublierNiveauImpose();
      setState(() {
        _cartes = tirage.cartes;
        _choisie = 0;
        _avisDePop = tirage.message;
        if (tirage.cartes.isEmpty) {
          _message = tirage.message;
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
          constraints: BoxConstraints(maxWidth: (_etape == _Etape.envie || _etape == _Etape.cartes) && estTele(context) ? 1180 : 560),
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
    final generique = etat.generiqueAVoir;
    final haut = <Widget>[
      _PourToi(etat: etat),
      if (etat.defiApres != null) _DefiApresVue(key: ValueKey(etat.defiApres!.date), etat: etat, billet: etat.defiApres!),
      if (generique != null)
        ChoixLarge(
          libelle: 'LE GÉNÉRIQUE DE ${Collection.mois[generique.month - 1].toUpperCase()} EST PRÊT · Revois ta saison et le résultat contre Pop.',
          couleur: AuraCouleurs.ambre,
          autofocus: true,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GeneriqueEcran(mois: generique))),
        ),
      _CourseEtSerie(etat: etat),
      _LaSemaine(etat: etat),
      if (Casse.enCours(DateTime.now()) && etat.ouvert(Etape.casse))
        ChoixLarge(
          libelle: 'LE CASSE DE LA CINÉMATHÈQUE · Quatre serrures, le trophée de Pop, et peut-être une Taupe parmi vous. Fin le ${Casse.dernierJour(DateTime.now())} à 18 h.',
          couleur: AuraCouleurs.jaune,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CasseEcran())),
        ),
      if (etat.billets.isNotEmpty && etat.boostersDispo() > 0)
        ChoixLarge(
          libelle: 'TON BOOSTER D\'ATOUTS T\'ATTEND · Trois cartes à collectionner pour ton deck.',
          couleur: AuraCouleurs.violet,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeckEcran())),
        ),
    ];
    final principal = <Widget>[
      if (etat.bonRetour == null && etat.billets.isNotEmpty)
        PopQuiParle(texte: Pop.accueil(joueur: etat.position, pop: etat.positionDePop, maintenant: DateTime.now(), insolent: etat.popInsolent), taille: 56),
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
                  padding: EdgeInsets.only(right: 120, top: 16),
                  child: TitreCartoon('Envie de quoi ce soir\u00a0?', taille: 34),
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
          const SizedBox(height: 18),
          if (etat.ouvert(Etape.niveaux)) _combien(etat),
          if (etat.ouvert(Etape.pouvoirs)) ...[
            const SizedBox(height: 14),
            _pouvoir(etat),
          ],
          if (_message != null) ...[
            const SizedBox(height: 14),
            Panneau(couleur: AuraCouleurs.jaune, child: Text(_message!, style: AuraTexte.corps(14, poids: FontWeight.w900))),
          ],
          const SizedBox(height: 20),
          AuraBouton(
            libelle: _chargement
                ? 'Pop mélange les cartes…'
                : 'Tirer mes ${etat.pouvoirArme && Pouvoirs.moment(etat.profil) == MomentPouvoir.tirage ? Pouvoirs.cartesAuTirage(etat.profil) : 3} cartes',
            onPressed: _chargement ? null : () => _tirer(etat),
          ),
          const SizedBox(height: 12),
          ChoixLarge(
            libelle: 'PAS ENVIE DE JOUER ? · Juste un film : trois idées, à changer autant que tu veux, sans compter pour le plateau.',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JusteUnFilmEcran())),
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
      // Une seule entrée pour jouer à plusieurs (R59).
      ChoixLarge(
        libelle: 'SOIRÉE JEU · À plusieurs sur la télé : avec vos téléphones, ou le Duel du canapé à une seule télécommande.',
        couleur: AuraCouleurs.violet,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChoixSoireeEcran(ligues: etat.ligues))),
      ),
      if (etat.mode == ModeJeu.demo)
        ChoixLarge(
          libelle: 'Tu utilises VJOD ? Branche ta bibliothèque : les cartes viendront de tes films, et ceux que tu termines seront validés automatiquement.',
          couleur: AuraCouleurs.bleu,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReglagesEcran())),
        ),
    ];
    // Sur le téléphone, l'action d'abord ; le reste en pastilles qui s'ouvrent.
    if (!estTele(context)) return _colonne([...alerte, ...principal, _Aujourdhui(etat: etat), ...bas]);
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

  /// « Tu te mets combien ? » : dix pastilles, la proposition d'Aura déjà choisie.
  Widget _combien(EtatJeu etat) {
    final propose = etat.niveauPropose;
    final impose = etat.niveauImpose;
    final n = impose ?? _niveau ?? propose;
    final gain = Niveau.cases(n);
    return Panneau(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TU TE METS COMBIEN ?', style: AuraTexte.titre(16)),
        if (impose != null) ...[
          const SizedBox(height: 6),
          Text('Crasse d\'un ami : ce soir, c\'est $impose, pas de discussion.', style: AuraTexte.corps(14, poids: FontWeight.w900)),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 10, children: [
          for (var i = Niveau.min; i <= Niveau.max; i++)
            Pastille(libelle: '$i', choisie: i == n, onTap: impose != null ? null : () => setState(() => _niveau = i)),
        ]),
        const SizedBox(height: 12),
        Text('$n · ${Niveau.nom(n).toUpperCase()} : ${gain == 1 ? '1 case' : '$gain cases'} si tu vas au bout.', style: AuraTexte.corps(14, poids: FontWeight.w900)),
        Text(Niveau.promesse(n), style: AuraTexte.corps(13)),
        Text(Niveau.risque(n), style: AuraTexte.corps(13, poids: n >= 9 ? FontWeight.w900 : FontWeight.w400)),
        const SizedBox(height: 4),
        Text(
          '${n == propose ? 'C\'est le niveau que je te propose, d\'après tes dernières séances.' : 'Je t\'aurais mis $propose, d\'après tes dernières séances. À toi de voir !'}'
          ' Audace du mois : ${etat.audaceDuMois}.',
          style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux),
        ),
      ]),
    );
  }

  /// Le pouvoir du pion (R39) : ses charges, et le bouton pour l'armer.
  Widget _pouvoir(EtatJeu etat) {
    final pp = etat.profilDuPouvoir;
    if (pp == null) {
      final f = etat.figurineDuMois;
      return Panneau(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('FIGURINE DU MOIS : ${f.nom.toUpperCase()}', style: AuraTexte.titre(16)),
          const SizedBox(height: 6),
          Text(f.explication, style: AuraTexte.corps(14)),
        ]),
      );
    }
    final p = pp;
    final charges = etat.chargesPouvoir;
    final arme = etat.pouvoirArme;
    final reste = Pouvoirs.audaceParCharge - etat.audaceDuMois % Pouvoirs.audaceParCharge;
    return Panneau(
      couleur: arme ? AuraCouleurs.jaune : AuraCouleurs.creme,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(etat.oeufEclos ? 'L\'ŒUF A ÉCLOS : ${p.pouvoir.toUpperCase()}' : 'TON POUVOIR : ${p.pouvoir.toUpperCase()}', style: AuraTexte.titre(16)),
        const SizedBox(height: 6),
        Text(p.effet, style: AuraTexte.corps(14)),
        const SizedBox(height: 6),
        Text(
          arme
              ? 'Armé : il agira ${Pouvoirs.quand(p)}. La charge part à ce moment-là, même si ça ne marche pas.'
              : '${charges == 0 ? 'Aucune charge' : charges == 1 ? '1 charge' : '$charges charges'}. Une par semaine, et une de plus tous les ${Pouvoirs.audaceParCharge} points d\'audace (encore $reste).',
          style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (arme)
            Pastille(libelle: 'Désarmer', choisie: false, onTap: etat.desarmerPouvoir)
          else
            Pastille(libelle: charges > 0 ? 'Armer mon pouvoir' : 'Plus de charge', choisie: false, onTap: charges > 0 ? etat.armerPouvoir : null),
        ]),
      ]),
    );
  }

  Widget _main() {
    // Sur la télé, tout tient dans l'écran : l'éventail à gauche, le reste à droite.
    if (estTele(context)) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: MainDeCartes(
            cartes: _cartes,
            choisie: _choisie,
            onChoisir: (i) => setState(() {
              _choisie = i;
              _avisDePop = null;
            }),
            onJouer: () => setState(() => _etape = _Etape.pronostic),
          ),
        ),
        const SizedBox(width: 24),
        SizedBox(
          width: 440,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const TitreCartoon('Choisis ta carte !', taille: 34),
            const SizedBox(height: 4),
            Text('${_emotion.libelle} · ${_duree.libelle}. Gauche et droite pour choisir, OK pour jouer.', style: AuraTexte.corps(14)),
            const SizedBox(height: 8),
            PopQuiParle(texte: _avisDePop ?? _carte.bulleDePop, taille: 60),
            const SizedBox(height: 8),
            Panneau(child: Text('${_carte.joker} Tous les films proposés sont notés 3 étoiles ou plus.', style: AuraTexte.corps(13))),
            if (PorteeEtat.of(context).relanceDispo) ...[
              const SizedBox(height: 10),
              AuraBouton(
                libelle: 'Joker Relance (1 par mois)',
                icone: Icons.autorenew_rounded,
                principal: false,
                onPressed: () async {
                  final etat = PorteeEtat.lire(context);
                  await etat.utiliserRelance();
                  await _tirer(etat);
                },
              ),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: AuraBouton(libelle: 'Changer d\'envie', principal: false, onPressed: () => setState(() => _etape = _Etape.envie))),
              const SizedBox(width: 10),
              Expanded(child: AuraBouton(libelle: 'Jouer cette carte !', onPressed: () => setState(() => _etape = _Etape.pronostic))),
            ]),
          ]),
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreCartoon('Choisis ta carte !', taille: 44),
        const SizedBox(height: 8),
        Text('${_emotion.libelle} · ${_duree.libelle}. Flèches gauche et droite pour choisir, OK pour jouer.',
            style: AuraTexte.corps(15)),
        const SizedBox(height: 10),
        PopQuiParle(texte: _avisDePop ?? _carte.bulleDePop, taille: 76),
        const SizedBox(height: 6),
        MainDeCartes(
          cartes: _cartes,
          choisie: _choisie,
          onChoisir: (i) => setState(() {
            _choisie = i;
            _avisDePop = null;
          }),
          onJouer: () => setState(() => _etape = _Etape.pronostic),
        ),
        Panneau(child: Text('${_carte.joker} Tous les films proposés sont notés 3 étoiles ou plus.', style: AuraTexte.corps(14))),
        if (PorteeEtat.of(context).relanceDispo) ...[
          const SizedBox(height: 12),
          AuraBouton(
            libelle: 'Joker Relance : une nouvelle main (1 par mois)',
            icone: Icons.autorenew_rounded,
            principal: false,
            onPressed: () async {
              final etat = PorteeEtat.lire(context);
              await etat.utiliserRelance();
              await _tirer(etat);
            },
          ),
        ],
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
        const SizedBox(height: 12),
        OuLeVoir(key: ValueKey(f.id), film: f),
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
          Pastille(
            libelle: Niveau.recul(seance.niveau) > 0 ? 'Je ne le regarderai pas (−${Niveau.recul(seance.niveau)})' : 'Je ne le regarderai pas',
            choisie: false,
            onTap: () => etat.abandonnerSeance(seance),
          ),
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

/// La course contre Pop (qui mène ?), en haut de Ce soir sur la télé et
/// dans la pastille « Course » sur le téléphone.
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
    // La série est sur le Plateau : ici, seulement la course.
    return course;
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
  Future<(List<Classe>, List<Cadeau>)>? _cadeaux;

  @override
  void initState() {
    super.initState();
    final l = widget.etat.ligues;
    if (l != null && l.inscrit && l.ligues.isNotEmpty) {
      _fil = l.fil(l.ligues.first);
      final ligue = l.ligues.first;
      _cadeaux = (() async => (await l.classement(ligue), await l.cadeaux(ligue)))();
    }
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
          FutureBuilder<(List<Classe>, List<Cadeau>)>(
            future: _cadeaux,
            builder: (context, c) {
              final donnees = c.data;
              if (donnees == null) return const SizedBox.shrink();
              final (membres, cadeaux) = donnees;
              final moi = widget.etat.ligues?.monId;
              final pourMoi = cadeaux.where((x) => x.pour == moi && !x.ouvert).toList();
              if (pourMoi.isEmpty) return const SizedBox.shrink();
              final x = pourMoi.first;
              final de = membres.where((m) => m.joueurId == x.de).firstOrNull?.pseudo ?? 'Un ami';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panneau(
                  couleur: AuraCouleurs.rose,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.redeem_rounded, size: 32),
                    const SizedBox(width: 10),
                    Expanded(child: Text('$de t\'a offert un film, ${Cadeaux.quand(x.ouvrirLe, DateTime.now())}. Il t\'attend dans l\'onglet Ligue.', style: AuraTexte.corps(13, poids: FontWeight.w900))),
                  ]),
                ),
              );
            },
          ),
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

/// « Ce soir pour toi » (R42) : la nouveauté que Pop présente, sinon deux
/// lignes sur ce qui compte ce soir et la prochaine règle à débloquer.
class _PourToi extends StatelessWidget {
  const _PourToi({required this.etat});

  final EtatJeu etat;

  @override
  Widget build(BuildContext context) {
    final n = etat.nouveaute;
    if (n != null) {
      return Panneau(
        couleur: AuraCouleurs.jaune,
        inclinaison: -0.01,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('NOUVEAU : ${n.titre.toUpperCase()}', style: AuraTexte.titre(17)),
          const SizedBox(height: 6),
          PopQuiParle(texte: n.explication, taille: 60),
          const SizedBox(height: 8),
          Pastille(libelle: 'Compris !', choisie: false, autofocus: true, onTap: () => etat.nouveauteVue(n)),
        ]),
      );
    }
    final lignes = CeSoirPourToi.lignes(etat.situation);
    return Panneau(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('CE SOIR POUR TOI', style: AuraTexte.titre(16)),
        const SizedBox(height: 6),
        for (final (i, l) in lignes.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(l, style: AuraTexte.corps(14, poids: i == 0 ? FontWeight.w900 : FontWeight.w400, couleur: i == lignes.length - 1 && i > 0 ? AuraCouleurs.texteDoux : AuraCouleurs.noir)),
          ),
      ]),
    );
  }
}

/// Le défi d'après-séance (R44) : trois questions sur le film vu, une à la fois.
class _DefiApresVue extends StatefulWidget {
  const _DefiApresVue({super.key, required this.etat, required this.billet});

  final EtatJeu etat;
  final Billet billet;

  @override
  State<_DefiApresVue> createState() => _DefiApresVueState();
}

class _DefiApresVueState extends State<_DefiApresVue> {
  late final List<QuestionApres> _questions = DefiApres.questions(
    titre: widget.billet.titre,
    annee: widget.billet.annee,
    pays: widget.billet.pays,
    genres: widget.billet.genres,
    graine: widget.billet.date.millisecondsSinceEpoch,
  );
  int _i = 0;
  int _justes = 0;
  int? _reponse;

  Future<void> _choisir(int r) async {
    if (_reponse != null) return;
    setState(() => _reponse = r);
    if (r == _questions[_i].bonne) _justes++;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    if (_i + 1 < _questions.length) {
      setState(() {
        _i++;
        _reponse = null;
      });
    } else {
      await widget.etat.repondreDefiApres(justes: _justes, total: _questions.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) return const SizedBox.shrink();
    final q = _questions[_i];
    return Panneau(
      couleur: AuraCouleurs.vert,
      inclinaison: 0.01,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('DÉFI D\'APRÈS-SÉANCE · ${_i + 1}/${_questions.length}', style: AuraTexte.titre(16)),
        const SizedBox(height: 6),
        Text(q.texte, style: AuraTexte.corps(15, poids: FontWeight.w900)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (i, r) in q.reponses.indexed)
            Pastille(
              libelle: _reponse == null ? r : (i == q.bonne ? '$r ✓' : (i == _reponse ? '$r ✗' : r)),
              choisie: _reponse != null && i == q.bonne,
              autofocus: i == 0,
              onTap: () => _choisir(i),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('1 point d\'audace par bonne réponse, 2 de plus pour un sans-faute.', style: AuraTexte.corps(12, couleur: AuraCouleurs.texteDoux))),
          Pastille(libelle: 'Passer', choisie: false, onTap: widget.etat.passerDefiApres),
        ]),
      ]),
    );
  }
}


/// Le Festival (R50) et le Défi de la semaine (R52), le même pour tous.
class _LaSemaine extends StatelessWidget {
  const _LaSemaine({required this.etat});
  final EtatJeu etat;

  @override
  Widget build(BuildContext context) {
    final maintenant = DateTime.now();
    final festival = etat.festivalDe(maintenant);
    final defi = etat.defiSemaineDe(maintenant);
    if (festival == null && defi == null) return const SizedBox.shrink();
    final fait = etat.defiSemaineReussi(maintenant);
    return Panneau(
      couleur: AuraCouleurs.rose,
      inclinaison: 0.01,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (festival != null) ...[
          Text('FESTIVAL DE LA SEMAINE · ${festival.nom.toUpperCase()}', style: AuraTexte.titre(16)),
          const SizedBox(height: 4),
          Text(festival.regle, style: AuraTexte.corps(15, poids: FontWeight.w900)),
          Text('Pop : « ${festival.annonce} »', style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
        ],
        if (festival != null && defi != null) const SizedBox(height: 8),
        if (defi != null)
          Text(
            fait ? 'DÉFI DE LA SEMAINE RÉUSSI ✓ · ${defi.texte}' : 'DÉFI DE LA SEMAINE · ${defi.texte} +3 d\'audace et un booster.',
            style: AuraTexte.corps(14, poids: FontWeight.w900),
          ),
      ]),
    );
  }
}


/// « Aujourd'hui » : tout ce qui n'est pas le tirage, en pastilles. Chacune
/// ouvre son panneau en bas de l'écran, ou l'écran qui va avec.
class _Aujourdhui extends StatelessWidget {
  const _Aujourdhui({required this.etat});
  final EtatJeu etat;

  static Future<void> _feuille(BuildContext context, Widget contenu) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (c) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .8),
              child: SingleChildScrollView(child: contenu),
            ),
          ),
        ),
      );

  void _ouvrir(BuildContext context, Widget ecran) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));

  @override
  Widget build(BuildContext context) {
    final maintenant = DateTime.now();
    final generique = etat.generiqueAVoir;
    final festival = etat.festivalDe(maintenant);
    final defi = etat.defiSemaineDe(maintenant);
    final puces = <(String, IconData, Color, VoidCallback)>[
      if (etat.defiApres != null)
        ('Défi d\'après-séance !', Icons.quiz_rounded, AuraCouleurs.vert,
            () => _feuille(context, _DefiApresVue(key: ValueKey(etat.defiApres!.date), etat: etat, billet: etat.defiApres!))),
      if (generique != null) ('Le générique du mois', Icons.movie_creation_rounded, AuraCouleurs.ambre, () => _ouvrir(context, GeneriqueEcran(mois: generique))),
      if (etat.billets.isNotEmpty && etat.boostersDispo() > 0) ('Ton booster', Icons.style_rounded, AuraCouleurs.violet, () => _ouvrir(context, const DeckEcran())),
      ('Pour toi', Icons.lightbulb_rounded, AuraCouleurs.creme, () => _feuille(context, _PourToi(etat: etat))),
      ('Course contre Pop', Icons.flag_rounded, AuraCouleurs.creme, () => _feuille(context, _CourseEtSerie(etat: etat))),
      if (festival != null || defi != null)
        (festival != null ? 'Festival : ${festival.nom}' : 'Défi de la semaine', Icons.celebration_rounded, AuraCouleurs.rose, () => _feuille(context, _LaSemaine(etat: etat))),
      if (etat.ouvert(Etape.casse))
        (Casse.enCours(maintenant) ? 'Le Casse !' : 'Le Casse', Icons.lock_rounded, Casse.enCours(maintenant) ? AuraCouleurs.jaune : AuraCouleurs.creme,
            () => _ouvrir(context, const CasseEcran())),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('AUJOURD\'HUI', style: AuraTexte.titre(18, couleur: AuraCouleurs.creme)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (libelle, icone, couleur, action) in puces)
          Touchable(
            etiquette: libelle,
            onTap: action,
            builder: (context, focus, appui) => AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              transform: Matrix4.translationValues(appui ? 2 : 0, appui ? 2 : 0, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: couleur,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(width: 2.5),
                boxShadow: [
                  if (focus) const BoxShadow(color: AuraCouleurs.jaune, spreadRadius: 4),
                  if (!appui) const BoxShadow(color: AuraCouleurs.noir, offset: Offset(2, 2)),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icone, size: 18),
                const SizedBox(width: 6),
                Flexible(child: Text(libelle, style: AuraTexte.corps(14, poids: FontWeight.w900))),
              ]),
            ),
          ),
      ]),
    ]);
  }
}
