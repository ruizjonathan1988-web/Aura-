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
import '../services/bingo.dart';
import 'duel.dart';

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
    await _publier(PartieSoiree.distribuer(joueurs, mains, Quiz.tirer(PartieSoiree.nbQuestions, hasard), hasard, public: _publicInscrit()));
  }

  /// Pop tire le jeu au sort : le Pitch demande au moins trois joueurs.
  Future<void> _popChoisit() async {
    final pitch = _inscrits.length >= 3 && math.Random().nextBool();
    setState(() => _erreur = null);
    await (pitch ? _pitch() : _distribuer());
  }

  /// Au-delà de quatre, les inscrits forment le public.
  List<Map<String, dynamic>> _publicInscrit() => [
        for (final j in _inscrits.skip(PartieSoiree.maxJoueurs)) {'id': j['joueur_id'], 'pseudo': j['pseudo']},
      ];

  Future<void> _pitch() async {
    final etat = PorteeEtat.lire(context);
    final hasard = math.Random();
    final presents = _inscrits.take(PartieSoiree.maxJoueurs).toList();
    final catalogue = await etat.source.catalogue(auHasard: false);
    final bons = Tirage.hautDuPanier(catalogue.where((f) => !f.dejaVu && Tirage.assezBon(f)).toList(), minimum: presents.length * Pitch.parManche)
      ..shuffle(hasard);
    if (bons.length < presents.length * Pitch.parManche) {
      setState(() => _erreur = 'Pas assez de films pour le Pitch.');
      return;
    }
    final joueurs = [for (final j in presents) {'id': j['joueur_id'], 'pseudo': j['pseudo'], 'profil': j['profil']}];
    await _publier(Pitch.nouvelle(joueurs, bons, hasard, public: _publicInscrit()));
  }

  Future<void> _lancer() async {
    final etat = PorteeEtat.lire(context);
    final CarteDefi carte;
    if (_etat['mode'] == 'pitch') {
      carte = CarteDefi(
        type: TypeCarte.envie,
        defi: 'Le film du Pitch',
        indice: '',
        cases: 2,
        joker: '',
        film: PartieSoiree.filmDepuisJson((_etat['film'] as Map).cast<String, dynamic>()),
        bulleDePop: '',
      );
    } else {
      final restes = PartieSoiree.cartes(_etat).where((c) => c['ecartee'] != true).toList();
      carte = _carteDepuis(restes.firstWhere((c) => c['j'] == _etat['gagnant']));
    }
    await etat.commencerSeance(carte, pronostic: 3, aPlusieurs: true);
    etat.mesures?.noter('duel', {'soiree': true});
    // Le Bingo du film (R55) : les téléphones reçoivent leur grille.
    await _publier(BingoSoiree.demarrer(_etat, carte.film.genres, math.Random()));
    if (VjodLien.disponible(carte.film)) await VjodLien.ouvrir(carte.film);
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
                    'pitch_mots' || 'pitch_vote' || 'pitch_revele' => _pitchTele(),
                    'bingo' => _bingoTele(),
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
          AuraBouton(libelle: 'Pop choisit le jeu du soir (${_inscrits.length.clamp(2, PartieSoiree.maxJoueurs)} joueurs)', autofocus: true, onPressed: _popChoisit),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            Pastille(libelle: 'Cartes et quiz', choisie: false, onTap: _distribuer),
            if (_inscrits.length >= 3) Pastille(libelle: 'Le Pitch', choisie: false, onTap: _pitch),
          ]),
          if (_inscrits.length > PartieSoiree.maxJoueurs)
            Text('Les suivants forment le public : ils votent et soufflent depuis leur téléphone.', style: AuraTexte.corps(14, couleur: AuraCouleurs.creme)),
        ],
      ];

  Widget _publicBandeau() {
    final p = PartieSoiree.publicDe(_etat);
    if (p.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text('LE PUBLIC · ${p.map((x) => x['pseudo']).join(', ')}', style: AuraTexte.titre(16, couleur: AuraCouleurs.creme)),
    );
  }

  List<Widget> _bingoTele() {
    final b = (_etat['bingo'] as Map).cast<String, dynamic>();
    final etape = b['etape'];
    final ids = BingoSoiree.participants(_etat);
    if (etape == 'jeu') {
      return [
        const PopQuiParle(
          texte: 'Bingo du film ! Chacun a sa grille secrète sur son téléphone. Cochez en silence quand ça arrive à l\'écran. Et méfiez-vous de mes cases…',
          taille: 90,
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 12, runSpacing: 10, children: [
          for (final id in ids)
            Panneau(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text('${BingoSoiree.nomDe(_etat, id)} · ${BingoSoiree.cocheesDe(_etat, id).length} case(s)', style: AuraTexte.corps(18, poids: FontWeight.w900)),
            ),
        ]),
        const SizedBox(height: 16),
        AuraBouton(libelle: 'Générique ! On compare les grilles', autofocus: true, onPressed: () => _publier(PartieSoiree.suivante(_etat))),
      ];
    }
    final grilles = (b['grilles'] as Map).cast<String, dynamic>();
    final points = ((b['points'] as Map?) ?? const {}).cast<String, dynamic>();
    final autres = ids.length - 1;
    return [
      PopQuiParle(
        texte: etape == 'fin'
            ? 'Les comptes sont faits. Bluffer au Bingo, c\'est risqué : la salle a l\'œil.'
            : 'Voilà ce que chacun prétend avoir vu. Si vous n\'y croyez pas, contestez depuis vos téléphones !',
        taille: 80,
      ),
      const SizedBox(height: 12),
      for (final id in ids) ...[
        Text('${BingoSoiree.nomDe(_etat, id).toUpperCase()}${etape == 'fin' ? ' · ${points[id] ?? 0} POINT(S)' : ''}', style: AuraTexte.titre(20, couleur: AuraCouleurs.creme)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in BingoSoiree.cocheesDe(_etat, id))
            Panneau(
              couleur: Bingo.rejetee(BingoSoiree.contestations(_etat, id, k), autres) ? AuraCouleurs.rouge : AuraCouleurs.vert,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                '${(grilles[id] as List)[k]}${BingoSoiree.contestations(_etat, id, k) > 0 ? ' · ${BingoSoiree.contestations(_etat, id, k)} contestation(s)' : ''}',
                style: AuraTexte.corps(14, poids: FontWeight.w900),
              ),
            ),
        ]),
        const SizedBox(height: 12),
      ],
      if (etape == 'generique')
        AuraBouton(libelle: 'Les résultats', autofocus: true, onPressed: () => _publier(PartieSoiree.suivante(_etat)))
      else
        AuraBouton(libelle: 'Fin de la soirée', autofocus: true, onPressed: () => Navigator.of(context).pop()),
    ];
  }

  List<Widget> _pitchTele() {
    final joueurs = _joueursDe(_etat);
    final m = Pitch.mancheDe(_etat);
    final films = [for (final f in (m['films'] as List)) PartieSoiree.filmDepuisJson((f as Map).cast<String, dynamic>())];
    final phase = _etat['phase'];
    final revele = phase == 'pitch_revele';
    final votes = (m['votes'] as Map).cast<String, int>();
    final pts = (_etat['points'] as List).cast<int>();
    final mots = (m['mots'] as List).cast<String>();
    return [
      PopQuiParle(texte: _etat['message'] as String? ?? '', taille: 80),
      const SizedBox(height: 12),
      Row(children: [
        for (var j = 0; j < joueurs.length; j++)
          Expanded(
            child: Panneau(
              couleur: m['conteur'] == j ? AuraCouleurs.jaune : (votes.containsKey(joueurs[j]['id']) ? AuraCouleurs.vert : AuraCouleurs.creme),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Figurine.profil(Profil.depuisNom(joueurs[j]['profil'] as String?), hauteur: 44),
                const SizedBox(width: 8),
                Expanded(child: Text('${joueurs[j]['pseudo']}${m['conteur'] == j ? ' raconte' : ''}', style: AuraTexte.corps(16, poids: FontWeight.w900))),
                Text('${pts[j]}', style: AuraTexte.titre(30)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 16),
      if (mots.isNotEmpty) Center(child: TitreCartoon(mots.join(' · '), taille: 48, inclinaison: -0.02)),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, f) in films.indexed)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Panneau(
                couleur: revele && i == m['cible'] ? AuraCouleurs.vert : AuraCouleurs.creme,
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i + 1}', style: AuraTexte.titre(30)),
                  Text(f.titre, style: AuraTexte.titre(20)),
                  Text(f.infos, style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
                  if (revele)
                    Text(
                      [for (final v in votes.entries) if (v.value == i) joueurs.firstWhere((x) => x['id'] == v.key, orElse: () => {'pseudo': '?'})['pseudo']].join(', '),
                      style: AuraTexte.corps(14, poids: FontWeight.w900),
                    ),
                ]),
              ),
            ),
          ),
      ]),
      _publicBandeau(),
      const SizedBox(height: 14),
      if (phase != 'pitch_mots')
        AuraBouton(
          libelle: revele ? ((_etat['manche'] as int) + 1 < (_etat['manches'] as List).length ? 'Manche suivante' : 'Voir le gagnant') : 'Révéler maintenant',
          autofocus: true,
          principal: revele,
          onPressed: () => _publier(PartieSoiree.suivante(_etat)),
        ),
    ];
  }

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
      if (revele && ((_etat['souffles'] as List?) ?? const []).isNotEmpty)
        Text(
          'Le public a soufflé la réponse à ${((_etat['souffles'] as List).cast<int>()).map((k) => joueurs[k]['pseudo']).join(' et ')} : un point quand même !',
          style: AuraTexte.corps(16, poids: FontWeight.w900, couleur: AuraCouleurs.creme),
        ),
      _publicBandeau(),
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
  final List<String> _mots = [];
  Set<int>? _bingo;
  bool _bingoCompte = false;

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
    String nomDe(int k) => joueurs[k]['pseudo'] as String;
    if (e['phase'] == 'bingo') return _bingoManette(e, moi ?? '');
    if (j < 0) return _public(e, moi ?? '', nomDe);
    final autre = joueurs.length == 2 ? nomDe(1 - j) : 'tes adversaires';
    switch (e['phase']) {
      case 'pitch_mots' || 'pitch_vote' || 'pitch_revele':
        return _pitchManette(e, j, nomDe);
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

  List<Widget> _public(Map<String, dynamic> e, String moi, String Function(int) nomDe) {
    final k = PartieSoiree.indexPublic(e, moi);
    if (e['phase'] == 'fin') return [const PopQuiParle(texte: 'La partie est finie. Regarde la télé : qui prend la télécommande ?')];
    if (k < 0) {
      return [
        const PopQuiParle(texte: 'La partie a commencé sans toi. Rejoins le public : tu voteras, et tu pourras souffler les réponses.'),
        const SizedBox(height: 12),
        AuraBouton(libelle: 'Rejoindre le public', autofocus: true, onPressed: _envoi ? null : () => _geste({'type': 'public', 'pseudo': widget.pseudo})),
      ];
    }
    final p = PartieSoiree.publicDe(e)[k];
    final joueurs = _joueursDe(e);
    if (e['mode'] == 'pitch') {
      if (e['phase'] != 'pitch_vote') return [const PopQuiParle(texte: 'Tu es dans le public. Regarde la télé : le conteur prépare ses trois mots.')];
      final m = Pitch.mancheDe(e);
      if (((m['votes_public'] as Map?) ?? const {}).containsKey(moi)) return [const PopQuiParle(texte: 'Vote envoyé. Si le public trouve, le conteur gagne un point.')];
      return [
        TitreCartoon('Quel film ? ${(m['mots'] as List).join(' · ')}', taille: 26),
        const SizedBox(height: 10),
        for (final (i, f) in (m['films'] as List).indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChoixLarge(libelle: '${i + 1} · ${(f as Map)['titre']}', autofocus: i == 0, onTap: _envoi ? null : () => _geste({'type': 'vote', 'film': i})),
          ),
      ];
    }
    final soutien = p['soutien'] as int?;
    final widgets = <Widget>[
      Text(soutien == null ? 'QUI SOUTIENS-TU ?' : 'TU SOUTIENS ${nomDe(soutien).toUpperCase()}', style: AuraTexte.titre(16)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var j = 0; j < joueurs.length; j++) Pastille(libelle: nomDe(j), choisie: soutien == j, onTap: _envoi ? null : () => _geste({'type': 'soutenir', 'joueur': j})),
      ]),
      const SizedBox(height: 6),
      Text('Si ton joueur se trompe et que tu trouves, tu lui souffles la réponse : il garde le point.', style: AuraTexte.corps(13, couleur: AuraCouleurs.creme)),
      const SizedBox(height: 12),
    ];
    if (e['phase'] == 'quiz' && e['revele'] != true) {
      final n = e['question'] as int;
      final q = (e['questions'] as List)[n] as Map;
      if (((e['reponses_public'] as Map?) ?? const {}).containsKey(moi)) {
        widgets.add(const PopQuiParle(texte: 'Réponse envoyée. Croise les doigts pour ton joueur.'));
      } else {
        widgets.addAll([
          TitreCartoon(q['texte'] as String, taille: 24),
          const SizedBox(height: 8),
          for (final (i, r) in (q['reponses'] as List).cast<String>().indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChoixLarge(libelle: r, autofocus: i == 0, onTap: _envoi ? null : () => _geste({'type': 'reponse', 'question': n, 'choix': r})),
            ),
        ]);
      }
    } else {
      widgets.add(const PopQuiParle(texte: 'Regarde la télé : le quiz arrive bientôt.'));
    }
    return widgets;
  }

  List<Widget> _bingoManette(Map<String, dynamic> e, String moi) {
    final b = (e['bingo'] as Map).cast<String, dynamic>();
    final grille = ((b['grilles'] as Map)[moi] as List?)?.cast<String>();
    if (grille == null) return [const PopQuiParle(texte: 'Le Bingo a commencé sans toi. Regarde le film, et prépare tes contestations !')];
    final etape = b['etape'];
    if (etape == 'jeu') {
      final mes = _bingo ??= BingoSoiree.cocheesDe(e, moi);
      return [
        const TitreCartoon('Ta grille secrète', taille: 26),
        const SizedBox(height: 4),
        Text('Coche quand ça arrive. Bluffer, c\'est permis… mais le salon peut contester au générique.', style: AuraTexte.corps(13, couleur: AuraCouleurs.creme)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: Bingo.cote,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: .82,
          children: [
            for (var k = 0; k < Bingo.cases; k++)
              Touchable(
                etiquette: '${grille[k]}${mes.contains(k) ? ', cochée' : ''}',
                onTap: () {
                  setState(() {
                    if (!mes.remove(k)) mes.add(k);
                  });
                  widget.service.geste(_rejointe!, {'type': 'cocher', 'case': k});
                },
                builder: (context, focus, appui) => Panneau(
                  couleur: mes.contains(k) ? AuraCouleurs.jaune : AuraCouleurs.creme,
                  padding: const EdgeInsets.all(5),
                  child: Center(
                    child: Text(grille[k], textAlign: TextAlign.center, maxLines: 5, overflow: TextOverflow.ellipsis, style: AuraTexte.corps(10.5, poids: FontWeight.w900)),
                  ),
                ),
              ),
          ],
        ),
      ];
    }
    final ids = BingoSoiree.participants(e).where((id) => id != moi).toList();
    if (etape == 'generique') {
      final contestes = ((b['contestes'] as Map?) ?? const {}).cast<String, dynamic>();
      return [
        const TitreCartoon('Ils l\'ont vraiment vu ?', taille: 26),
        const SizedBox(height: 8),
        for (final id in ids)
          for (final k in BingoSoiree.cocheesDe(e, id))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ChoixLarge(
                libelle: '${BingoSoiree.nomDe(e, id)} : ${((b['grilles'] as Map)[id] as List)[k]}${(contestes['$id|$k'] as List? ?? const []).contains(moi) ? ' · contesté' : ' · Contester ?'}',
                onTap: _envoi || (contestes['$id|$k'] as List? ?? const []).contains(moi) ? null : () => _geste({'type': 'contester', 'qui': id, 'case': k}),
              ),
            ),
      ];
    }
    final pts = (((b['points'] as Map?) ?? const {})[moi] as num?)?.toInt() ?? 0;
    if (!_bingoCompte) {
      _bingoCompte = true;
      final etat = PorteeEtat.lire(context);
      final code = _rejointe ?? '';
      WidgetsBinding.instance.addPostFrameCallback((_) => etat.gagnerAudaceBingo(code, pts));
    }
    return [PopQuiParle(texte: 'Bingo terminé : $pts point${pts.abs() > 1 ? 's' : ''}. ${pts > 0 ? 'Ça te fait ${pts.clamp(0, 5)} d\'audace.' : 'Tu bluffes mal. Je note.'}')];
  }

  List<Widget> _pitchManette(Map<String, dynamic> e, int j, String Function(int) nomDe) {
    final m = Pitch.mancheDe(e);
    final conteur = m['conteur'] as int;
    final films = (m['films'] as List).cast<Map>();
    switch (e['phase']) {
      case 'pitch_mots':
        if (conteur != j) return [PopQuiParle(texte: '${nomDe(conteur)} choisit ses trois mots en secret. Pas de triche !')];
        final cible = films[m['cible'] as int];
        return [
          Panneau(
            couleur: AuraCouleurs.jaune,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TON FILM SECRET', style: AuraTexte.titre(14)),
              Text('${cible['titre']}', style: AuraTexte.titre(26)),
              Text('Fais-le deviner à quelques-uns, pas à tous : sinon tu ne marques rien.', style: AuraTexte.corps(13, poids: FontWeight.w900)),
            ]),
          ),
          const SizedBox(height: 12),
          Text('TROIS MOTS (${_mots.length}/${Pitch.nbMots})', style: AuraTexte.titre(16)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (i, mot) in (m['proposes'] as List).cast<String>().indexed)
              Pastille(
                libelle: mot,
                choisie: _mots.contains(mot),
                autofocus: i == 0,
                onTap: () => setState(() {
                  if (_mots.contains(mot)) {
                    _mots.remove(mot);
                  } else if (_mots.length < Pitch.nbMots) {
                    _mots.add(mot);
                  }
                }),
              ),
          ]),
          const SizedBox(height: 12),
          AuraBouton(
            libelle: 'Envoyer mes trois mots',
            onPressed: _envoi || _mots.length != Pitch.nbMots
                ? null
                : () async {
                    final choisis = [..._mots];
                    _mots.clear();
                    await _geste({'type': 'mots', 'mots': choisis});
                  },
          ),
        ];
      case 'pitch_vote':
        if (conteur == j) return [const PopQuiParle(texte: 'Ils réfléchissent… Garde ton air innocent.')];
        if ((m['votes'] as Map).containsKey(widget.service.monId)) return [const PopQuiParle(texte: 'Vote envoyé. Regarde la télé.')];
        return [
          TitreCartoon((m['mots'] as List).join(' · '), taille: 28),
          const SizedBox(height: 10),
          for (final (i, f) in films.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChoixLarge(libelle: '${i + 1} · ${f['titre']}', autofocus: i == 0, onTap: _envoi ? null : () => _geste({'type': 'vote', 'film': i})),
            ),
        ];
      default:
        return [PopQuiParle(texte: e['message'] as String? ?? 'Regarde la télé !')];
    }
  }
}

