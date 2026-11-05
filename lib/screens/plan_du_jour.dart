import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/etat.dart';
import '../services/plan_du_jour.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';

/// Le Plan du jour : 3 indices à ouvrir un par un, 1 seul essai parmi 4 films.
class PlanDuJourEcran extends StatefulWidget {
  const PlanDuJourEcran({super.key});

  @override
  State<PlanDuJourEcran> createState() => _PlanDuJourEcranState();
}

class _PlanDuJourEcranState extends State<PlanDuJourEcran> {
  Future<PlanDuJour?>? _plan;
  int _ouverts = 1;
  Film? _reponse;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _plan ??= _charger(PorteeEtat.of(context));
  }

  Future<PlanDuJour?> _charger(EtatJeu etat) async {
    final films = await etat.source.catalogue(auHasard: false);
    return PlanDuJour.du(DateTime.now(), films);
  }

  Future<void> _repondre(EtatJeu etat, PlanDuJour plan, Film f) async {
    setState(() => _reponse = f);
    await etat.jouerPlanDuJour(ResultatPlan(indices: _ouverts, trouve: f.id == plan.film.id));
  }

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    return Scaffold(
      body: FondTrame(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const EnTeteRetour(titre: 'Le Plan du jour'),
                    const SizedBox(height: 16),
                    FutureBuilder<PlanDuJour?>(
                      future: _plan,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const PopQuiParle(texte: 'Je rembobine la pellicule…');
                        }
                        final plan = snap.data;
                        if (snap.hasError || plan == null) {
                          return Panneau(
                            couleur: AuraCouleurs.jaune,
                            child: Text(
                              snap.hasError
                                  ? 'Impossible de joindre ta bibliothèque. Vérifie l\'adresse dans les réglages.'
                                  : 'Pas assez de films à 3 étoiles ou plus pour jouer aujourd\'hui.',
                              style: AuraTexte.corps(14, poids: FontWeight.w900),
                            ),
                          );
                        }
                        final deja = etat.planDuJour;
                        return deja != null && _reponse == null ? _dejaJoue(deja) : _jeu(etat, plan);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _jeu(EtatJeu etat, PlanDuJour plan) {
    final fini = _reponse != null;
    final trouve = _reponse?.id == plan.film.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PopQuiParle(
          texte: !fini
              ? 'Un film, trois indices, un seul essai. Moins tu ouvres d\'indices, plus tu brilles.'
              : trouve
                  ? 'Bien joué ! Je n\'aurais pas fait mieux. Enfin, si, mais bravo.'
                  : 'Raté ! C\'était « ${plan.film.titre} ». Revanche demain.',
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Indice(numero: i + 1, texte: i < _ouverts || fini ? plan.indices[i] : null),
          ),
        if (!fini && _ouverts < 3)
          AuraBouton(libelle: 'Ouvrir l\'indice ${_ouverts + 1}', principal: false, onPressed: () => setState(() => _ouverts++)),
        const SizedBox(height: 18),
        Text(fini ? 'LA RÉPONSE' : 'TON ESSAI (UN SEUL !)', style: AuraTexte.titre(18, couleur: AuraCouleurs.creme)),
        const SizedBox(height: 10),
        for (final (i, f) in plan.choix.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ChoixLarge(
              libelle: f.titre,
              autofocus: i == 0 && !fini,
              couleur: !fini
                  ? AuraCouleurs.creme
                  : f.id == plan.film.id
                      ? AuraCouleurs.vert
                      : f.id == _reponse!.id
                          ? AuraCouleurs.caseRouge
                          : AuraCouleurs.creme,
              onTap: fini ? null : () => _repondre(etat, plan, f),
            ),
          ),
        if (fini) ...[
          const SizedBox(height: 8),
          _Partage(resultat: ResultatPlan(indices: _ouverts, trouve: trouve)),
        ],
      ],
    );
  }

  Widget _dejaJoue(ResultatPlan r) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PopQuiParle(texte: r.trouve ? 'Tu l\'as déjà trouvé aujourd\'hui. Reviens demain pour le suivant !' : 'Un seul essai par jour… Le prochain film t\'attend demain.'),
          const SizedBox(height: 16),
          _Partage(resultat: r),
        ],
      );
}

class _Indice extends StatelessWidget {
  const _Indice({required this.numero, required this.texte});
  final int numero;
  final String? texte;

  @override
  Widget build(BuildContext context) {
    final ouvert = texte != null;
    return Panneau(
      couleur: ouvert ? AuraCouleurs.creme : const Color(0xFFD8D0C3),
      inclinaison: numero.isEven ? 0.01 : -0.01,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: ouvert ? AuraCouleurs.jaune : AuraCouleurs.creme, shape: BoxShape.circle, border: Border.all(width: 2.5)),
          child: Text('$numero', style: AuraTexte.titre(17)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(texte ?? 'Indice caché', style: AuraTexte.corps(15, poids: FontWeight.w900, couleur: ouvert ? AuraCouleurs.noir : AuraCouleurs.texteDoux))),
      ]),
    );
  }
}

/// Le résultat sans spoiler, à copier pour le partager.
class _Partage extends StatelessWidget {
  const _Partage({required this.resultat});
  final ResultatPlan resultat;

  @override
  Widget build(BuildContext context) {
    final texte = resultat.partage(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panneau(
          couleur: AuraCouleurs.jaune,
          inclinaison: -0.015,
          child: Text(texte, style: AuraTexte.corps(16, poids: FontWeight.w900)),
        ),
        const SizedBox(height: 16),
        if (!estTele(context))
          AuraBouton(
            libelle: 'Copier mon résultat',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: texte));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Résultat copié, sans spoiler. Colle-le à tes amis !')));
              }
            },
          ),
      ],
    );
  }
}
