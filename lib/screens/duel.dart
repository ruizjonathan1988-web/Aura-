import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/duel.dart';
import '../services/tirage.dart';
import '../services/vjod_lien.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';

enum _Phase { joueurs, envie, table, quiz, verdict }

/// Le Duel du canapé : à deux, sur la télé, avec une seule télécommande.
/// Chacun choisit son envie et pose ses 3 cartes ; on écarte à tour de rôle
/// une carte de l'autre (un Veto chacun pour protéger la sienne) ; le
/// mini-quiz départage les deux dernières. Le gagnant prend la télécommande.
class DuelEcran extends StatefulWidget {
  const DuelEcran({super.key});

  @override
  State<DuelEcran> createState() => _DuelEcranState();
}

class _DuelEcranState extends State<DuelEcran> {
  final _hasard = math.Random();
  _Phase _phase = _Phase.joueurs;
  late final List<Profil> _joueurs = [PorteeEtat.lire(context).profil, Profil.hote];
  final _envies = <Emotion>[Emotion.frissonner, Emotion.rire];
  Duree _duree = Duree.moyenne;
  int _quiChoisit = 0;
  Duel? _duel;
  bool _modeVeto = false;
  String _bulle = '';
  String? _erreur;
  bool _chargement = false;

  // Le quiz : trois questions chacun, à tour de rôle.
  List<Question> _questions = const [];
  List<String> _reponsesMelangees = const [];
  int _question = 0;
  final _points = [0, 0];
  String? _repondu;
  int? _gagnant;

