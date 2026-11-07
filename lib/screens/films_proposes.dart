import 'package:flutter/material.dart';

import '../app.dart';
import '../services/aura.dart';
import '../services/etat.dart';
import '../services/films_proposes.dart';
import '../services/ligues.dart';
import '../services/service_aura.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';
import 'aura.dart';

/// Les films proposés (R61), en tête de l'onglet Ensemble : ma liste (« Pour
/// moi », cachetés compris) et le mur que la maison et les ligues voient.
class FilmsProposesVue extends StatefulWidget {
  const FilmsProposesVue({super.key, required this.service});
  final ServiceLigues service;

  @override
  State<FilmsProposesVue> createState() => _FilmsProposesVueState();
}

class _FilmsProposesVueState extends State<FilmsProposesVue> {
  late final ServiceAura _aura = ServiceAura(widget.service);
  Future<List<Proposition>>? _donnees;
  bool _mur = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _donnees ??= _charger();
  }

  Future<List<Proposition>> _charger() async {
    final etat = PorteeEtat.lire(context);
    if (etat.mode == ModeJeu.vjod && etat.connexion.complete && _aura.maison == null) await _aura.relier(etat.connexion);
    return _aura.propositions();
  }

  Future<void> _ouvrirAura() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AuraEcran(ligues: widget.service)));
    if (mounted) setState(() => _donnees = _charger());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Proposition>>(
      future: _donnees,
      builder: (context, snap) {
        final toutes = snap.data ?? const <Proposition>[];
        final maintenant = DateTime.now();
        final pourMoi = FilmsProposes.pourMoi(toutes, _aura.pourMoi, maintenant);
        final mur = FilmsProposes.mur(toutes, _aura.deMoi, maintenant);
        final aVoir = pourMoi.where((l) => l.etat == 'à voir' || l.cachetee).length;
        final classement = Aura.classement(toutes);
        final moi = classement.where((c) => c.qui == _aura.moi || c.qui == widget.service.monId).firstOrNull;
        final lignes = (_mur ? mur : pourMoi).take(6).toList();
        return Panneau(
          couleur: AuraCouleurs.jaune,
          inclinaison: -0.008,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.auto_awesome_rounded, size: 30),
              const SizedBox(width: 8),
              Expanded(child: Text('LES FILMS PROPOSÉS', style: AuraTexte.titre(22))),
              if (snap.hasData) Text('Ton aura : ${moi?.aura ?? 0}', style: AuraTexte.corps(14, poids: FontWeight.w900)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Pastille(libelle: aVoir > 0 ? 'Pour moi ($aVoir)' : 'Pour moi', choisie: !_mur, onTap: () => setState(() => _mur = false)),
              Pastille(libelle: 'Le mur de tout le monde', choisie: _mur, onTap: () => setState(() => _mur = true)),
            ]),
            const SizedBox(height: 10),
            if (snap.connectionState != ConnectionState.done)
              Text('Je regarde ce qui circule…', style: AuraTexte.corps(14, poids: FontWeight.w700))
            else if (snap.hasError)
              Text('${snap.error}', style: AuraTexte.corps(14, poids: FontWeight.w900))
            else if (lignes.isEmpty)
              Text(
                _mur
                    ? 'Rien ne circule encore. Propose le premier film : toute la maison et ta ligue le verront ici.'
                    : 'Personne ne t\'a encore proposé de film. Propose-en un : ça donne souvent des idées aux autres.',
                style: AuraTexte.corps(14, poids: FontWeight.w700),
              )
            else
              for (final l in lignes) _Ligne(ligne: l, mur: _mur, onTap: _ouvrirAura),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: AuraBouton(libelle: 'Proposer un film', icone: Icons.send_rounded, onPressed: _ouvrirAura)),
              if ((_mur ? mur : pourMoi).length > lignes.length) ...[
                const SizedBox(width: 8),
                Expanded(child: AuraBouton(libelle: 'Tout voir', principal: false, onPressed: _ouvrirAura)),
              ],
            ]),
          ]),
        );
      },
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.ligne, required this.mur, required this.onTap});

  final LigneProposee ligne;
  final bool mur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = ligne.p;
    final qui = mur ? '${p.deNom} → ${p.pourNom}' : 'De ${p.deNom}';
    final couleurEtat = ligne.cachetee
        ? AuraCouleurs.violet
        : p.aimee
            ? AuraCouleurs.rose
            : p.vu
                ? AuraCouleurs.vert
                : AuraCouleurs.creme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Touchable(
        etiquette: '${ligne.titre}, $qui, ${ligne.etat}',
        onTap: onTap,
        builder: (context, focus, appui) => AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AuraCouleurs.creme,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(width: 2.5),
            boxShadow: [
              if (focus) const BoxShadow(color: AuraCouleurs.noir, spreadRadius: 3),
              if (!appui) const BoxShadow(color: AuraCouleurs.noir, offset: Offset(3, 3)),
            ],
          ),
          child: Row(children: [
            Icon(ligne.cachetee ? Icons.lock_rounded : p.serie ? Icons.tv_rounded : Icons.movie_rounded, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ligne.titre, maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraTexte.corps(15, poids: FontWeight.w900)),
                Text(p.mot != null ? '$qui · « ${p.mot} »' : qui, maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraTexte.corps(12, poids: FontWeight.w700)),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: couleurEtat, borderRadius: BorderRadius.circular(999), border: Border.all(width: 2)),
              child: Text(ligne.etat, style: AuraTexte.corps(11, poids: FontWeight.w900, couleur: ligne.cachetee ? AuraCouleurs.creme : AuraCouleurs.noir)),
            ),
          ]),
        ),
      ),
    );
  }
}
