import 'package:flutter/material.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/collection.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';
import 'premier_soir.dart';
import 'reglages.dart';

/// « Quel spectateur es-tu ? » : ta figurine, ton pouvoir, ton contrat.
class ProfilEcran extends StatelessWidget {
  const ProfilEcran({super.key});

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    final p = etat.profil;
    final fait = etat.billets.length.clamp(0, p.objectif);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TitreCartoon('Quel spectateur es-tu ?', taille: 38),
              const SizedBox(height: 16),
              Transform.rotate(
                angle: -0.015,
                child: Container(
                  decoration: AuraTrait.panneau(),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        color: p.couleur,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Transform.rotate(angle: -0.07, child: Figurine.profil(p, hauteur: 130)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.nom.toUpperCase(), style: AuraTexte.titre(30)),
                                const SizedBox(height: 4),
                                Text(p.description, style: AuraTexte.corps(14)),
                              ]),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 3, thickness: 3, color: AuraCouleurs.noir),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(TextSpan(children: [
                              TextSpan(text: 'POUVOIR ${p.pouvoir.toUpperCase()} : ', style: AuraTexte.titre(16)),
                              TextSpan(text: p.effet, style: AuraTexte.corps(14)),
                            ])),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(child: Text('Contrat : ${p.contrat}', style: AuraTexte.corps(14, poids: FontWeight.w900))),
                              Text('$fait / ${p.objectif}', style: AuraTexte.titre(18)),
                            ]),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                height: 16,
                                decoration: BoxDecoration(color: Colors.white, border: Border.all(width: 2.5), borderRadius: BorderRadius.circular(8)),
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: fait / p.objectif,
                                  child: Container(color: AuraCouleurs.ambre),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text('Ton piège de saison : ${p.piege}.', style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _Collection(collection: etat.collection, position: etat.position),
              const SizedBox(height: 22),
              const TitreCartoon('Les figurines', taille: 26, inclinaison: 0),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, c) {
                final colonnes = c.maxWidth > 500 ? 4 : 2;
                return GridView.count(
                  crossAxisCount: colonnes,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: .78,
                  children: [
                    for (final (i, profil) in Profil.values.indexed)
                      Touchable(
                        etiquette: profil.nom,
                        selectionne: profil == p,
                        autofocus: profil == p,
                        onTap: () => etat.choisirProfil(profil),
                        builder: (context, focus, appui) => Transform.rotate(
                          angle: i.isEven ? -0.02 : 0.02,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 80),
                            transform: Matrix4.translationValues(appui ? 3 : 0, appui ? 3 : 0, 0),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: profil == p ? AuraCouleurs.jaune : AuraCouleurs.creme,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(width: 3),
                              boxShadow: [
                                if (focus) const BoxShadow(color: AuraCouleurs.jaune, spreadRadius: 5),
                                if (!appui) const BoxShadow(color: AuraCouleurs.noir, offset: Offset(3, 3)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: Center(child: Figurine.profil(profil, hauteur: 96))),
                                Text(profil.nom.toUpperCase(), style: AuraTexte.titre(17)),
                                Text(profil.pouvoir, style: AuraTexte.corps(12, couleur: AuraCouleurs.texteDoux)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }),
              if (etat.tauxDeValidation != null) ...[
                const SizedBox(height: 18),
                Text(
                  'Cartes jouées qui ont fini en billet : ${(etat.tauxDeValidation! * 100).round()} %',
                  style: AuraTexte.corps(13, poids: FontWeight.w900, couleur: AuraCouleurs.creme),
                ),
              ],
              const SizedBox(height: 22),
              AuraBouton(
                libelle: 'Refaire le test',
                principal: false,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremierSoirEcran(testSeul: true))),
              ),
              const SizedBox(height: 12),
              AuraBouton(
                libelle: 'Réglages',
                icone: Icons.settings_rounded,
                principal: false,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReglagesEcran())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La collection : les exploits (gardés pour toujours) et les figurines de
/// saison, qui ne reviennent jamais.
class _Collection extends StatelessWidget {
  const _Collection({required this.collection, required this.position});
  final Set<String> collection;
  final int position;

  @override
  Widget build(BuildContext context) {
    final maintenant = DateTime.now();
    final saisonDuMois = Collection.saison(maintenant);
    final saisons = collection.where((c) => c.startsWith('saison_')).toList()..sort();
    final obtenus = Collection.exploits.where((e) => collection.contains(e.id)).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TitreCartoon('Ta collection : $obtenus / ${Collection.exploits.length}', taille: 26, inclinaison: 0),
      const SizedBox(height: 10),
      Panneau(
        couleur: collection.contains(saisonDuMois) ? AuraCouleurs.ambre : AuraCouleurs.creme,
        inclinaison: -0.012,
        child: Text(
          collection.contains(saisonDuMois)
              ? '${Collection.nomDeSaison(saisonDuMois)} : gagnée ! Elle ne reviendra jamais.'
              : 'Atteins la case ${Collection.caseDeSaison} en ${Collection.mois[maintenant.month - 1]} pour gagner la figurine de saison. Elle ne reviendra jamais. (Tu es case $position.)',
          style: AuraTexte.corps(14, poids: FontWeight.w900),
        ),
      ),
      if (saisons.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Tes figurines de saison : ${saisons.map((s) => Collection.nomDeSaison(s).replaceFirst('Figurine de saison, ', '')).join(', ')}.',
            style: AuraTexte.corps(13, poids: FontWeight.w900, couleur: AuraCouleurs.creme)),
      ],
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in Collection.exploits)
          Tooltip(
            message: e.description,
            child: Container(
              width: 160,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: collection.contains(e.id) ? AuraCouleurs.jaune : const Color(0xFFD8D0C3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(width: 2.5),
                boxShadow: collection.contains(e.id) ? AuraTrait.ombre(3) : null,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(collection.contains(e.id) ? e.icone : Icons.lock_rounded, color: AuraCouleurs.noir),
                const SizedBox(height: 4),
                Text(e.nom, style: AuraTexte.corps(14, poids: FontWeight.w900)),
                Text(e.description, style: AuraTexte.corps(12, couleur: AuraCouleurs.texteDoux)),
              ]),
            ),
          ),
      ]),
    ]);
  }
}
