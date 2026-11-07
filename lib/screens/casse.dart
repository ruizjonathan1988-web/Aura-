import 'package:flutter/material.dart';

import '../app.dart';
import '../services/casse.dart';
import '../services/etat.dart';
import '../services/ligues.dart';
import '../services/service_casse.dart';
import '../theme/aura_theme.dart';
import '../widgets/animations.dart';
import '../widgets/aura_widgets.dart';

/// Le Casse de la Cinémathèque (R56) : les quatre serrures, ton rôle secret,
/// le vote contre la Taupe, et l'ouverture du coffre le dernier soir.
class CasseEcran extends StatefulWidget {
  const CasseEcran({super.key});

  @override
  State<CasseEcran> createState() => _CasseEcranState();
}

class _Vue {
  _Vue({required this.noms, required this.roles, required this.moi, required this.ouvertures, required this.votes, this.ligue});
  final Map<String, String> noms;
  final Map<String, Role> roles;
  final String moi;

  /// Serrure → vraiment ouverte ?
  final Map<int, bool> ouvertures;
  final Map<String, String> votes;
  final Ligue? ligue;

  bool get solo => ligue == null;
  Role get monRole => roles[moi] ?? const Role(serrures: []);
  String? get taupe => roles.entries.where((e) => e.value.taupe).map((e) => e.key).firstOrNull;
  String proprietaire(int s) => roles.entries.firstWhere((e) => e.value.serrures.contains(s), orElse: () => MapEntry('', const Role(serrures: []))).key;
}

