import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/aura.dart';
import '../services/cadeaux.dart';
import '../services/config.dart';
import '../services/etat.dart';
import '../services/ligues.dart';
import '../services/recherche_films.dart';
import '../services/service_aura.dart';
import '../services/tirage.dart';
import '../services/vjod_lien.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';

/// Les mots qu'on peut joindre, sans clavier (la télé n'en a pas). Les mêmes
/// que dans VJOD.
const motsAura = <String?>[null, 'Tu vas adorer.', 'Fais-moi confiance.', 'Pour un soir de pluie.', 'On en parle après ?'];

/// L'aura (R47, R48) : ce qu'on te propose, proposer un film à la maison ou
/// à un ami de ligue, et le classement.
class AuraEcran extends StatefulWidget {
  const AuraEcran({super.key, required this.ligues});
  final ServiceLigues ligues;

  @override
  State<AuraEcran> createState() => _AuraEcranState();
}

class _AuraEcranState extends State<AuraEcran> {
  late final ServiceAura _aura = ServiceAura(widget.ligues);
  Future<(List<Proposition>, List<Destinataire>)>? _donnees;
  Future<List<Film>>? _idees;

  bool _proposer = false;
  Destinataire? _pour;
  Film? _film;
  String? _mot;
  DateTime? _ouvrirLe;
  bool _envoi = false;
  String? _message;

  // R67 : chercher le film à proposer.
  final _recherche = TextEditingController();
  Timer? _attente;
  String? _cherche;
  Future<List<Film>>? _trouves;

  @override
  void initState() {
    super.initState();
    _recherche.addListener(_auTexte);
  }

