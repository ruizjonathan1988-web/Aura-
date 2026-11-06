import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/ce_soir.dart';
import 'screens/ligue.dart';
import 'screens/plateau.dart';
import 'screens/premier_soir.dart';
import 'screens/profil.dart';
import 'screens/semaine.dart';
import 'services/etat.dart';
import 'services/mise_a_jour.dart';
import 'theme/aura_theme.dart';
import 'widgets/animations.dart';
import 'widgets/aura_widgets.dart';
import 'widgets/fenetre_mise_a_jour.dart';

/// Donne l'état du joueur à tous les écrans, et les reconstruit quand il change.
class PorteeEtat extends InheritedNotifier<EtatJeu> {
  const PorteeEtat({super.key, required EtatJeu etat, required super.child}) : super(notifier: etat);

  static EtatJeu of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PorteeEtat>()!.notifier!;

  /// Pour agir hors de build (rappels, retour dans l'appli) sans s'abonner.
  static EtatJeu lire(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PorteeEtat>()!.notifier!;
}

class AuraApp extends StatelessWidget {
  const AuraApp({super.key, required this.etat});
  final EtatJeu etat;

  @override
  Widget build(BuildContext context) {
    return PorteeEtat(
      etat: etat,
      child: MaterialApp(
        title: 'Aura',
        debugShowCheckedModeBanner: false,
        theme: construireTheme(),
        // La touche OK des télécommandes Android TV valide partout.
        shortcuts: {
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
        },
        home: const _Depart(),
      ),
    );
  }
}

/// Chaque lancement s'ouvre comme une séance de cinéma (rideau, Pop, titre,
/// figurines). Puis le premier soir au tout premier lancement, et le jeu.
class _Depart extends StatefulWidget {
  const _Depart();

  @override
  State<_Depart> createState() => _DepartState();
}

class _DepartState extends State<_Depart> {
  bool _dansLaSalle = false;

  @override
  Widget build(BuildContext context) {
    if (!_dansLaSalle) return Ouverture(onEntrer: () => setState(() => _dansLaSalle = true));
    return PorteeEtat.of(context).accueilFait ? const Coquille() : const PremierSoirEcran();
  }
}

enum Onglet {
  ceSoir('Ce soir', Icons.style_rounded),
  plateau('Plateau', Icons.flag_rounded),
  semaine('Semaine', Icons.local_movies_rounded),
  ligue('Ligue', Icons.emoji_events_rounded),
  profil('Profil', Icons.face_rounded);

  const Onglet(this.libelle, this.icone);
  final String libelle;
  final IconData icone;

  /// Les onglets de la barre ; le Profil s'ouvre depuis la pastille en haut.
  static const barre = [ceSoir, plateau, semaine, ligue];
}

/// La structure de l'appli : en-tête, écran courant, et navigation en bas
/// (téléphone) ou en haut (télé, écran large).
class Coquille extends StatefulWidget {
  const Coquille({super.key});

  @override
  State<Coquille> createState() => _CoquilleState();
}

class _CoquilleState extends State<Coquille> with WidgetsBindingObserver {
  Onglet _onglet = Onglet.ceSoir;