class _CasseEcranState extends State<CasseEcran> {
  Future<_Vue>? _vue;
  ({bool reussi, bool taupeDemasquee})? _issue;
  String? _message;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _vue ??= _charger();
  }

  Future<_Vue> _charger() async {
    final etat = PorteeEtat.lire(context);
    final maintenant = DateTime.now();
    final mois = Casse.mois(maintenant);
    final ligues = etat.ligues;
    if (ligues != null && ligues.inscrit && ligues.ligues.isNotEmpty) {
      try {
        final l = ligues.ligues.first;
        final service = ServiceCasse(ligues);
        final membres = await ligues.classement(l);
        final roles = Casse.roles([for (final m in membres) m.joueurId], ServiceCasse.graine(l.id, mois));
        final moi = ligues.monId!;
        final role = roles[moi];
        if (role != null) {
          for (final s in role.serrures) {
            if (etat.casseOuvertes(maintenant).contains(s)) await service.ouvrir(l.id, mois, s, vraie: !role.taupe || etat.casseVraie(maintenant));
          }
        }
        final ouv = <int, bool>{};
        for (final o in await service.ouvertures(l.id, mois)) {
          if (roles[o.joueur]?.serrures.contains(o.serrure) ?? false) ouv[o.serrure] = (ouv[o.serrure] ?? false) || o.vraie;
        }
        return _Vue(
          noms: {for (final m in membres) m.joueurId: m.joueurId == moi ? 'Toi' : m.pseudo},
          roles: roles,
          moi: moi,
          ouvertures: ouv,
          votes: await service.votes(l.id, mois),
          ligue: l,
        );
      } catch (_) {
        // Pas encore de table (migration 0009) ou hors ligne : le Casse en solo.
      }
    }
    final accuse = etat.casseAccuse(maintenant);
    return _Vue(
      noms: {'moi': 'Toi', ...Casse.nomsRobots},
      roles: etat.rolesSolo,
      moi: 'moi',
      ouvertures: etat.ouverturesSolo(maintenant),
      votes: {if (accuse != null) 'moi': accuse},
    );
  }

  Future<void> _voter(EtatJeu etat, _Vue v, String accuse) async {
    final maintenant = DateTime.now();
    if (v.solo) {
      await etat.accuserEnSolo(maintenant, accuse);
    } else {
      try {
        await ServiceCasse(etat.ligues!).voter(v.ligue!.id, Casse.mois(maintenant), accuse);
      } catch (_) {
        setState(() => _message = 'Le vote n\'est pas parti. Réessaie plus tard.');
        return;
      }
    }
    setState(() => _vue = _charger());
  }

  Future<void> _ouvrirLeCoffre(EtatJeu etat, _Vue v) async {
    final maintenant = DateTime.now();
    final issue = Casse.issue(ouvertures: v.ouvertures, taupe: v.taupe, votes: v.votes, equipe: v.solo ? 1 : v.roles.length);
    await etat.terminerCasse(maintenant, reussi: issue.reussi, taupeDemasquee: issue.taupeDemasquee, jeSuisLaTaupe: v.monRole.taupe);
    if (!mounted) return;
    setState(() => _issue = issue);
    if (issue.reussi && !v.monRole.taupe) await celebrer(context);
  }

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    final maintenant = DateTime.now();
    return Scaffold(
      body: FondTrame(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  EnTeteRetour(
                    titre: 'Le Casse',
                    regle: 'La dernière semaine de chaque mois, on braque le coffre de Pop. Chacun reçoit ses serrures, le Perceur la plus dure. Un film qui remplit le défi d\'une serrure l\'ouvre.\n'
                        'Dès trois joueurs, l\'un de vous est la Taupe : il peut ouvrir pour de faux. Votez pour la démasquer.\n'
                        'Coffre vidé : ${Casse.audaceReussite} d\'audace, Pop recule de ${Casse.recul} cases, et l\'exploit « Le casse du siècle ».\n'
                        'En solo, Bobine et Pellicule font l\'équipe… et l\'un des deux te trahit.',
                  ),
                  const SizedBox(height: 14),
                  if (!Casse.enCours(maintenant))
                    _Apercu(maintenant: maintenant)
                  else
                    FutureBuilder<_Vue>(
                      future: _vue,
                      builder: (context, snap) => snap.data == null ? const PopQuiParle(texte: 'Je compte mes clés…') : _contenu(etat, snap.data!, maintenant),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contenu(EtatJeu etat, _Vue v, DateTime maintenant) {
    final serrures = Casse.serrures(maintenant);
    final deja = etat.casseRevele(maintenant) ?? _issue;
    final role = v.monRole;
    final autres = v.roles.keys.where((id) => id != v.moi).toList();
    final blocs = <Widget>[
      PopQuiParle(
        texte: deja != null
            ? (deja.reussi ? 'Vous avez vidé mon coffre. Je n\'en reviens pas. Je ne m\'en remettrai pas.' : 'Le coffre a tenu ! Mon trophée reste à moi. Merci à qui vous savez…')
            : 'Mon trophée est dans le coffre. Quatre serrures, un film chacune. Et l\'un de vous travaille peut-être pour moi.',
      ),
      Panneau(
        couleur: role.taupe ? AuraCouleurs.rouge : AuraCouleurs.jaune,
        inclinaison: -0.01,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(role.taupe ? 'TON RÔLE SECRET : LA TAUPE' : (role.perceur ? 'TON RÔLE : LE PERCEUR' : 'TON RÔLE : ÉQUIPIER'), style: AuraTexte.titre(18)),
          const SizedBox(height: 4),
          Text(
            role.taupe
                ? 'Tu travailles pour Pop. Ta serrure s\'affichera ouverte, mais tu peux l\'ouvrir pour de faux. Si le casse rate, tu gagnes ${Casse.audaceTaupe} d\'audace. Ne te fais pas démasquer.'
                : role.perceur
                    ? 'Tu as la serrure la plus dure. Regarde le bon film avant la fin du mois.'
                    : 'Ouvre ta serrure avec le bon film, et ouvre l\'œil : la Taupe est peut-être parmi vous.',
            style: AuraTexte.corps(14, poids: FontWeight.w900),
          ),
          if (role.taupe) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Pastille(libelle: 'Ouvrir pour de faux', choisie: !etat.casseVraie(maintenant), onTap: () => etat.changerCasseVraie(maintenant, false)),
              Pastille(libelle: 'Ouvrir pour de vrai', choisie: etat.casseVraie(maintenant), onTap: () => etat.changerCasseVraie(maintenant, true)),
            ]),
          ],
        ]),
      ),
      Text('LES QUATRE SERRURES', style: AuraTexte.titre(18)),
      for (final (i, s) in serrures.indexed)
        Panneau(
          couleur: v.ouvertures.containsKey(i) ? AuraCouleurs.vert : AuraCouleurs.creme,
          child: Row(children: [
            Icon(v.ouvertures.containsKey(i) ? Icons.lock_open_rounded : Icons.lock_rounded, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i == 0 ? 'SERRURE DU PERCEUR · ' : ''}${v.noms[v.proprietaire(i)] ?? '?'}', style: AuraTexte.corps(12, poids: FontWeight.w900)),
                Text(s.texte, style: AuraTexte.corps(16, poids: FontWeight.w900)),
                if (deja != null && v.ouvertures[i] == false) Text(deja.taupeDemasquee ? 'Ouverte pour de faux… mais la Taupe est démasquée !' : 'Ouverte pour de faux !', style: AuraTexte.corps(13, poids: FontWeight.w900, couleur: AuraCouleurs.rouge)),
              ]),
            ),
          ]),
        ),
      if (deja == null && autres.isNotEmpty && v.roles.length >= 3) ...[
        Text('QUI EST LA TAUPE ?', style: AuraTexte.titre(18)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final id in autres) Pastille(libelle: v.noms[id] ?? '?', choisie: v.votes[v.moi] == id, onTap: () => _voter(etat, v, id)),
        ]),
        Text(v.solo ? 'Un seul vote : le tien. Si tu vises juste, la fausse serrure compte quand même.' : 'Si la majorité de l\'équipe désigne la Taupe, ses fausses serrures comptent quand même.',
            style: AuraTexte.corps(13, couleur: AuraCouleurs.creme)),
      ],
      if (deja != null)
        Panneau(
          couleur: deja.reussi ? AuraCouleurs.vert : AuraCouleurs.rouge,
          child: Text(
            deja.reussi
                ? 'CASSE RÉUSSI ! ${role.taupe ? 'Ton camp a perdu.' : '+${Casse.audaceReussite} d\'audace, Pop recule de ${Casse.recul} cases, et l\'exploit « Le casse du siècle ».'}'
                : 'LE COFFRE A TENU. ${role.taupe ? 'Bien joué, Taupe : +${Casse.audaceTaupe} d\'audace.' : 'Pop garde son trophée… jusqu\'au mois prochain.'}${v.taupe != null ? ' La Taupe était ${v.noms[v.taupe]}.' : ''}',
            style: AuraTexte.corps(16, poids: FontWeight.w900),
          ),
        )
      else if (Casse.revelation(maintenant))
        AuraBouton(libelle: 'Ouvrir le coffre !', icone: Icons.lock_open_rounded, autofocus: true, onPressed: () => _ouvrirLeCoffre(etat, v))
      else
        Text('Le coffre s\'ouvre le ${Casse.dernierJour(maintenant)} à 18 h. Jusque-là, chaque film compte.', style: AuraTexte.corps(14, poids: FontWeight.w900, couleur: AuraCouleurs.creme)),
      if (_message != null) Panneau(couleur: AuraCouleurs.jaune, child: Text(_message!, style: AuraTexte.corps(14, poids: FontWeight.w900))),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, b) in blocs.indexed) ...[if (i > 0) const SizedBox(height: 12), b],
    ]);
  }
}


