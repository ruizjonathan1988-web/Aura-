import 'package:flutter/material.dart';

import '../services/mise_a_jour.dart';
import '../theme/aura_theme.dart';
import 'aura_widgets.dart';

/// « Aura a une nouvelle version » : ce qui change, puis le téléchargement
/// et l'installeur d'Android. Jouable à la télécommande : le bouton
/// « Mettre à jour » a le focus.
Future<void> proposerMiseAJour(BuildContext context, NouvelleVersion v) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Panneau(
          couleur: AuraCouleurs.creme,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('AURA A UNE NOUVELLE VERSION', style: AuraTexte.titre(20)),
              const SizedBox(height: 6),
              Text('Publiée le ${v.date}.', style: AuraTexte.corps(14, couleur: AuraCouleurs.texteDoux)),
              if (v.nouveautes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('CE QUI CHANGE', style: AuraTexte.titre(15)),
                const SizedBox(height: 4),
                for (final n in v.nouveautes) Text('• $n', style: AuraTexte.corps(14, poids: FontWeight.w700)),
              ],
              const SizedBox(height: 16),
              AuraBouton(libelle: 'Mettre à jour', icone: Icons.system_update_rounded, autofocus: true, onPressed: () => Navigator.pop(context, true)),
              const SizedBox(height: 10),
              AuraBouton(libelle: 'Plus tard', principal: false, onPressed: () => Navigator.pop(context, false)),
            ]),
          ),
        ),
      ),
    ),
  );
  if (ok != true || !context.mounted) return;

  if (!await MiseAJour.peutInstaller()) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Panneau(
            couleur: AuraCouleurs.jaune,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('UNE AUTORISATION D\'ABORD', style: AuraTexte.titre(20)),
              const SizedBox(height: 8),
              Text(
                'Android doit laisser Aura installer ses mises à jour. Dans les réglages, active « Installer des applis inconnues » pour Aura, puis reviens et relance la mise à jour.',
                style: AuraTexte.corps(14, poids: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              AuraBouton(
                libelle: 'Ouvrir les réglages',
                autofocus: true,
                onPressed: () {
                  Navigator.pop(context);
                  MiseAJour.ouvrirReglages();
                },
              ),
              const SizedBox(height: 10),
              AuraBouton(libelle: 'Plus tard', principal: false, onPressed: () => Navigator.pop(context)),
            ]),
          ),
        ),
      ),
    );
    return;
  }

  if (!context.mounted) return;
  final avance = ValueNotifier<double?>(null);
  final messager = ScaffoldMessenger.of(context);
  final navigateur = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Panneau(
            couleur: AuraCouleurs.creme,
            child: ValueListenableBuilder<double?>(
              valueListenable: avance,
              builder: (context, p, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('TÉLÉCHARGEMENT…', style: AuraTexte.titre(18)),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: p, minHeight: 10, color: AuraCouleurs.caseVert, backgroundColor: Colors.black12),
                const SizedBox(height: 8),
                Text(p == null ? 'Je prépare la nouvelle version.' : '${(p * 100).round()} %', style: AuraTexte.corps(14, poids: FontWeight.w900)),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
  final erreur = await MiseAJour.installer(v, progression: (p) => avance.value = p);
  navigateur.pop();
  avance.dispose();
  if (erreur != null) messager.showSnackBar(SnackBar(content: Text(erreur)));
}
