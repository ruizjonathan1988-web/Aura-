import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../services/generique.dart';
import '../theme/aura_theme.dart';
import '../widgets/animations.dart';
import '../widgets/aura_widgets.dart';

/// Le générique de fin de la saison, qui défile comme au cinéma.
class GeneriqueEcran extends StatefulWidget {
  const GeneriqueEcran({super.key, required this.mois});

  /// Le premier jour du mois raconté.
  final DateTime mois;

  @override
  State<GeneriqueEcran> createState() => _GeneriqueEcranState();
}

class _GeneriqueEcranState extends State<GeneriqueEcran> with SingleTickerProviderStateMixin {
  late final _defile = AnimationController(vsync: this, duration: const Duration(seconds: 18))..forward();

  @override
  void dispose() {
    _defile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    final maintenant = DateTime.now();
    final enCours = widget.mois.year == maintenant.year && widget.mois.month == maintenant.month;
    final resultat = etat.resultatDeSaison(widget.mois);
    final lignes = Generique.lignes(
      mois: widget.mois,
      billets: etat.billets,
      position: enCours ? etat.position : (resultat?.$1 ?? 1),
      positionDePop: enCours ? etat.positionDePop : (resultat?.$2 ?? 1),
      terminee: !enCours,
    );
    final texte = Column(
      children: [
        for (final (i, l) in lignes.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: i < 2
                ? TitreCartoon(l, taille: i == 0 ? 26 : 40, inclinaison: 0)
                : Text(l, textAlign: TextAlign.center, style: AuraTexte.corps(i == 3 ? 15 : 19, poids: FontWeight.w900, couleur: AuraCouleurs.creme)),
          ),
        const SizedBox(height: 16),
        Image.asset('assets/marque/pop.png', height: 110, semanticLabel: 'Pop, la mascotte VJOD'),
      ],
    );
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C0B),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const EnTeteRetour(titre: 'Le générique'),
            const SizedBox(height: 10),
            Expanded(
              child: animationsReduites(context)
                  ? SingleChildScrollView(child: texte)
                  : LayoutBuilder(
                      builder: (context, c) => ClipRect(
                        child: AnimatedBuilder(
                          animation: _defile,
                          builder: (context, enfant) => OverflowBox(
                            alignment: Alignment.topCenter,
                            maxHeight: double.infinity,
                            child: Transform.translate(
                              // Le texte monte du bas de l'écran jusqu'à s'arrêter sur Pop.
                              offset: Offset(0, c.maxHeight * (1 - Curves.easeOut.transform(_defile.value))),
                              child: enfant,
                            ),
                          ),
                          child: texte,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            if (!estTele(context))
              AuraBouton(
                libelle: 'Copier pour partager',
                principal: false,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: Generique.partage(lignes)));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Générique copié !')));
                },
              ),
            const SizedBox(height: 8),
            AuraBouton(
              libelle: 'Fermer',
              autofocus: true,
              onPressed: () {
                etat.generiqueVu(widget.mois);
                Navigator.of(context).pop();
              },
            ),
          ]),
        ),
      ),
    );
  }
}