  /// La nouvelle version trouvée : tant qu'elle n'est pas installée, un
  /// bouton « Mise à jour » reste dans l'en-tête, même après « Plus tard ».
  NouvelleVersion? _nouvelle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _miseAJour());
    MiseAJour.ecouter();
    MiseAJour.echec.addListener(_echecMiseAJour);
  }

  /// Une nouvelle version d'Aura ? On la propose (au plus une fois par heure).
  Future<void> _miseAJour() async {
    final v = await MiseAJour.verifier();
    if (v == null || !mounted) return;
    final deja = _nouvelle?.publieeLe == v.publieeLe;
    setState(() => _nouvelle = v);
    if (!deja) await proposerMiseAJour(context, v);
  }

  void _echecMiseAJour() {
    final m = MiseAJour.echec.value;
    if (m == null || !mounted) return;
    MiseAJour.echec.value = null;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mise à jour pas installée'),
        content: Text(m),
        actions: [TextButton(autofocus: true, onPressed: () => Navigator.pop(context), child: const Text('Compris'))],
      ),
    );
  }

  @override
  void dispose() {
    MiseAJour.echec.removeListener(_echecMiseAJour);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Au retour dans Aura (après VJOD, par exemple), on regarde si le film
  /// de la carte jouée a été vu : le billet se crée tout seul.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PorteeEtat.lire(context).verifierSeances();
      _miseAJour();
    }
  }

  void _aller(Onglet o) => setState(() => _onglet = o);

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    final tele = estTele(context);
    final ecran = switch (_onglet) {
      Onglet.ceSoir => CeSoirEcran(versPlateau: () => _aller(Onglet.plateau)),
      Onglet.plateau => const PlateauEcran(),
      Onglet.semaine => const SemaineEcran(),
      Onglet.ligue => const LigueEcran(),
      Onglet.profil => const ProfilEcran(),
    };
    return PopScope(
      canPop: _onglet == Onglet.ceSoir,
      onPopInvokedWithResult: (aQuitte, _) {
        if (!aQuitte) _aller(Onglet.ceSoir);
      },
      child: Scaffold(
        body: FondTrame(
          child: SafeArea(
            bottom: false,
            child: FocusTraversalGroup(
              child: Column(
                children: [
                  _EnTete(
                    position: etat.position,
                    onProfil: () => _aller(Onglet.profil),
                    onLigue: () => _aller(Onglet.ligue),
                    onMiseAJour: _nouvelle == null ? null : () => proposerMiseAJour(context, _nouvelle!),
                    onglets: tele ? _Onglets(actif: _onglet, onChoisir: _aller, compact: true) : null,
                  ),
                  Expanded(child: KeyedSubtree(key: ValueKey(_onglet), child: ecran)),
                  if (!tele) _Onglets(actif: _onglet, onChoisir: _aller),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete({required this.position, required this.onProfil, required this.onLigue, this.onMiseAJour, this.onglets});

  final int position;
  final VoidCallback onProfil;
  final VoidCallback onLigue;
  final VoidCallback? onMiseAJour;
  final Widget? onglets;

  static List<BoxShadow> _ombres(bool focus, bool appui) => [
        if (focus) const BoxShadow(color: AuraCouleurs.jaune, spreadRadius: 4),
        if (!appui) const BoxShadow(color: AuraCouleurs.noir, offset: Offset(3, 3)),
      ];

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    final ligues = etat.ligues;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const TitreCartoon('Aura', taille: 34, inclinaison: -0.05),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 2, 6, 2),
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(7), border: Border.all(width: 2)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('un jeu ', style: AuraTexte.corps(11, poids: FontWeight.w900, couleur: AuraCouleurs.creme)),
                  Image.asset('assets/marque/vjod-transparent.png', height: 15, semanticLabel: 'VJOD'),
                ]),
              ),
            ],
          ),
          if (onglets != null) ...[const SizedBox(width: 24), Expanded(child: onglets!)] else const Spacer(),
          Touchable(
            etiquette: 'Voir la ligue : tu es case $position sur 30',
            onTap: onLigue,
            builder: (context, focus, appui) => Container(
              padding: const EdgeInsets.fromLTRB(4, 2, 11, 2),
              decoration: BoxDecoration(
                color: AuraCouleurs.creme,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(width: 3),
                boxShadow: _ombres(focus, appui),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Figurine.profil(etat.profil, hauteur: 36),
                Transform.translate(offset: const Offset(-9, 0), child: const Figurine.pop(hauteur: 36)),
                Text('$position/30', style: AuraTexte.corps(14, poids: FontWeight.w900)),
              ]),
            ),
          ),
          if (onMiseAJour != null) ...[
            const SizedBox(width: 8),
            Touchable(
              etiquette: 'Une nouvelle version d\'Aura est prête : mettre à jour',
              onTap: onMiseAJour!,
              builder: (context, focus, appui) => Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AuraCouleurs.jaune,
                  shape: BoxShape.circle,
                  border: Border.all(width: 3),
                  boxShadow: _ombres(focus, appui),
                ),
                child: const Icon(Icons.system_update_rounded, color: AuraCouleurs.noir),
              ),
            ),
          ],
          const SizedBox(width: 8),
          ListenableBuilder(
            listenable: ligues ?? etat,
            builder: (context, _) {
              final pseudo = ligues?.pseudo;
              return Touchable(
                etiquette: 'Mon profil : ${etat.profil.nom}',
                onTap: onProfil,
                builder: (context, focus, appui) => Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: etat.profil.couleur,
                    shape: BoxShape.circle,
                    border: Border.all(width: 3),
                    boxShadow: _ombres(focus, appui),
                  ),
                  child: pseudo == null || pseudo.isEmpty
                      ? const Icon(Icons.face_rounded, color: AuraCouleurs.noir)
                      : Text(pseudo.characters.first.toUpperCase(), style: AuraTexte.titre(20)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Onglets extends StatelessWidget {
  const _Onglets({required this.actif, required this.onChoisir, this.compact = false});

  final Onglet actif;
  final ValueChanged<Onglet> onChoisir;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rangee = Row(
      children: [
        for (final o in Onglet.barre)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Touchable(
                etiquette: o.libelle,
                selectionne: o == actif,
                onTap: () => onChoisir(o),
                onFocus: compact ? () => onChoisir(o) : null,
                builder: (context, focus, appui) => Container(
                  height: 58,
                  decoration: BoxDecoration(
                    color: o == actif ? AuraCouleurs.jaune : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: o == actif || focus ? Border.all(width: 2.5) : null,
                    boxShadow: focus ? const [BoxShadow(color: AuraCouleurs.jaune, spreadRadius: 3)] : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!compact) Icon(o.icone, size: 20, color: AuraCouleurs.noir),
                      Text(o.libelle.toUpperCase(), style: AuraTexte.titre(compact ? 17 : 14)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    if (compact) return rangee;
    return Container(
      decoration: const BoxDecoration(
        color: AuraCouleurs.creme,
        border: Border(top: BorderSide(width: 3)),
      ),
      padding: EdgeInsets.fromLTRB(8, 6, 8, 8 + MediaQuery.paddingOf(context).bottom),
      child: rangee,
    );
  }
}
