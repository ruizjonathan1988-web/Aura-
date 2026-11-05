import 'package:flutter/material.dart';

import '../app.dart';
import '../screens/plateau.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';

/// La ligue entre amis. Pour l'instant, le duel solo contre Pop ; les
/// ligues partagées arrivent avec le serveur Supabase.
class LigueEcran extends StatelessWidget {
  const LigueEcran({super.key});

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    final pop = Circuit.positionDePop(DateTime.now());
    final lignes = [
      ('Toi', etat.position, Figurine.profil(etat.profil, hauteur: 52)),
      ('Pop, le Programmateur', pop, const Figurine.pop(hauteur: 52)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TitreCartoon('Classement', taille: 40),
              const SizedBox(height: 16),
              for (final (i, l) in lignes.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panneau(
                    couleur: l.$1 == 'Toi' ? AuraCouleurs.jaune : AuraCouleurs.creme,
                    inclinaison: l.$1 == 'Toi' ? -0.02 : 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(children: [
                      Text('${i + 1}', style: AuraTexte.titre(26)),
                      const SizedBox(width: 12),
                      l.$3,
                      const SizedBox(width: 12),
                      Expanded(child: Text(l.$1, style: AuraTexte.corps(16, poids: FontWeight.w900))),
                      Text('case ${l.$2}', style: AuraTexte.titre(20)),
                    ]),
                  ),
                ),
              const SizedBox(height: 10),
              Panneau(
                couleur: AuraCouleurs.violet,
                inclinaison: 0.015,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LES LIGUES ENTRE AMIS ARRIVENT', style: AuraTexte.titre(18)),
                    const SizedBox(height: 6),
                    Text(
                      'Bientôt : inviter tes amis avec un code, l\'Affiche de la semaine, le Bluff, le Faussaire et la Révélation du dimanche sur la télé. En attendant, bats Pop en solo.',
                      style: AuraTexte.corps(14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