  @override
  void dispose() {
    _attente?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  void _auTexte() {
    _attente?.cancel();
    final q = RechercheFilms.aChercher(_recherche.text);
    if (q == _cherche) return;
    _attente = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final etat = PorteeEtat.lire(context);
      setState(() {
        _cherche = q;
        _film = null;
        _trouves = q == null
            ? null
            : RechercheFilms(
                connexion: etat.mode == ModeJeu.vjod && etat.connexion.complete ? etat.connexion : null,
                cleTmdb: Config.tmdbCle,
              ).chercher(q);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _donnees ??= _charger();
  }

  Future<(List<Proposition>, List<Destinataire>)> _charger() async {
    final etat = PorteeEtat.lire(context);
    if (etat.mode == ModeJeu.vjod && etat.connexion.complete && _aura.maison == null) await _aura.relier(etat.connexion);
    var toutes = await _aura.propositions();
    if (etat.mode == ModeJeu.vjod && await _aura.verifierJellyfin(etat.connexion, toutes.where(_aura.pourMoi).toList())) {
      toutes = await _aura.propositions();
    }
    return (toutes, await _aura.destinataires());
  }

  Future<List<Film>> _choix() async {
    final films = await PorteeEtat.lire(context).source.catalogue(auHasard: false);
    final bons = films.where((f) => !f.dejaVu && Tirage.assezBon(f)).toList();
    return (Tirage.hautDuPanier(bons)..shuffle(math.Random())).take(6).toList();
  }

  Future<void> _faire(Future<void> Function() action, String reussite) async {
    setState(() {
      _envoi = true;
      _message = null;
    });
    try {
      await action();
      _message = reussite;
      _donnees = _charger();
    } on ErreurLigue catch (e) {
      _message = e.message;
    }
    if (mounted) setState(() => _envoi = false);
  }

  Film _filmDe(Proposition p) => Film(
        id: p.jellyfin ?? 'tmdb:${p.tmdb}',
        titre: p.titre,
        annee: p.annee,
        tmdbId: p.tmdb,
        serveurId: _aura.maison,
        source: p.jellyfin != null ? SourceFilm.jellyfin : SourceFilm.catalogueVjod,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FondTrame(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const EnTeteRetour(
                    titre: 'L\'aura',
                    regle: 'Propose des films et des séries à la maison (les profils de ton serveur VJOD) et à tes amis de ligue, depuis Aura ou depuis VJOD.\n'
                        'Ton aura grandit : +1 quand on regarde ce que tu as proposé, +2 quand on l\'aime (un cœur, ou une note de 4 ou 5), et +3 de plus quand plusieurs personnes aiment le même film.\n'
                        'Un film peut être cacheté jusqu\'à un jour choisi : l\'autre voit qui l\'envoie et quand l\'ouvrir, jamais le titre avant.',
                  ),
                  const SizedBox(height: 14),
                  const PopQuiParle(texte: 'Propose des films. Plus ils plaisent, plus ton aura grandit. La mienne est naturelle.'),
                  const SizedBox(height: 16),
                  FutureBuilder<(List<Proposition>, List<Destinataire>)>(
                    future: _donnees,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) return const PopQuiParle(texte: 'Je mesure ton aura…');
                      if (snap.hasError || snap.data == null) {
                        return Panneau(
                          couleur: AuraCouleurs.jaune,
                          child: Text('${snap.error ?? 'Le serveur ne répond pas.'}', style: AuraTexte.corps(14, poids: FontWeight.w900)),
                        );
                      }
                      final (toutes, pour) = snap.data!;
                      return _contenu(toutes, pour);
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

  Widget _contenu(List<Proposition> toutes, List<Destinataire> destinataires) {
    final recues = toutes.where((p) => _aura.pourMoi(p) && p.note == null && !(p.vu && p.aime)).toList();
    final faites = toutes.where(_aura.deMoi).toList();
    // L'exploit « Fin limier » : une de mes propositions a été aimée.
    final etat = PorteeEtat.lire(context);
    if (faites.any((p) => p.aimee) && !etat.collection.contains('flair')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => etat.ajouterExploit('flair'));
    }
    final maintenant = DateTime.now();
    final classement = Aura.classement(toutes);
    final moi = _aura.moi;
    final rang = classement.indexWhere((c) => c.qui == moi || (widget.ligues.monId != null && c.qui == widget.ligues.monId));
    final monAura = rang < 0 ? 0 : classement[rang].aura;
    final blocs = <Widget>[
      Panneau(
        couleur: AuraCouleurs.jaune,
        inclinaison: -0.012,
        child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TON AURA : $monAura', style: AuraTexte.titre(26)),
              Text(
                rang < 0 ? 'Propose un film pour entrer au classement.' : '${rang == 0 ? '1re' : '${rang + 1}e'} place sur ${classement.length}.',
                style: AuraTexte.corps(14, poids: FontWeight.w900),
              ),
            ]),
          ),
        ]),
      ),
      if (recues.isNotEmpty) ...[
        Text('ON TE PROPOSE', style: AuraTexte.titre(18)),
        for (final (i, p) in recues.indexed) _Recue(p: p, maintenant: maintenant, autofocus: i == 0, film: _filmDe(p), envoi: _envoi, noter: (n) => _faire(() => _aura.marquer(p, aime: n >= 4, note: n), 'Merci ! ${p.deNom} le saura.')),
      ],
      if (!_proposer)
        AuraBouton(
          libelle: 'Proposer un film',
          icone: Icons.auto_awesome_rounded,
          autofocus: recues.isEmpty,
          onPressed: destinataires.isEmpty
              ? null
              : () => setState(() {
                    _proposer = true;
                    _idees ??= _choix();
                  }),
        )
      else
        _formulaire(destinataires),
      if (destinataires.isEmpty)
        Text(
          'Personne à qui proposer pour l\'instant : rejoins une ligue, ou active Aura dans VJOD sur les autres profils de la maison (Réglages, L\'essentiel).',
          style: AuraTexte.corps(13, couleur: AuraCouleurs.creme),
        ),
      if (_message != null) Panneau(couleur: AuraCouleurs.jaune, child: Text(_message!, style: AuraTexte.corps(14, poids: FontWeight.w900))),
      if (classement.isNotEmpty)
        Panneau(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('LE CLASSEMENT DE L\'AURA', style: AuraTexte.titre(16)),
            const SizedBox(height: 6),
            for (final (i, c) in classement.take(10).indexed)
              Text('${i + 1}. ${i == rang ? 'Toi' : c.nom} : ${c.aura}', style: AuraTexte.corps(15, poids: i == rang ? FontWeight.w900 : FontWeight.w700)),
          ]),
        ),
      if (faites.isNotEmpty)
        Panneau(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CE QUE TU AS PROPOSÉ', style: AuraTexte.titre(16)),
            const SizedBox(height: 6),
            for (final p in faites.take(12))
              Text(
                '${p.titre} à ${p.pourNom} : ${p.cachetee(maintenant) ? 'cacheté, ${Cadeaux.quand(p.ouvrirLe!, maintenant)}' : p.aimee ? 'aimé !' : p.vu ? 'vu' : 'pas encore vu'}',
                style: AuraTexte.corps(14, poids: FontWeight.w700),
              ),
          ]),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, b) in blocs.indexed) ...[if (i > 0) const SizedBox(height: 12), b],
    ]);
  }

  Widget _formulaire(List<Destinataire> destinataires) {
    return Panneau(
      couleur: AuraCouleurs.rose,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('POUR QUI ?', style: AuraTexte.titre(15)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (i, d) in destinataires.indexed)
            Pastille(
              libelle: d.maison ? '${d.nom} (maison)' : d.nom,
              choisie: _pour == d,
              autofocus: i == 0,
              onTap: () => setState(() => _pour = d),
            ),
        ]),
        const SizedBox(height: 12),
        Text('QUEL FILM ?', style: AuraTexte.titre(15)),
        const SizedBox(height: 6),
        ChampAura(controleur: _recherche, indication: 'Chercher un film…'),
        const SizedBox(height: 6),
        if (_cherche != null)
          Text('Ce que j\'ai trouvé :', style: AuraTexte.corps(13, poids: FontWeight.w900))
        else
          Text('Ou une de mes idées :', style: AuraTexte.corps(13, poids: FontWeight.w900)),
        const SizedBox(height: 6),
        FutureBuilder<List<Film>>(
          future: _cherche != null ? _trouves : _idees,
          builder: (context, snap) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_cherche != null && snap.connectionState == ConnectionState.done && (snap.data ?? const []).isEmpty)
              Text('Aucun film à ce nom.', style: AuraTexte.corps(14)),
            for (final f in snap.data ?? const <Film>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ChoixLarge(
                  libelle: '${f.titre}\n${f.infos}',
                  couleur: _film?.id == f.id ? AuraCouleurs.jaune : AuraCouleurs.creme,
                  onTap: () => setState(() => _film = f),
                ),
              ),
          ]),
        ),
        if (_cherche == null)
          AuraBouton(
            libelle: 'D\'autres idées',
            principal: false,
            onPressed: () => setState(() {
              _film = null;
              _idees = _choix();
            }),
          ),
        const SizedBox(height: 12),
        Text('UN MOT ?', style: AuraTexte.titre(15)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in motsAura) Pastille(libelle: m ?? 'Sans mot', choisie: _mot == m, onTap: () => setState(() => _mot = m)),
        ]),
        const SizedBox(height: 12),
        Text('CACHETÉ ?', style: AuraTexte.titre(15)),
        Text('Le titre reste caché jusqu\'au jour choisi : la surprise s\'ouvre ce soir-là.', style: AuraTexte.corps(13, poids: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pastille(libelle: 'Non, tout de suite', choisie: _ouvrirLe == null, onTap: () => setState(() => _ouvrirLe = null)),
          for (final (nom, date) in Cadeaux.dates(DateTime.now()).skip(1))
            Pastille(libelle: nom, choisie: _ouvrirLe == date, onTap: () => setState(() => _ouvrirLe = date)),
        ]),
        const SizedBox(height: 12),
        AuraBouton(
          libelle: _envoi ? 'Envoi…' : 'Proposer',
          onPressed: _envoi || _pour == null || _film == null
              ? null
              : () {
                  final d = _pour!;
                  final f = _film!;
                  final quand = _ouvrirLe;
                  _faire(() async {
                    await _aura.proposer(d, f, mot: _mot, ouvrirLe: quand);
                    _proposer = false;
                    _pour = null;
                    _film = null;
                    _mot = null;
                    _ouvrirLe = null;
                  },
                      quand == null
                          ? 'Proposé à ${d.nom} ! Ton aura grandira s\'il le regarde.'
                          : 'Cacheté pour ${d.nom}, ${Cadeaux.quand(quand, DateTime.now())}. Chut.');
                },
        ),
        const SizedBox(height: 8),
        AuraBouton(libelle: 'Annuler', principal: false, onPressed: () => setState(() => _proposer = false)),
      ]),
    );
  }
}