/// Hors de la dernière semaine : de quoi préparer le coup. Le compte à
/// rebours, les règles, et les quatre serrures du mois, déjà connues.
class _Apercu extends StatelessWidget {
  const _Apercu({required this.maintenant});
  final DateTime maintenant;

  @override
  Widget build(BuildContext context) {
    final debut = Casse.dernierJour(maintenant) - Casse.jours + 1;
    final jours = debut - maintenant.day;
    final serrures = Casse.serrures(maintenant);
    final blocs = <Widget>[
      PopQuiParle(texte: 'Mon coffre est fermé à double tour. Vous croyez que je ne vous vois pas préparer vos plans ? Rendez-vous le $debut.'),
      Panneau(
        couleur: AuraCouleurs.jaune,
        inclinaison: -0.012,
        child: Row(children: [
          Text('J-$jours', style: AuraTexte.titre(54)),
          const SizedBox(width: 14),
          Expanded(child: Text('Le casse commence le $debut et le coffre s\'ouvre le ${Casse.dernierJour(maintenant)} à 18 h.', style: AuraTexte.corps(15, poids: FontWeight.w900))),
        ]),
      ),
      Text('LES QUATRE SERRURES DE CE MOIS', style: AuraTexte.titre(18, couleur: AuraCouleurs.creme)),
      for (final (i, s) in serrures.indexed)
        Panneau(
          child: Row(children: [
            const Icon(Icons.lock_rounded, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (i == 0) Text('LA SERRURE DU PERCEUR', style: AuraTexte.corps(12, poids: FontWeight.w900)),
                Text(s.texte, style: AuraTexte.corps(16, poids: FontWeight.w900)),
              ]),
            ),
          ]),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, b) in blocs.indexed) ...[if (i > 0) const SizedBox(height: 12), b],
    ]);
  }
}
