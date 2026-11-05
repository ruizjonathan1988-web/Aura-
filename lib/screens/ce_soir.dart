import 'package:flutter/material.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/etat.dart';
import '../services/plan_du_jour.dart';
import '../services/sources.dart';
import '../services/tirage.dart';
import '../services/vjod_lien.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';
import 'plan_du_jour.dart';

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
          _message = 'Rien à 3 étoiles ou plus pour cette envie et cette durée. Change d\'envie ou prends plus de temps.';
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(gagnees > 0
          ? 'Ton pion avance de $gagnees case${gagnees > 1 ? 's' : ''} !'
          : 'Séance gardée dans tes billets. Ton pion a déjà avancé de 3 cases aujourd\'hui.'),
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
          constraints: const BoxConstraints(maxWidth: 560),
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

  Widget _envie(EtatJeu etat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (etat.billetANoter != null) ...[
          _ANoter(billet: etat.billetANoter!),
          const SizedBox(height: 18),
        ] else if (etat.enCoursAVoir.isNotEmpty) ...[
          _AlorsCeFilm(seance: etat.enCoursAVoir.first),
          const SizedBox(height: 18),
        ],
        _CartePlanDuJour(resultat: etat.planDuJour),
        const SizedBox(height: 18),
        if (etat.jokerBluff) ...[
          Panneau(
            couleur: AuraCouleurs.vert,
            inclinaison: 0.012,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text('Joker du Bluff en main : +1 case sur ta prochaine séance.', style: AuraTexte.corps(14, poids: FontWeight.w900)),
          ),
          const SizedBox(height: 18),
        ],
        SizedBox(
          height: 150,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 120, top: 8),
                child: TitreCartoon('Qu\'est-ce qu\'on ressent ce soir ?', taille: 38),
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
              Text('COMBIEN DE TEMPS ?', style: AuraTexte.titre(16)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 10, children: [
                for (final d in Duree.values)
                  Pastille(libelle: d.libelle, choisie: d == _duree, onTap: () => setState(() => _duree = d)),
              ]),
              const SizedBox(height: 12),
              Text('Le jeu pioche dans : ${etat.source.nom}. Que des titres à 3 étoiles ou plus.',
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
      ],
    );
  }

  Widget _main() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreCartoon('Tire ta carte !', taille: 44),
        const SizedBox(height: 8),
        Text('${_emotion.libelle}, ${_duree.libelle.toLowerCase()}. Gauche et droite pour choisir, OK pour jouer.',
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
        Panneau(child: Text('${_carte.joker}.', style: AuraTexte.corps(14))),
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
    final etoiles = f.etoiles == null ? '' : '${f.etoiles!.toStringAsFixed(1).replaceAll('.', ',')} étoiles';
    final vjod = VjodLien.disponible(f);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Transform.rotate(
          angle: -0.025,
          child: Container(
            decoration: AuraTrait.panneau(),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: _carte.type.couleur,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text('CARTE RÉVÉLÉE !', style: AuraTexte.titre(16)),
                ),
                const Divider(height: 3, thickness: 3, color: AuraCouleurs.noir),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.titre.toUpperCase(), style: AuraTexte.titre(34)),
                      const SizedBox(height: 6),
                      Text(f.infos, style: AuraTexte.corps(14, couleur: AuraCouleurs.texteDoux)),
                      if (etoiles.isNotEmpty) Text(etoiles, style: AuraTexte.corps(14, poids: FontWeight.w900)),
                    ],
                  ),
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
              Text('TON PRONOSTIC : QUELLE NOTE LUI DONNERAS-TU ?', style: AuraTexte.titre(16)),
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
            libelle: 'C\'est parti, je regarde',
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
                      Text('${_emotion.libelle}, ${_carte.defi.toLowerCase()}', style: AuraTexte.corps(14, couleur: AuraCouleurs.texteDoux)),
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
              Text('TA VRAIE NOTE (TU AVAIS DIT $_pronostic)', style: AuraTexte.titre(16)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var n = 1; n <= 5; n++)
                  Pastille(libelle: '$n', choisie: n == _note, onTap: () => setState(() => _note = n)),
              ]),
              const SizedBox(height: 6),
              Text('Pop compare avec ton pronostic. Prépare-toi.', style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
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
        AuraBouton(libelle: 'Je ne l\'ai pas vu finalement', principal: false, onPressed: () => setState(() => _etape = _Etape.cartes)),
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
                        : 'Raté aujourd\'hui. Revanche demain !',
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
        Text(billet.cases > 0 ? 'BILLET VALIDÉ TOUT SEUL : +${billet.cases} !' : 'BILLET VALIDÉ TOUT SEUL !', style: AuraTexte.titre(16)),
        const SizedBox(height: 4),
        Text('Alors, ${billet.titre} ?', style: AuraTexte.titre(26)),
        const SizedBox(height: 4),
        Text('Ta note, et Pop la compare à ton pronostic (${billet.pronostic}).', style: AuraTexte.corps(13)),
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
        Text('Tu l\'as vu ? Donne ta note et ton pion avance de ${seance.cases}.', style: AuraTexte.corps(13)),
        const SizedBox(height: 10),
        _Etoiles(
          autofocus: true,
          onNote: (n) async {
            final gagnees = await etat.validerEnCours(seance, note: n);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(gagnees > 0 ? 'Billet validé : +$gagnees !' : 'Billet validé. Ton pion a déjà fait ses 3 cases ce jour-là.'),
              ));
            }
          },
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pastille(libelle: 'Pas encore vu', choisie: false, onTap: () => etat.reporterSeance(seance)),
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
