import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/duel.dart';
import '../services/ligues.dart';
import '../services/soiree.dart';
import '../services/tirage.dart';
import '../services/vjod_lien.dart';
import '../theme/aura_theme.dart';
import '../widgets/animations.dart';
import '../widgets/aura_widgets.dart';
import '../widgets/ou_le_voir.dart';

CarteDefi _carteDepuis(Map<String, dynamic> c) => CarteDefi(
      type: TypeCarte.values.firstWhere((t) => t.name == c['type'], orElse: () => TypeCarte.envie),
      defi: c['defi'] as String,
      indice: (c['indice'] as String?) ?? '',
      cases: (c['cases'] as int?) ?? 1,
      joker: '',
      film: PartieSoiree.filmDepuisJson((c['film'] as Map).cast<String, dynamic>()),
      bulleDePop: '',
    );

List<Map<String, dynamic>> _joueursDe(Map<String, dynamic> e) => ((e['joueurs'] as List?) ?? const []).cast<Map<String, dynamic>>();

/// La télé, plateau de la Soirée jeu : elle affiche le code, la table, le
/// quiz et le gagnant ; elle applique les gestes reçus des téléphones.
class SoireeTeleEcran extends StatefulWidget {
  const SoireeTeleEcran({super.key, required this.service});
  final ServiceSoiree service;

  @override
  State<SoireeTeleEcran> createState() => _SoireeTeleEcranState();
}