  String _nom(int j) => _joueurs[j].nom;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_joueurs[1] == _joueurs[0]) _joueurs[1] = Profil.values.firstWhere((p) => p != _joueurs[0]);
  }

  Future<void> _poserLesCartes() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    final etat = PorteeEtat.lire(context);
    try {
      final catalogue = await etat.source.catalogue();
      final tirage = Tirage(hasard: _hasard);
      final a = tirage.tirer(catalogue: catalogue, emotion: _envies[0], duree: _duree, profil: _joueurs[0]);
      final pris = a.map((c) => c.film.id).toSet();
      final b = tirage.tirer(catalogue: catalogue.where((f) => !pris.contains(f.id)).toList(), emotion: _envies[1], duree: _duree, profil: _joueurs[1]);
      if (a.length < 2 || b.length < 2) {
        _erreur = 'Pas assez de films pour ces deux envies. Essayez d\'autres envies ou plus de temps.';
      } else {
        _duel = Duel(a, b);
        _bulle = '${_nom(0)} commence. Écarte une carte de ${_nom(1)}. Choisis bien : je regarde.';
        _phase = _Phase.table;
      }
    } catch (_) {
      _erreur = 'Impossible de joindre la bibliothèque. Vérifie les réglages.';
    }
    if (mounted) setState(() => _chargement = false);
  }

  void _jouer(CarteEnJeu c) {
    final d = _duel!;
    final joueur = d.tour;
    setState(() {
      if (_modeVeto) {
        d.proteger(c);
        _modeVeto = false;
        _bulle = '${_nom(joueur)} pose son Veto : cette carte est intouchable. Malin…';
      } else {
        final sienne = c.joueur == joueur;
        d.ecarter(c);
        _bulle = sienne
            ? '${_nom(joueur)} se sépare d\'une de ses propres cartes. Il le fallait.'
            : const [
                'Adieu, petite carte. Tu ne seras pas regardée ce soir.',
                'Coup bas ! J\'adore.',
                'Et une de moins. La tension monte sur le canapé.',
                'Sans pitié. Je retiens.',
              ][_hasard.nextInt(4)];
      }
      if (d.fini) {
        _bulle = 'Il reste une carte chacun. Place au quiz : trois questions chacun, le meilleur prend la télécommande !';
        _questions = Quiz.tirer(6, _hasard);
        _melanger();
        _phase = _Phase.quiz;
      }
    });
  }

  void _melanger() => _reponsesMelangees = [..._questions[_question].reponses]..shuffle(_hasard);

  void _repondre(String r) {
    final q = _questions[_question];
    final joueur = _question % 2;
    setState(() {
      _repondu = r;
      if (r == q.bonne) _points[joueur]++;
    });
  }

  void _suivante() {
    setState(() {
      _repondu = null;
      _question++;
      if (_question >= _questions.length) {
        if (_points[0] != _points[1]) {
          _gagnant = _points[0] > _points[1] ? 0 : 1;
          _bulle = '${_nom(_gagnant!)} gagne le quiz ${_points[_gagnant!]} à ${_points[1 - _gagnant!]} et prend la télécommande !';
        } else {
          // Égalité : la carte la mieux notée l'emporte, Pop tranche.
          final f = _duel!.finalistes;
          _gagnant = (f[0].carte.film.note ?? 0) >= (f[1].carte.film.note ?? 0) ? 0 : 1;
          _bulle = 'Égalité ! Je tranche : on regarde le film le mieux noté. C\'est moi le Programmateur, après tout.';
        }
        _phase = _Phase.verdict;
      } else {
        _melanger();
      }
    });
  }

  Future<void> _valider(CarteDefi carte) async {
    final etat = PorteeEtat.lire(context);
    await etat.commencerSeance(carte, pronostic: 3);
    if (VjodLien.disponible(carte.film)) {
      final erreur = await VjodLien.ouvrir(carte.film);
      if (erreur != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erreur)));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bonne séance ! À la fin, Aura vous demandera votre note.')));
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FondTrame(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _phase == _Phase.table ? 1100 : 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const EnTeteRetour(titre: 'Le Duel du canapé'),
                    const SizedBox(height: 14),
                    switch (_phase) {
                      _Phase.joueurs => _choixJoueurs(),
                      _Phase.envie => _choixEnvie(),
                      _Phase.table => _table(),
                      _Phase.quiz => _quiz(),
                      _Phase.verdict => _verdict(),
                    },
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _choixJoueurs() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PopQuiParle(texte: 'À deux, une télécommande, six cartes. Celui qui gagne choisit le film. Qui affronte qui ?'),
          const SizedBox(height: 16),
          Text('TOI : ${_nom(0).toUpperCase()}', style: AuraTexte.titre(18, couleur: AuraCouleurs.creme)),
          const SizedBox(height: 10),
          Text('TON ADVERSAIRE CHOISIT SA FIGURINE', style: AuraTexte.titre(18, couleur: AuraCouleurs.creme)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in Profil.values.where((p) => p != _joueurs[0]))
              Pastille(libelle: p.nom, choisie: p == _joueurs[1], autofocus: p == _joueurs[1], onTap: () => setState(() => _joueurs[1] = p)),
          ]),
          const SizedBox(height: 16),
          Panneau(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('COMBIEN DE TEMPS AVEZ-VOUS ?', style: AuraTexte.titre(16)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final d in Duree.values) Pastille(libelle: d.libelle, choisie: d == _duree, onTap: () => setState(() => _duree = d)),
              ]),
            ]),
          ),
          const SizedBox(height: 18),
          AuraBouton(libelle: 'C\'est parti', onPressed: () => setState(() => _phase = _Phase.envie)),
        ],
      );

  Widget _choixEnvie() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Figurine.profil(_joueurs[_quiChoisit], hauteur: 90),
            const SizedBox(width: 12),
            Expanded(child: TitreCartoon('${_nom(_quiChoisit)}, envie de quoi ?', taille: 32)),
          ]),
          const SizedBox(height: 16),
          for (final e in Emotion.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ChoixLarge(
                libelle: e.phrase,
                autofocus: e == Emotion.values.first,
                couleur: _envies[_quiChoisit] == e ? AuraCouleurs.jaune : AuraCouleurs.creme,
                onTap: () {
                  setState(() => _envies[_quiChoisit] = e);
                  if (_quiChoisit == 0) {
                    setState(() => _quiChoisit = 1);
                  } else {
                    _poserLesCartes();
                  }
                },
              ),
            ),
          if (_quiChoisit == 1) Text('Passe la télécommande à ${_nom(1)} !', style: AuraTexte.corps(15, poids: FontWeight.w900, couleur: AuraCouleurs.creme)),
          if (_chargement) const PopQuiParle(texte: 'Je distribue les cartes…'),
          if (_erreur != null) Panneau(couleur: AuraCouleurs.jaune, child: Text(_erreur!, style: AuraTexte.corps(14, poids: FontWeight.w900))),
        ],
      );

  Widget _table() {
    final d = _duel!;
    final peutVeto = d.veto[d.tour] && d.cartes.any(d.peutProteger);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PopQuiParle(texte: _bulle, taille: 70),
        const SizedBox(height: 12),
        Panneau(
          couleur: AuraCouleurs.jaune,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            _modeVeto
                ? '${_nom(d.tour)} : choisis la carte à protéger.'
                : d.cible == d.tour
                    ? 'Au tour de ${_nom(d.tour)} : il ne reste qu\'une carte à ${_nom(d.adversaire)}, écarte une des tiennes.'
                    : 'Au tour de ${_nom(d.tour)} : écarte une carte de ${_nom(d.adversaire)}.',
            style: AuraTexte.corps(15, poids: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 14),
        for (final j in [0, 1]) ...[
          Row(children: [
            Figurine.profil(_joueurs[j], hauteur: 44),
            const SizedBox(width: 8),
            Text('${_nom(j)} · ${_envies[j].libelle}${d.veto[j] ? '' : ' · Veto utilisé'}', style: AuraTexte.titre(16, couleur: AuraCouleurs.creme)),
          ]),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, c) {
            final largeur = math.min(260.0, (c.maxWidth - 24) / 3);
            return Row(children: [
              for (final carte in d.cartes.where((x) => x.joueur == j)) ...[
                _CarteTable(
                  carte: carte,
                  largeur: largeur,
                  onTap: (_modeVeto ? d.peutProteger(carte) : d.peutEcarter(carte)) ? () => _jouer(carte) : null,
                ),
                const SizedBox(width: 8),
              ],
            ]);
          }),
          const SizedBox(height: 14),
        ],
        if (peutVeto)
          AuraBouton(
            libelle: _modeVeto ? 'Annuler le Veto' : 'Utiliser mon Veto',
            principal: false,
            onPressed: () => setState(() => _modeVeto = !_modeVeto),
          ),
      ],
    );
  }

  Widget _quiz() {
    final q = _questions[_question];
    final joueur = _question % 2;
    final fini = _repondu != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          for (final j in [0, 1])
            Expanded(
              child: Panneau(
                couleur: j == joueur ? AuraCouleurs.jaune : AuraCouleurs.creme,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  Figurine.profil(_joueurs[j], hauteur: 40),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_nom(j), style: AuraTexte.corps(14, poids: FontWeight.w900))),
                  Text('${_points[j]}', style: AuraTexte.titre(26)),
                ]),
              ),
            ),
        ].expand((w) => [w, const SizedBox(width: 8)]).toList()..removeLast()),
        const SizedBox(height: 14),
        Text('QUESTION ${_question + 1} SUR ${_questions.length}, POUR ${_nom(joueur).toUpperCase()}', style: AuraTexte.titre(16, couleur: AuraCouleurs.creme)),
        const SizedBox(height: 8),
        TitreCartoon(q.texte, taille: 30, inclinaison: -0.02),
        const SizedBox(height: 14),
        for (final (i, r) in _reponsesMelangees.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ChoixLarge(
              libelle: r,
              autofocus: i == 0 && !fini,
              couleur: !fini
                  ? AuraCouleurs.creme
                  : r == q.bonne
                      ? AuraCouleurs.vert
                      : r == _repondu
                          ? AuraCouleurs.caseRouge
                          : AuraCouleurs.creme,
              onTap: fini ? null : () => _repondre(r),
            ),
          ),
        if (fini) ...[
          PopQuiParle(texte: _repondu == q.bonne ? 'Bonne réponse ! Un point.' : 'Raté ! C\'était « ${q.bonne} ».', taille: 60),
          const SizedBox(height: 12),
          AuraBouton(
            libelle: _question + 1 < _questions.length ? 'Question suivante, pour ${_nom(1 - joueur)}' : 'Voir qui gagne',
            autofocus: true,
            onPressed: _suivante,
          ),
        ],
      ],
    );
  }

  Widget _verdict() {
    final g = _gagnant!;
    final carte = _duel!.finalistes[g].carte;
    final f = carte.film;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PopQuiParle(texte: _bulle),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Figurine.profil(_joueurs[g], hauteur: 110),
          const SizedBox(width: 12),
          Expanded(child: TitreCartoon('${_nom(g)} prend la télécommande !', taille: 32)),
        ]),
        const SizedBox(height: 14),
        Panneau(
          inclinaison: -0.015,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('LE FILM DE CE SOIR', style: AuraTexte.titre(15)),
            Text(f.titre.toUpperCase(), style: AuraTexte.titre(32)),
            Text(f.infos, style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
            if (f.synopsis != null) ...[const SizedBox(height: 6), Text(f.synopsis!, style: AuraTexte.corps(14))],
          ]),
        ),
        const SizedBox(height: 18),
        AuraBouton(
          libelle: VjodLien.disponible(f) ? 'Lancer dans VJOD' : 'C\'est parti, on le regarde',
          icone: VjodLien.disponible(f) ? Icons.play_arrow_rounded : null,
          autofocus: true,
          onPressed: () => _valider(carte),
        ),
        const SizedBox(height: 12),
        AuraBouton(
          libelle: 'Revanche !',
          principal: false,
          onPressed: () => setState(() {
            _phase = _Phase.envie;
            _quiChoisit = 0;
            _question = 0;
            _points[0] = 0;
            _points[1] = 0;
            _gagnant = null;
          }),
        ),
      ],
    );
  }
}