/// La Soirée jeu (R59) : une seule porte pour jouer à plusieurs. Sur la
/// télé, avec les téléphones (2 à 4 joueurs et le public) ou le Duel du
/// canapé à une seule télécommande ; sur le téléphone, rejoindre la partie
/// affichée sur la télé.
class ChoixSoireeEcran extends StatelessWidget {
  const ChoixSoireeEcran({super.key, required this.ligues});
  final ServiceLigues? ligues;

  @override
  Widget build(BuildContext context) {
    final tele = estTele(context);
    final etat = PorteeEtat.of(context);
    final l = ligues;
    void ouvrir(Widget ecran) => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ecran));
    return Scaffold(
      body: FondTrame(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const EnTeteRetour(titre: 'Soirée jeu'),
                  const SizedBox(height: 14),
                  const PopQuiParle(texte: 'On joue comment ce soir ? Celui qui gagne choisit le film. Et je compte les points, évidemment.'),
                  const SizedBox(height: 16),
                  if (l != null)
                    ChoixLarge(
                      autofocus: true,
                      couleur: AuraCouleurs.violet,
                      libelle: tele
                          ? 'AVEC VOS TÉLÉPHONES · De 2 à 4 joueurs, et le public. La télé est le plateau, chacun joue en secret. Le Pitch, le quiz, puis le Bingo pendant le film.'
                          : 'REJOINDRE LA PARTIE · Celle qui est affichée sur la télé, avec son code de 4 lettres.',
                      onTap: () => ouvrir(tele
                          ? SoireeTeleEcran(service: ServiceSoiree(l.client))
                          : SoireeManetteEcran(service: ServiceSoiree(l.client), pseudo: l.pseudo ?? etat.profil.nom.replaceFirst(RegExp(r"^(Le |L')"), ''))),
                    ),
                  const SizedBox(height: 10),
                  ChoixLarge(
                    autofocus: l == null,
                    couleur: AuraCouleurs.rose,
                    libelle: 'LE DUEL DU CANAPÉ · À deux, une seule télécommande : chacun pose ses cartes, on élimine à tour de rôle, et le quiz désigne qui choisit le film.',
                    onTap: () => ouvrir(const DuelEcran()),
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
