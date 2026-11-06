import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/cadeaux.dart';
import '../services/etat.dart';
import '../services/ligues.dart';
import '../services/premier_soir.dart';
import '../services/tirage.dart';
import '../services/vjod_lien.dart';
import '../theme/aura_theme.dart';
import '../widgets/animations.dart';
import '../widgets/aura_widgets.dart';

/// Le Cadeau cacheté et le Flair, dans l'onglet Ligue : les cadeaux reçus
/// (scellés jusqu'au jour prévu), offrir un film à un ami, et le Flair de
/// chacun (la part de ses cadeaux qui ont plu).
class CadeauxVue extends StatefulWidget {
  const CadeauxVue({super.key, required this.service, required this.ligue});
  final ServiceLigues service;
  final Ligue ligue;

  @override
  State<CadeauxVue> createState() => _CadeauxVueState();
}

class _CadeauxVueState extends State<CadeauxVue> {
  late Future<(List<Classe>, List<Cadeau>)> _donnees = _charger();
  bool _offrir = false;
  String? _ami;
  Film? _film;
  DateTime? _jour;
  final _mot = TextEditingController();
  Future<List<Film>>? _propositions;
  bool _envoi = false;
  String? _message;

  Future<(List<Classe>, List<Cadeau>)> _charger() async =>
      (await widget.service.classement(widget.ligue), await widget.service.cadeaux(widget.ligue));

  @override
  void dispose() {
    _mot.dispose();
    super.dispose();
  }