/// Une carte posée sur la table, retournée : on voit le défi et l'indice,
/// pas le film. Écartée, elle se grise ; protégée, elle porte un bouclier.
class _CarteTable extends StatelessWidget {
  const _CarteTable({required this.carte, required this.largeur, this.onTap});
  final CarteEnJeu carte;
  final double largeur;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = carte.carte;
    return Opacity(
      opacity: carte.ecartee ? .35 : 1,
      child: Touchable(
        etiquette: 'Carte ${c.type.libelle} : ${c.defi}${carte.protegee ? ', protégée' : ''}${carte.ecartee ? ', écartée' : ''}',
        onTap: onTap,
        builder: (context, focus, appui) => AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: largeur,
          height: largeur * 1.15,
          transform: Matrix4.translationValues(0, focus ? -8 : 0, 0),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.type.couleur,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(width: 3),
            boxShadow: [
              if (focus) const BoxShadow(color: AuraCouleurs.jaune, spreadRadius: 5),
              const BoxShadow(color: AuraCouleurs.noir, offset: Offset(3, 3)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(c.type.libelle.toUpperCase(), style: AuraTexte.titre(15))),
              if (carte.protegee) const Icon(Icons.shield_rounded, color: AuraCouleurs.noir, size: 20),
            ]),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(width: 2)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.defi, maxLines: 2, overflow: TextOverflow.ellipsis, style: AuraTexte.corps(13, poids: FontWeight.w900).copyWith(height: 1.15)),
                  const SizedBox(height: 3),
                  Expanded(child: Text(c.indice, overflow: TextOverflow.fade, style: AuraTexte.corps(11, couleur: AuraCouleurs.texteDoux))),
                ]),
              ),
            ),
            if (carte.ecartee) Center(child: Text('ÉCARTÉE', style: AuraTexte.titre(14))),
          ]),
        ),
      ),
    );
  }
}
