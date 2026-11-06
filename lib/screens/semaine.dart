import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/affiche.dart';
import '../services/etat.dart';
import '../services/premier_soir.dart';
import '../services/vjod_lien.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';
import 'revelation.dart';

/// La semaine : l'Affiche choisie par le Programmateur, la séance, le Curseur,
/// et la Révélation du dimanche. En solo, Pop programme ; le Bluff et le
/// Faussaire demandent une ligue.
class SemaineEcran extends StatefulWidget {
  const SemaineEcran({super.key});

  @override
  State<SemaineEcran> createState() => _SemaineEcranState();
}

class _SemaineEcranState extends State<SemaineEcran> {
  Future<Affiche?>? _affiche;
  double? _curseur;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _affiche ??= _charger(PorteeEtat.of(context));
  }

  Future<Affiche?> _charger(EtatJeu etat) async {
    final films = await etat.source.catalogue(auHasard: false);
    return Affiche.de(DateTime.now(), films, EtatJeu.jourDe);
  }

  bool _vue(EtatJeu etat, Affiche a) {
    final lundi = Affiche.lundiDe(DateTime.now());
    return etat.billets.any((b) => b.titre == a.film.titre && !b.date.isBefore(lundi));
  }

  Future<void> _jaiVu(EtatJeu etat, Affiche a) async {
    final carte = CarteDefi(
      type: TypeCarte.affiche,
      defi: 'L\'Affiche de la semaine',
      indice: '',
      cases: 2,
      joker: '',
      film: a.film,
      bulleDePop: '',
    );
    final gagnees = await etat.validerSeance(carte, pronostic: 3);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(gagnees > 0 ? 'Séance de l\'Affiche validée : +$gagnees ! Place ton Curseur.' : 'Séance validée. Ton pion a déjà fait ses 3 cases aujourd\'hui.'),
    ));
  }

  Future<void> _lancer(Film f) async {
    final erreur = await VjodLien.ouvrir(f);
    if (erreur != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erreur)));
  }

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: FutureBuilder<Affiche?>(
            future: _affiche,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const PopQuiParle(texte: 'Je choisis l\'Affiche de la semaine…');
              }
              final a = snap.data;
              if (snap.hasError || a == null) {
                return Panneau(
                  couleur: AuraCouleurs.jaune,
                  child: Text(
                    snap.hasError ? 'Impossible de joindre ta bibliothèque. Vérifie l\'adresse dans les réglages.' : 'Pas de film à afficher cette semaine.',
                    style: AuraTexte.corps(14, poids: FontWeight.w900),
                  ),
                );
              }
              return _contenu(etat, a);
            },
          ),
        ),
      ),
    );
  }

  BluffDePop? _bluffCache;
  String? _bluffCle;
  int? _choixBluff;

  /// Le Bluff de la semaine, tiré une fois (même ordre toute la semaine).
  BluffDePop? _bluff(Affiche a) {
    if (_bluffCle != a.semaine) {
      _bluffCle = a.semaine;
      _bluffCache = BluffDePop.pourFilm(a.film, math.Random(a.semaine.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) % 1000003)));
    }
    return _bluffCache;
  }

  Widget _bluffVue(EtatJeu etat, Affiche a, BluffDePop b) {
    final fini = _choixBluff != null;
    return Panneau(
      couleur: AuraCouleurs.rose,
      inclinaison: 0.01,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('LE BLUFF DE LA SEMAINE', style: AuraTexte.titre(18)),
        const SizedBox(height: 8),
        PopQuiParle(
          taille: 60,
          texte: !fini
              ? 'Avant de le regarder : un seul de ces résumés est le vrai. J\'ai écrit les deux autres. Trouve le vrai pour gagner un Joker (+1 case).'
              : _choixBluff == b.vrai
                  ? 'Encore toi ! Bon, voilà ton Joker. Je ferai mieux la semaine prochaine.'
                  : 'Je t\'ai eu ! Le vrai, c\'était l\'autre. Rendez-vous la semaine prochaine.',
        ),
        const SizedBox(height: 10),
        for (final (i, t) in b.synopsis.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChoixLarge(
              libelle: t,
              autofocus: i == 0,
              couleur: !fini
                  ? AuraCouleurs.creme
                  : i == b.vrai
                      ? AuraCouleurs.vert
                      : i == _choixBluff
                          ? AuraCouleurs.caseRouge
                          : AuraCouleurs.creme,
              onTap: fini ? null : () => setState(() => _choixBluff = i),
            ),
          ),
        if (fini)
          AuraBouton(
            libelle: 'Continuer',
            autofocus: true,
            onPressed: () {
              etat.jouerBluff(a.semaine, trouve: _choixBluff == b.vrai);
              setState(() => _choixBluff = null);
            },
          ),
      ]),
    );
  }

  Widget _contenu(EtatJeu etat, Affiche a) {
    final vue = _vue(etat, a);
    final place = etat.curseurDe(a.semaine);
    final dimanche = Affiche.jourDeRevelation(DateTime.now());
    final bluff = etat.bluffDe(a.semaine);
    final etapes = [
      ('Bluff', bluff == null ? 'à jouer' : (bluff ? 'gagné' : 'perdu'), bluff != null),
      ('Séance', vue ? 'vue' : 'à voir', vue),
      ('Curseur', place != null ? 'placé' : 'après', place != null),
      ('Révélation', 'dimanche', dimanche && place != null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panneau(
          inclinaison: -0.017,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('L\'AFFICHE DE LA SEMAINE', style: AuraTexte.titre(16)),
            const SizedBox(height: 4),
            Text(a.film.titre.toUpperCase(), style: AuraTexte.titre(34)),
            const SizedBox(height: 4),
            Text('${a.film.infos}. Choisi par Pop, Programmateur de la semaine.', style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          for (final (i, e) in etapes.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  color: e.$3 ? AuraCouleurs.jaune : AuraCouleurs.creme,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(width: 2.5),
                  boxShadow: AuraTrait.ombre(2),
                ),
                child: Column(children: [
                  Text(e.$1.toUpperCase(), style: AuraTexte.titre(13)),
                  Text(e.$2, style: AuraTexte.corps(11)),
                ]),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 18),
        if (bluff == null && _bluff(a) != null) ...[
          _bluffVue(etat, a, _bluff(a)!),
          const SizedBox(height: 18),
        ],
        if (!vue) ...[
          if (VjodLien.disponible(a.film)) ...[
            AuraBouton(libelle: 'Lancer dans VJOD', icone: Icons.play_arrow_rounded, autofocus: true, onPressed: () => _lancer(a.film)),
            const SizedBox(height: 12),
          ],
          AuraBouton(libelle: 'Je l\'ai vu : +2 cases', principal: !VjodLien.disponible(a.film), onPressed: () => _jaiVu(etat, a)),
        ] else
          Panneau(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('LE CURSEUR : ${a.question.toUpperCase()}', style: AuraTexte.titre(16)),
              const SizedBox(height: 4),
              // Un Curseur placé reste caché jusqu'à la Révélation : la télé est partagée.
              if (place == null || dimanche) Row(children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AuraCouleurs.rouge,
                      inactiveTrackColor: Colors.white,
                      thumbColor: AuraCouleurs.ambre,
                      trackHeight: 8,
                    ),
                    child: Slider(
                      value: _curseur ?? (place ?? 5).toDouble(),
                      min: 0,
                      max: 10,
                      divisions: 10,
                      autofocus: place == null,
                      onChanged: place != null ? null : (v) => setState(() => _curseur = v),
                    ),
                  ),
                ),
                SizedBox(width: 44, child: Text('${(_curseur ?? (place ?? 5)).round()}', textAlign: TextAlign.right, style: AuraTexte.titre(30))),
              ]),
              const SizedBox(height: 6),
              if (place == null) ...[
                Text('Flèches gauche et droite pour régler. Ton Curseur reste secret jusqu\'à dimanche.', style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
                const SizedBox(height: 12),
                AuraBouton(
                  libelle: 'Placer mon Curseur',
                  onPressed: () => etat.placerCurseur(a.semaine, (_curseur ?? 5).round()),
                ),
              ] else
                Text(
                  dimanche
                      ? (etat.revelationFaite(a.semaine) ? 'Révélation faite. Nouvelle Affiche lundi !' : 'C\'est dimanche : place à la Révélation, idéalement sur la télé.')
                      : 'Curseur placé. Rendez-vous dimanche pour la Révélation.',
                  style: AuraTexte.corps(14, poids: FontWeight.w900),
                ),
              if (dimanche) ...[
                const SizedBox(height: 12),
                AuraBouton(
                  libelle: 'Lancer la Révélation',
                  autofocus: place != null,
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RevelationEcran(affiche: a))),
                ),
              ],
            ]),
          ),
        const SizedBox(height: 18),
        Panneau(
          couleur: AuraCouleurs.violet,
          inclinaison: 0.017,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('EN LIGUE, ÇA SE CORSE', style: AuraTexte.titre(18)),
            const SizedBox(height: 6),
            Text(
              'Le Programmateur change chaque semaine. Dans le Bluff, le vrai synopsis se cache parmi les faux écrits par tes amis ; un Faussaire n\'a pas vu le film ; et la Révélation se joue le dimanche, sur la télé.',
              style: AuraTexte.corps(14),
            ),
          ]),
        ),
      ],
    );
  }
}