class _Recue extends StatelessWidget {
  const _Recue({required this.p, required this.maintenant, required this.film, required this.noter, required this.envoi, this.autofocus = false});

  final Proposition p;
  final DateTime maintenant;
  final Film film;
  final void Function(int) noter;
  final bool envoi;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    if (p.cachetee(maintenant)) {
      // Cacheté (R60) : qui l'envoie et quand l'ouvrir, jamais le titre.
      return Panneau(
        couleur: AuraCouleurs.violet,
        inclinaison: -0.01,
        child: Row(children: [
          const Icon(Icons.lock_rounded, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('UN FILM CACHETÉ DE ${p.deNom.toUpperCase()}', style: AuraTexte.titre(16)),
              Text('${Cadeaux.quand(p.ouvrirLe!, maintenant)[0].toUpperCase()}${Cadeaux.quand(p.ouvrirLe!, maintenant).substring(1)}. Pas avant.', style: AuraTexte.corps(15, poids: FontWeight.w900)),
              if (p.mot != null) Text('« ${p.mot} »', style: AuraTexte.corps(14, poids: FontWeight.w700)),
            ]),
          ),
        ]),
      );
    }
    final ouvertAujourdhui = p.ouvrirLe != null && !p.cachetee(maintenant) && maintenant.difference(p.ouvrirLe!).inDays < 1;
    return Panneau(
      couleur: AuraCouleurs.rose,
      inclinaison: 0.01,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(ouvertAujourdhui ? 'LE FILM CACHETÉ DE ${p.deNom.toUpperCase()} S\'OUVRE !' : '${p.deNom.toUpperCase()} TE PROPOSE', style: AuraTexte.titre(14)),
        Text('${p.titre}${p.annee != null ? ' (${p.annee})' : ''}', style: AuraTexte.titre(26)),
        if (p.mot != null) Text('« ${p.mot} »', style: AuraTexte.corps(15, poids: FontWeight.w900)),
        const SizedBox(height: 8),
        if (VjodLien.disponible(film))
          AuraBouton(
            libelle: 'Ouvrir dans VJOD',
            autofocus: autofocus,
            onPressed: () async {
              final erreur = await VjodLien.ouvrir(film, lecture: false);
              if (erreur != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erreur)));
            },
          ),
        const SizedBox(height: 8),
        Text('Tu l\'as vu ? Ta note fait grandir (ou pas) l\'aura de ${p.deNom} :', style: AuraTexte.corps(14, poids: FontWeight.w900)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var n = 1; n <= 5; n++) Pastille(libelle: '$n', choisie: p.note == n, autofocus: autofocus && !VjodLien.disponible(film) && n == 1, onTap: envoi ? null : () => noter(n)),
        ]),
      ]),
    );
  }
}
