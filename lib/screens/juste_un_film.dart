import 'package:flutter/material.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/etat.dart';
import '../services/juste_un_film.dart';
import '../services/sources.dart';
import '../services/traduction.dart';
import '../services/vjod_lien.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';
import '../widgets/ou_le_voir.dart';

/// « Juste un film » : pour les soirs sans jeu. Trois idées, à changer autant
/// qu'on veut, une par une ou toutes d'un coup. Rien ne compte pour le
/// plateau : pas de carte, pas de case, pas de rappel.
class JusteUnFilmEcran extends StatefulWidget {
  const JusteUnFilmEcran({super.key});

  @override
  State<JusteUnFilmEcran> createState() => _JusteUnFilmEcranState();
}

class _JusteUnFilmEcranState extends State<JusteUnFilmEcran> {
  final _choix = JusteUnFilm();
  final Map<String, List<Film>> _catalogues = {};

  Emotion? _emotion;
  Duree _duree = Duree.soiree;
  Epoque _epoque = Epoque.toutes;
  List<Film> _idees = const [];
  bool _chargement = true;
  String? _message;
  bool _premier = true;

  static const _couleurs = [AuraCouleurs.caseOrange, AuraCouleurs.caseVert, AuraCouleurs.caseBleu];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_premier) {
      _premier = false;
      _renouveler();
    }
  }

  Future<List<Film>> _catalogue(EtatJeu etat) async =>
      _catalogues['${_emotion?.name}|${_duree.name}|${_epoque.name}'] ??= await etat.source.catalogue(emotion: _emotion, duree: _duree, epoque: _epoque);

  Future<void> _renouveler() async {
    final etat = PorteeEtat.of(context);
    setState(() {
      _chargement = true;
      _message = null;
    });
    try {
      final films = await _catalogue(etat);
      final idees = _choix.proposer(films, emotion: _emotion, duree: _duree, epoque: _epoque);
      setState(() {
        _idees = idees;
        if (idees.isEmpty) {
          _message = 'Rien à 3 étoiles ou plus avec ces filtres. Élargis la durée ou l\'époque, ou choisis « Peu importe ».';
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

  Future<void> _autre(int index) async {
    final films = await _catalogue(PorteeEtat.of(context));
    setState(() => _idees = _choix.remplacer(films, _idees, index, emotion: _emotion, duree: _duree, epoque: _epoque));
  }

  void _filtre(VoidCallback changer) {
    setState(changer);
    _renouveler();
  }

  Future<void> _lancer(Film film) async {
    // Hors du jeu : on ouvre VJOD, et c'est tout.
    final erreur = await VjodLien.ouvrir(film);
    if (erreur != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erreur)));
  }

  @override
  Widget build(BuildContext context) {
    final tele = estTele(context);
    return Scaffold(
      body: FondTrame(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: tele ? 1180 : 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const EnTeteRetour(titre: 'Juste un film'),
                    const SizedBox(height: 8),
                    Text('Pas de jeu ce soir : trois idées, à changer autant que tu veux. Rien ne compte pour le plateau.',
                        style: AuraTexte.corps(15)),
                    const SizedBox(height: 16),
                    _filtres(),
                    const SizedBox(height: 18),
                    if (_message != null)
                      Panneau(couleur: AuraCouleurs.jaune, child: Text(_message!, style: AuraTexte.corps(14, poids: FontWeight.w900)))
                    else if (_chargement && _idees.isEmpty)
                      const PopQuiParle(texte: 'Je fouille les étagères…')
                    else if (tele)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final (i, f) in _idees.indexed) ...[
                          if (i > 0) const SizedBox(width: 16),
                          Expanded(child: _idee(i, f)),
                        ],
                      ])
                    else
                      for (final (i, f) in _idees.indexed) ...[
                        if (i > 0) const SizedBox(height: 16),
                        _idee(i, f),
                      ],
                    const SizedBox(height: 20),
                    AuraBouton(
                      libelle: 'Trois autres idées',
                      icone: Icons.autorenew_rounded,
                      autofocus: true,
                      onPressed: _chargement ? null : _renouveler,
                    ),
                    const SizedBox(height: 12),
                    AuraBouton(libelle: 'Finalement, je veux jouer', principal: false, onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filtres() {
    Widget rangee(String titre, List<Widget> pastilles) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: AuraTexte.titre(15)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: pastilles),
        ]);
    return Panneau(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        rangee('ENVIE', [
          Pastille(libelle: 'Peu importe', choisie: _emotion == null, onTap: () => _filtre(() => _emotion = null)),
          for (final e in Emotion.values) Pastille(libelle: e.libelle, choisie: e == _emotion, onTap: () => _filtre(() => _emotion = e)),
        ]),
        const SizedBox(height: 12),
        rangee('DURÉE', [
          for (final d in Duree.values) Pastille(libelle: d.libelle, choisie: d == _duree, onTap: () => _filtre(() => _duree = d)),
        ]),
        const SizedBox(height: 12),
        rangee('ÉPOQUE', [
          for (final e in Epoque.values) Pastille(libelle: e.libelle, choisie: e == _epoque, onTap: () => _filtre(() => _epoque = e)),
        ]),
      ]),
    );
  }

  Widget _idee(int i, Film f) {
    final etoiles = f.etoiles == null ? null : f.etoiles!.toStringAsFixed(1).replaceAll('.', ',');
    final genres = f.genres.take(3).map(Traduction.genre).join(', ');
    return Container(
      key: ValueKey(f.id),
      decoration: AuraTrait.panneau(),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: _couleurs[i % _couleurs.length],
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(f.titre.toUpperCase(), style: AuraTexte.titre(24))),
            if (etoiles != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(color: AuraCouleurs.jaune, borderRadius: BorderRadius.circular(999), border: Border.all(width: 2.5)),
                // L'étoile en icône : la police Anton n'a pas le caractère ★.
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(etoiles, style: AuraTexte.titre(15)),
                  const SizedBox(width: 3),
                  const Icon(Icons.star_rounded, size: 16),
                ]),
              ),
            ],
          ]),
        ),
        const Divider(height: 3, thickness: 3, color: AuraCouleurs.noir),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(f.infos, style: AuraTexte.corps(14, couleur: AuraCouleurs.texteDoux)),
            if (genres.isNotEmpty) Text(genres, style: AuraTexte.corps(13, poids: FontWeight.w900)),
            if ((f.synopsis ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(f.synopsis!, style: AuraTexte.corps(14, poids: FontWeight.w700)),
            ],
            const SizedBox(height: 10),
            OuLeVoir(key: ValueKey('ou${f.id}'), film: f),
            const SizedBox(height: 12),
            if (VjodLien.disponible(f)) ...[
              AuraBouton(
                // Ma TV a dit qu'il n'est pas en VOD : la fiche VJOD proposera de le demander.
                libelle: f.enVod == false ? 'Demander dans VJOD' : 'Lancer dans VJOD',
                icone: f.enVod == false ? Icons.add_rounded : Icons.play_arrow_rounded,
                onPressed: () => _lancer(f),
              ),
              const SizedBox(height: 10),
            ],
            AuraBouton(libelle: 'Une autre idée', principal: false, onPressed: () => _autre(i)),
          ]),
        ),
      ]),
    );
  }
}