  Future<List<Film>> _choix() async {
    final films = await PorteeEtat.lire(context).source.catalogue(auHasard: false);
    final bons = films.where((f) => Tirage.assezBon(f) && BluffDePop.premierePhrase(f.synopsis).isNotEmpty).toList();
    return (Tirage.hautDuPanier(bons)..shuffle(math.Random())).take(4).toList();
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

  Future<void> _jouer(EtatJeu etat, Cadeau c, String deQui) async {
    final carte = Cadeaux.carte(c, deQui);
    await etat.commencerSeance(carte, pronostic: 4);
    if (VjodLien.disponible(c.film)) {
      await VjodLien.ouvrir(c.film);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bonne séance ! Reviens noter le cadeau ici.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<Classe>, List<Cadeau>)>(
      future: _donnees,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done || snap.hasError || snap.data == null) return const SizedBox.shrink();
        final (membres, cadeaux) = snap.data!;
        return _contenu(PorteeEtat.of(context), membres, cadeaux);
      },
    );
  }

  Widget _contenu(EtatJeu etat, List<Classe> membres, List<Cadeau> cadeaux) {
    final moi = widget.service.monId;
    final maintenant = DateTime.now();
    String nom(String id) => membres.where((c) => c.joueurId == id).firstOrNull?.pseudo ?? 'un ami';
    final recus = cadeaux.where((c) => c.pour == moi).toList();
    final flair = Cadeaux.flair(cadeaux);
    if (cadeaux.any((c) => c.de == moi && (c.note ?? 0) >= 4) && !etat.collection.contains('flair')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => etat.ajouterExploit('flair'));
    }
    final blocs = <Widget>[
      const TitreCartoon('Cadeau cacheté', taille: 26, inclinaison: 0),
      for (final c in recus.where((c) => c.note == null))
        Panneau(
          couleur: AuraCouleurs.rose,
          inclinaison: 0.012,
          child: !c.ouvert
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const Icon(Icons.redeem_rounded, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('${nom(c.de)} t\'offre un film, ${Cadeaux.quand(c.ouvrirLe, maintenant)}.', style: AuraTexte.corps(15, poids: FontWeight.w900)),
                    ),
                  ]),
                  if (c.ouvrable(maintenant)) ...[
                    const SizedBox(height: 8),
                    AuraBouton(libelle: 'Ouvrir le cadeau', autofocus: true, onPressed: _envoi ? null : () => _faire(() => widget.service.ouvrirCadeau(c), 'Cadeau ouvert !')),
                  ],
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('LE CADEAU DE ${nom(c.de).toUpperCase()}', style: AuraTexte.titre(15)),
                  Entree(child: Text(c.film.titre.toUpperCase(), style: AuraTexte.titre(30))),
                  Text(c.film.infos, style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
                  if (c.mot != null) Text('« ${c.mot} »', style: AuraTexte.corps(15, poids: FontWeight.w900)),
                  const SizedBox(height: 8),
                  if (!etat.enCours.any((s) => s.filmId == c.film.id) && !etat.billets.any((b) => b.titre == c.film.titre))
                    AuraBouton(
                      libelle: VjodLien.disponible(c.film) ? 'Lancer dans VJOD (+2 cases)' : 'Jouer ce cadeau (+2 cases)',
                      autofocus: true,
                      onPressed: () => _jouer(etat, c, nom(c.de)),
                    )
                  else ...[
                    Text('Tu l\'as vu ? Ta note fera monter (ou pas) le Flair de ${nom(c.de)} :', style: AuraTexte.corps(14, poids: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (var n = 1; n <= 5; n++)
                        Pastille(libelle: '$n', choisie: false, onTap: _envoi ? null : () => _faire(() => widget.service.noterCadeau(c, n), 'Merci ! ${nom(c.de)} le saura.')),
                    ]),
                  ],
                ]),
        ),
      if (flair.isNotEmpty)
        Panneau(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('LE FLAIR DE LA LIGUE', style: AuraTexte.titre(15)),
            const SizedBox(height: 4),
            Text('La part des cadeaux de chacun qui ont plu (noté 4 ou 5).', style: AuraTexte.corps(12, couleur: AuraCouleurs.texteDoux)),
            const SizedBox(height: 6),
            for (final e in (flair.entries.toList()..sort((a, b) => (b.value.$1 / b.value.$2).compareTo(a.value.$1 / a.value.$2))))
              Text('${e.key == moi ? 'Toi' : nom(e.key)} : Flair ${Cadeaux.pourcentage(e.value)} (${e.value.$1} sur ${e.value.$2})',
                  style: AuraTexte.corps(14, poids: FontWeight.w900)),
          ]),
        ),
      if (!_offrir)
        AuraBouton(
          libelle: 'Offrir un film à un ami',
          icone: Icons.card_giftcard_rounded,
          principal: false,
          onPressed: membres.length < 2 ? null : () => setState(() {
                _offrir = true;
                _propositions ??= _choix();
              }),
        )
      else
        _formulaire(membres, moi),
      if (_message != null) Panneau(couleur: AuraCouleurs.jaune, child: Text(_message!, style: AuraTexte.corps(14, poids: FontWeight.w900))),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, b) in blocs.indexed) ...[if (i > 0) const SizedBox(height: 12), b],
    ]);
  }

  Widget _formulaire(List<Classe> membres, String? moi) {
    final dates = Cadeaux.dates(DateTime.now());
    return Panneau(
      couleur: AuraCouleurs.rose,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('POUR QUI ?', style: AuraTexte.titre(15)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in membres.where((c) => c.joueurId != moi)) Pastille(libelle: c.pseudo, choisie: _ami == c.joueurId, onTap: () => setState(() => _ami = c.joueurId)),
        ]),
        const SizedBox(height: 12),
        Text('QUEL FILM ?', style: AuraTexte.titre(15)),
        const SizedBox(height: 6),
        FutureBuilder<List<Film>>(
          future: _propositions,
          builder: (context, snap) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
        const SizedBox(height: 6),
        Text('À OUVRIR QUAND ?', style: AuraTexte.titre(15)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (libelle, d) in dates) Pastille(libelle: libelle, choisie: _jour == d, onTap: () => setState(() => _jour = d)),
        ]),
        const SizedBox(height: 12),
        Text('UN PETIT MOT (FACULTATIF)', style: AuraTexte.titre(15)),
        const SizedBox(height: 6),
        ChampAura(controleur: _mot, indication: 'Tu vas adorer la fin', longueurMax: 120),
        const SizedBox(height: 12),
        AuraBouton(
          libelle: _envoi ? 'Emballage…' : 'Sceller et offrir',
          onPressed: _envoi || _ami == null || _film == null || _jour == null
              ? null
              : () => _faire(() async {
                    await widget.service.offrir(widget.ligue, pour: _ami!, film: _film!, ouvrirLe: _jour!, mot: _mot.text);
                    _offrir = false;
                    _ami = null;
                    _film = null;
                    _jour = null;
                    _mot.clear();
                  }, 'Cadeau scellé ! Il s\'ouvrira le jour prévu.'),
        ),
        const SizedBox(height: 8),
        AuraBouton(libelle: 'Annuler', principal: false, onPressed: () => setState(() => _offrir = false)),
      ]),
    );
  }
}