class _SoireeTeleEcranState extends State<SoireeTeleEcran> {
  String? _code;
  String? _erreur;
  Map<String, dynamic> _etat = PartieSoiree.nouvelle();
  List<Map<String, dynamic>> _inscrits = const [];
  int _dernierGeste = 0;
  Timer? _boucle;
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    _ouvrir();
  }

  Future<void> _ouvrir() async {
    try {
      final code = await widget.service.ouvrir();
      if (!mounted) return;
      setState(() => _code = code);
      _boucle = Timer.periodic(const Duration(milliseconds: 1500), (_) => _tic());
    } on ErreurLigue catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    }
  }

  @override
  void dispose() {
    _boucle?.cancel();
    super.dispose();
  }

  Future<void> _tic() async {
    final code = _code;
    if (code == null || _occupe || !mounted) return;
    _occupe = true;
    try {
      if (_etat['phase'] == 'attente') {
        final j = await widget.service.joueurs(code);
        if (mounted) setState(() => _inscrits = j);
      } else {
        final gestes = await widget.service.gestes(code, _dernierGeste);
        var e = _etat;
        var change = false;
        for (final (id, joueur, action) in gestes) {
          _dernierGeste = id;
          final suivant = PartieSoiree.appliquer(e, joueur, action);
          if (suivant != null) {
            e = suivant;
            change = true;
          }
        }
        if (change) await _publier(e);
      }
    } catch (_) {
      // Réseau capricieux : on réessaie au prochain passage.
    } finally {
      _occupe = false;
    }
  }

  Future<void> _publier(Map<String, dynamic> e) async {
    if (mounted) setState(() => _etat = e);
    await widget.service.ecrireEtat(_code!, e);
  }

  Future<void> _distribuer() async {
    final etat = PorteeEtat.lire(context);
    final hasard = math.Random();
    final presents = _inscrits.take(PartieSoiree.maxJoueurs).toList();
    final catalogue = await etat.source.catalogue();
    final tirage = Tirage(hasard: hasard);
    Emotion envie(Map j) => Emotion.values.firstWhere((x) => x.name == j['envie'], orElse: () => Emotion.frissonner);
    Profil profil(Map j) => Profil.depuisNom(j['profil'] as String?);
    final pris = <String>{};
    final mains = <List<CarteDefi>>[];
    for (final j in presents) {
      final main = tirage.tirer(catalogue: catalogue.where((f) => !pris.contains(f.id)).toList(), emotion: envie(j), duree: Duree.soiree, profil: profil(j));
      if (main.length < 3) {
        setState(() => _erreur = 'Pas assez de films pour l\'envie de ${j['pseudo']}. Changez d\'envie sur vos téléphones.');
        return;
      }
      pris.addAll(main.map((c) => c.film.id));
      mains.add(main);
    }
    final joueurs = [for (final j in presents) {'id': j['joueur_id'], 'pseudo': j['pseudo'], 'profil': j['profil']}];
    await _publier(PartieSoiree.distribuer(joueurs, mains, Quiz.tirer(PartieSoiree.nbQuestions, hasard), hasard));
  }

  Future<void> _lancer() async {
    final etat = PorteeEtat.lire(context);
    final restes = PartieSoiree.cartes(_etat).where((c) => c['ecartee'] != true).toList();
    final carte = _carteDepuis(restes.firstWhere((c) => c['j'] == _etat['gagnant']));
    await etat.commencerSeance(carte, pronostic: 3, aPlusieurs: true);
    etat.mesures?.noter('duel', {'soiree': true});
    if (VjodLien.disponible(carte.film)) await VjodLien.ouvrir(carte.film);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final phase = _etat['phase'];
    return Scaffold(
      body: FondTrame(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const EnTeteRetour(titre: 'Soirée jeu'),
                  const SizedBox(height: 16),
                  if (_erreur != null) Panneau(couleur: AuraCouleurs.jaune, child: Text(_erreur!, style: AuraTexte.corps(16, poids: FontWeight.w900))),
                  if (_code == null && _erreur == null) const PopQuiParle(texte: 'J\'installe le plateau…'),
                  if (_code != null) ...switch (phase) {
                    'attente' => _attente(),
                    'table' => _table(),
                    'quiz' => _quiz(),
                    _ => _fin(),
                  },
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _attente() => [
        Panneau(
          couleur: AuraCouleurs.jaune,
          inclinaison: -0.015,
          child: Column(children: [
            Text('LE CODE DE LA SOIRÉE', style: AuraTexte.titre(20)),
            Text(_code!, style: AuraTexte.titre(96).copyWith(letterSpacing: 18)),
            Text('Sur vos téléphones : Aura, Ce soir, puis « Rejoindre une soirée jeu ».', textAlign: TextAlign.center, style: AuraTexte.corps(18, poids: FontWeight.w900)),
          ]),
        ),
        const SizedBox(height: 18),
        Wrap(spacing: 16, runSpacing: 12, children: [
          for (final j in _inscrits)
            Entree(
              child: Panneau(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Figurine.profil(Profil.depuisNom(j['profil'] as String?), hauteur: 70),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(j['pseudo'] as String, style: AuraTexte.titre(24)),
                    Text(Emotion.values.firstWhere((e) => e.name == j['envie'], orElse: () => Emotion.frissonner).libelle, style: AuraTexte.corps(15)),
                  ]),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 18),
        if (_inscrits.length < PartieSoiree.minJoueurs)
          PopQuiParle(texte: _inscrits.isEmpty ? 'J\'attends de 2 à 4 joueurs. Sortez vos téléphones !' : 'Encore un joueur au moins, et on commence.')
        else ...[
          if (_inscrits.length > PartieSoiree.maxJoueurs)
            Text('Quatre joueurs au plus : les premiers arrivés jouent.', style: AuraTexte.corps(15, poids: FontWeight.w900, couleur: AuraCouleurs.creme)),
          AuraBouton(libelle: 'Distribuer les cartes (${_inscrits.length.clamp(2, PartieSoiree.maxJoueurs)} joueurs)', autofocus: true, onPressed: _distribuer),
        ],
      ];

  List<Widget> _table() {
    final joueurs = _joueursDe(_etat);
    final cartes = PartieSoiree.cartes(_etat);
    return [
      PopQuiParle(texte: _etat['message'] as String? ?? '', taille: 90),
      const SizedBox(height: 14),
      for (var j = 0; j < joueurs.length; j++) ...[
        Row(children: [
          Figurine.profil(Profil.depuisNom(joueurs[j]['profil'] as String?), hauteur: joueurs.length > 2 ? 44 : 56),
          const SizedBox(width: 10),
          Text('${joueurs[j]['pseudo']}${_etat['tour'] == j ? ' · à toi de jouer !' : ''}', style: AuraTexte.titre(22, couleur: AuraCouleurs.creme)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          for (final (i, c) in cartes.indexed)
            if (c['j'] == j)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Opacity(
                    opacity: c['ecartee'] == true ? .3 : 1,
                    child: Panneau(
                      couleur: _carteDepuis(c).type.couleur,
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${i + 1} · ${_carteDepuis(c).type.libelle.toUpperCase()}', style: AuraTexte.titre(16))),
                          if (c['protegee'] == true) const Icon(Icons.shield_rounded),
                        ]),
                        Text(c['defi'] as String, style: AuraTexte.corps(15, poids: FontWeight.w900)),
                        Text(c['indice'] as String? ?? '', style: AuraTexte.corps(12, couleur: AuraCouleurs.texteDoux)),
                        if (c['ecartee'] == true) Text('ÉCARTÉE', style: AuraTexte.titre(16)),
                      ]),
                    ),
                  ),
                ),
              ),
        ]),
        const SizedBox(height: 16),
      ],
    ];
  }

  List<Widget> _quiz() {
    final n = _etat['question'] as int;
    final q = (_etat['questions'] as List)[n] as Map;
    final joueurs = _joueursDe(_etat);
    final reponses = (_etat['reponses'] as Map).cast<String, dynamic>();
    final revele = _etat['revele'] == true;
    final pts = (_etat['points'] as List).cast<int>();
    return [
      Row(children: [
        for (var j = 0; j < joueurs.length; j++)
          Expanded(
            child: Panneau(
              couleur: reponses.containsKey(joueurs[j]['id']) ? AuraCouleurs.vert : AuraCouleurs.creme,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Figurine.profil(Profil.depuisNom(joueurs[j]['profil'] as String?), hauteur: 48),
                const SizedBox(width: 8),
                Expanded(child: Text('${joueurs[j]['pseudo']}${reponses.containsKey(joueurs[j]['id']) ? ' a répondu' : ''}', style: AuraTexte.corps(16, poids: FontWeight.w900))),
                Text('${pts[j]}', style: AuraTexte.titre(32)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 16),
      Text('QUESTION ${n + 1} SUR ${(_etat['questions'] as List).length} · RÉPONDEZ SUR VOS TÉLÉPHONES', style: AuraTexte.titre(18, couleur: AuraCouleurs.creme)),
      const SizedBox(height: 8),
      TitreCartoon(q['texte'] as String, taille: 40, inclinaison: -0.02),
      const SizedBox(height: 14),
      for (final r in (q['reponses'] as List).cast<String>())
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panneau(
            couleur: revele && r == q['bonne'] ? AuraCouleurs.vert : AuraCouleurs.creme,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(r, style: AuraTexte.corps(20, poids: FontWeight.w900)),
          ),
        ),
      const SizedBox(height: 10),
      AuraBouton(
        libelle: revele ? 'Question suivante' : 'Révéler la réponse',
        autofocus: true,
        principal: revele,
        onPressed: () => _publier(PartieSoiree.suivante(_etat)),
      ),
    ];
  }

  List<Widget> _fin() {
    final joueurs = _joueursDe(_etat);
    final g = _etat['gagnant'] as int;
    final film = PartieSoiree.filmDepuisJson((_etat['film'] as Map).cast<String, dynamic>());
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Rebond(declencheur: g, sauts: 3, hauteur: 14, auDemarrage: true, child: Figurine.profil(Profil.depuisNom(joueurs[g]['profil'] as String?), hauteur: 140)),
        const SizedBox(width: 16),
        Expanded(child: TitreCartoon('${joueurs[g]['pseudo']} prend la télécommande !', taille: 52)),
      ]),
      const SizedBox(height: 18),
      Panneau(
        inclinaison: -0.012,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('LE FILM DE CE SOIR', style: AuraTexte.titre(18)),
          Text(film.titre.toUpperCase(), style: AuraTexte.titre(44)),
          Text(film.infos, style: AuraTexte.corps(16, couleur: AuraCouleurs.texteDoux)),
          if (film.synopsis != null) Text(film.synopsis!, style: AuraTexte.corps(18)),
        ]),
      ),
      const SizedBox(height: 12),
      OuLeVoir(film: film),
      const SizedBox(height: 18),
      AuraBouton(
        libelle: VjodLien.disponible(film) ? 'Lancer dans VJOD' : 'C\'est parti, on le regarde',
        icone: VjodLien.disponible(film) ? Icons.play_arrow_rounded : null,
        autofocus: true,
        onPressed: _lancer,
      ),
    ];
  }
}

/// Le téléphone, manette de la Soirée jeu : on rejoint avec le code, on
/// choisit son envie, puis on joue ses coups et ses réponses en secret.
class SoireeManetteEcran extends StatefulWidget {
  const SoireeManetteEcran({super.key, required this.service, required this.pseudo});
  final ServiceSoiree service;
  final String pseudo;

  @override
  State<SoireeManetteEcran> createState() => _SoireeManetteEcranState();
}

class _SoireeManetteEcranState extends State<SoireeManetteEcran> {
  final _code = TextEditingController();
  Emotion _envie = Emotion.frissonner;
  String? _rejointe;
  String? _erreur;
  Map<String, dynamic>? _etat;
  Timer? _boucle;
  bool _veto = false;
  bool _envoi = false;

  @override
  void dispose() {
    _boucle?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _rejoindre() async {
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    final etat = PorteeEtat.lire(context);
    try {
      final code = _code.text.trim().toUpperCase();
      await widget.service.rejoindre(code, pseudo: widget.pseudo, profil: etat.profil, envie: _envie);
      _rejointe = code;
      _boucle = Timer.periodic(const Duration(milliseconds: 1500), (_) => _lire());
      await _lire();
    } on ErreurLigue catch (e) {
      _erreur = e.message;
    }
    if (mounted) setState(() => _envoi = false);
  }

  Future<void> _lire() async {
    final code = _rejointe;
    if (code == null || !mounted) return;
    try {
      final e = await widget.service.etat(code);
      if (mounted) setState(() => _etat = e);
    } catch (_) {}
  }

  Future<void> _geste(Map<String, dynamic> action) async {
    setState(() => _envoi = true);
    try {
      await widget.service.geste(_rejointe!, action);
      _veto = false;
    } on ErreurLigue catch (e) {
      _erreur = e.message;
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _lire();
    if (mounted) setState(() => _envoi = false);
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
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const EnTeteRetour(titre: 'Soirée jeu'),
                  const SizedBox(height: 16),
                  if (_erreur != null) ...[
                    Panneau(couleur: AuraCouleurs.jaune, child: Text(_erreur!, style: AuraTexte.corps(14, poids: FontWeight.w900))),
                    const SizedBox(height: 12),
                  ],
                  ...(_rejointe == null ? _formulaire() : _manette()),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _formulaire() => [
        const PopQuiParle(texte: 'Le code est sur la télé. Entre-le, choisis ton envie, et à toi de jouer !'),
        const SizedBox(height: 14),
        Panneau(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('LE CODE DE LA SOIRÉE', style: AuraTexte.titre(16)),
            const SizedBox(height: 8),
            ChampAura(controleur: _code, indication: '4 lettres', longueurMax: 4, majuscules: true),
            const SizedBox(height: 12),
            Text('TON ENVIE', style: AuraTexte.titre(16)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in Emotion.values) Pastille(libelle: e.libelle, choisie: e == _envie, onTap: () => setState(() => _envie = e)),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        AuraBouton(libelle: _envoi ? 'Connexion…' : 'Rejoindre la soirée', onPressed: _envoi ? null : _rejoindre),
      ];

  List<Widget> _manette() {
    final e = _etat;
    if (e == null || e['phase'] == 'attente') {
      return [const PopQuiParle(texte: 'Tu es dans la soirée ! Regarde la télé : on attend que tout le monde arrive.')];
    }
    final moi = widget.service.monId;
    final j = PartieSoiree.indexDe(e, moi ?? '');
    final joueurs = _joueursDe(e);
    if (j < 0) return [const PopQuiParle(texte: 'La partie a commencé sans toi… Tu joueras la prochaine !')];
    String nomDe(int k) => joueurs[k]['pseudo'] as String;
    final autre = joueurs.length == 2 ? nomDe(1 - j) : 'tes adversaires';
    switch (e['phase']) {
      case 'table':
        if (e['tour'] != j) return [PopQuiParle(texte: 'Au tour de ${nomDe(e['tour'] as int)}. Regarde la télé et prépare ton coup.')];
        final cartes = PartieSoiree.cartes(e);
        final possibles = [
          for (var i = 0; i < cartes.length; i++)
            if (_veto ? PartieSoiree.peutProteger(e, i) : PartieSoiree.peutEcarter(e, i)) i,
        ];
        final vetoPossible = [for (var i = 0; i < cartes.length; i++) i].any((i) => PartieSoiree.peutProteger(e, i));
        return [
          TitreCartoon(_veto ? 'Protège une de tes cartes' : (PartieSoiree.doitEcarterLaSienne(e) ? 'Écarte une de tes cartes' : 'Écarte une carte de $autre'), taille: 30),
          const SizedBox(height: 12),
          for (final (k, i) in possibles.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChoixLarge(
                libelle: '${cartes[i]['j'] == j ? 'Ta carte' : 'Carte de ${nomDe(cartes[i]['j'] as int)}'} · ${cartes[i]['defi']}\n${cartes[i]['indice'] ?? ''}',
                couleur: _carteDepuis(cartes[i]).type.couleur,
                autofocus: k == 0,
                onTap: _envoi ? null : () => _geste({'type': _veto ? 'veto' : 'ecarter', 'carte': i}),
              ),
            ),
          if (vetoPossible) AuraBouton(libelle: _veto ? 'Annuler le Veto' : 'Utiliser mon Veto', principal: false, onPressed: () => setState(() => _veto = !_veto)),
        ];
      case 'quiz':
        final n = e['question'] as int;
        final q = (e['questions'] as List)[n] as Map;
        final reponses = (e['reponses'] as Map).cast<String, dynamic>();
        final mienne = reponses[moi] as String?;
        if (e['revele'] == true) {
          return [
            PopQuiParle(texte: mienne == q['bonne'] ? 'Bonne réponse ! Un point.' : 'Raté ! C\'était « ${q['bonne']} ». Regarde la télé.'),
          ];
        }
        if (mienne != null) return [const PopQuiParle(texte: 'Réponse envoyée. On attend l\'autre joueur…')];
        return [
          TitreCartoon(q['texte'] as String, taille: 28),
          const SizedBox(height: 12),
          for (final (k, r) in (q['reponses'] as List).cast<String>().indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChoixLarge(libelle: r, autofocus: k == 0, onTap: _envoi ? null : () => _geste({'type': 'reponse', 'question': n, 'choix': r})),
            ),
        ];
      default:
        final g = e['gagnant'] as int?;
        return [
          PopQuiParle(texte: g == j ? 'Tu as gagné ! Tu prends la télécommande : le film démarre sur la télé.' : '${g == null ? 'Quelqu\'un' : nomDe(g)} a gagné et prend la télécommande. Revanche à la prochaine soirée !'),
        ];
    }
  }
}

/// La pastille d'accès à la Soirée jeu, dans Ce soir : sur la télé, on ouvre
/// le plateau ; sur le téléphone, on rejoint avec le code.
class AccesSoiree extends StatelessWidget {
  const AccesSoiree({super.key, required this.ligues});
  final ServiceLigues ligues;

  @override
  Widget build(BuildContext context) {
    final tele = estTele(context);
    final etat = PorteeEtat.of(context);
    return ChoixLarge(
      libelle: tele
          ? 'SOIRÉE JEU · De 2 à 4 joueurs : la télé devient le plateau, vos téléphones les manettes, chacun joue ses cartes en secret.'
          : 'SOIRÉE JEU · Rejoindre la partie affichée sur la télé, avec son code.',
      couleur: AuraCouleurs.violet,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => tele
            ? SoireeTeleEcran(service: ServiceSoiree(ligues.client))
            : SoireeManetteEcran(service: ServiceSoiree(ligues.client), pseudo: ligues.pseudo ?? etat.profil.nom.replaceFirst(RegExp(r"^(Le |L')"), '')),
      )),
    );
  }
}
