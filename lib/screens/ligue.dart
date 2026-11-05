import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/etat.dart';
import '../services/ligues.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';

/// La ligue entre amis : inscription par pseudo, création ou rejointe par
/// code, classement du mois. Sans serveur, le duel solo contre Pop.
class LigueEcran extends StatefulWidget {
  const LigueEcran({super.key});

  @override
  State<LigueEcran> createState() => _LigueEcranState();
}

class _LigueEcranState extends State<LigueEcran> {
  String? _ligueId;
  bool _ajout = false;

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    final service = etat.ligues;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: service == null
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _DuelPop(etat: etat),
                  const SizedBox(height: 16),
                  const _Info(
                    titre: 'Les ligues entre amis',
                    texte: 'Les ligues ne sont pas disponibles dans cette version. En attendant, affronte Pop en solo.',
                  ),
                ])
              : ListenableBuilder(listenable: service, builder: (context, _) => _avecServeur(etat, service)),
        ),
      ),
    );
  }

  Widget _avecServeur(EtatJeu etat, ServiceLigues service) {
    if (!service.charge) return const PopQuiParle(texte: 'Je compte les points…');
    if (!service.inscrit) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (estTele(context))
          const _Info(titre: 'Joue avec tes amis', texte: 'Crée ton joueur et ta ligue depuis ton téléphone : sur la télé, on ne tape rien.')
        else
          _Inscription(service: service, profil: etat.profil, apres: etat.synchroniser),
        const SizedBox(height: 16),
        _DuelPop(etat: etat),
      ]);
    }
    if (service.ligues.isEmpty || _ajout) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (estTele(context))
          const _Info(titre: 'Pas encore de ligue', texte: 'Crée une ligue ou rejoins celle d\'un ami depuis ton téléphone, avec son code à 6 caractères.')
        else
          _CreerOuRejoindre(
            service: service,
            annulable: service.ligues.isNotEmpty,
            fini: (id) => setState(() {
              _ajout = false;
              if (id != null) _ligueId = id;
            }),
          ),
        const SizedBox(height: 16),
        _DuelPop(etat: etat),
      ]);
    }
    final ligue = service.ligues.firstWhere((l) => l.id == _ligueId, orElse: () => service.ligues.first);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TitreCartoon(ligue.nom, taille: 40),
      if (service.ligues.length > 1) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final l in service.ligues) Pastille(libelle: l.nom, choisie: l.id == ligue.id, onTap: () => setState(() => _ligueId = l.id)),
        ]),
      ],
      const SizedBox(height: 16),
      _Classement(key: ValueKey(ligue.id), service: service, ligue: ligue, positionLocale: etat.position),
      const SizedBox(height: 16),
      Panneau(
        couleur: AuraCouleurs.jaune,
        inclinaison: -0.015,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CODE D\'INVITATION', style: AuraTexte.titre(16)),
              Text(ligue.code, style: AuraTexte.titre(34).copyWith(letterSpacing: 4)),
              Text('Donne-le à tes amis pour qu\'ils rejoignent la ligue.', style: AuraTexte.corps(13)),
            ]),
          ),
          if (!estTele(context))
            Touchable(
              etiquette: 'Copier le code',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: ligue.code));
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copié !')));
              },
              builder: (context, focus, appui) => Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AuraCouleurs.creme,
                  shape: BoxShape.circle,
                  border: Border.all(width: 3),
                  boxShadow: [
                    if (focus) const BoxShadow(color: AuraCouleurs.jaune, spreadRadius: 4),
                    if (!appui) const BoxShadow(color: AuraCouleurs.noir, offset: Offset(3, 3)),
                  ],
                ),
                child: const Icon(Icons.copy_rounded, color: AuraCouleurs.noir),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 18),
      if (!estTele(context)) ...[
        AuraBouton(libelle: 'Créer ou rejoindre une autre ligue', principal: false, onPressed: () => setState(() => _ajout = true)),
        const SizedBox(height: 12),
      ],
      AuraBouton(
        libelle: 'Quitter cette ligue',
        principal: false,
        onPressed: () => _quitter(service, ligue),
      ),
      const SizedBox(height: 22),
      _DuelPop(etat: etat, titre: 'En solo contre Pop'),
    ]);
  }

  Future<void> _quitter(ServiceLigues service, Ligue ligue) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AuraCouleurs.creme,
        title: Text('Quitter « ${ligue.nom} » ?', style: AuraTexte.titre(22)),
        content: Text('Tes séances restent à toi. Tu pourras revenir avec le code ${ligue.code}.', style: AuraTexte.corps(15)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Rester', style: AuraTexte.corps(15, poids: FontWeight.w900))),
          TextButton(autofocus: true, onPressed: () => Navigator.pop(context, true), child: Text('Quitter', style: AuraTexte.corps(15, poids: FontWeight.w900))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await service.quitter(ligue);
    } on ErreurLigue catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.titre, required this.texte});
  final String titre;
  final String texte;

  @override
  Widget build(BuildContext context) => Panneau(
        couleur: AuraCouleurs.violet,
        inclinaison: 0.015,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre.toUpperCase(), style: AuraTexte.titre(18)),
          const SizedBox(height: 6),
          Text(texte, style: AuraTexte.corps(14)),
        ]),
      );
}

/// Le duel solo : toi contre Pop, qui avance d'une case par jour.
class _DuelPop extends StatelessWidget {
  const _DuelPop({required this.etat, this.titre = 'Classement'});
  final EtatJeu etat;
  final String titre;

  @override
  Widget build(BuildContext context) {
    final pop = etat.positionDePop;
    final lignes = [
      ('Toi', etat.position, Figurine.profil(etat.profil, hauteur: 52)),
      ('Pop, le Programmateur', pop, const Figurine.pop(hauteur: 52)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TitreCartoon(titre, taille: titre == 'Classement' ? 40 : 26, inclinaison: titre == 'Classement' ? -0.035 : 0),
      const SizedBox(height: 14),
      for (final (i, l) in lignes.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _Rangee(rang: i + 1, nom: l.$1, detail: null, position: l.$2, figurine: l.$3, moi: l.$1 == 'Toi'),
        ),
    ]);
  }
}

class _Rangee extends StatelessWidget {
  const _Rangee({required this.rang, required this.nom, required this.detail, required this.position, required this.figurine, required this.moi});

  final int rang;
  final String nom;
  final String? detail;
  final int position;
  final Widget figurine;
  final bool moi;

  @override
  Widget build(BuildContext context) => Panneau(
        couleur: moi ? AuraCouleurs.jaune : AuraCouleurs.creme,
        inclinaison: moi ? -0.02 : 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          SizedBox(width: 26, child: Text('$rang', style: AuraTexte.titre(26))),
          const SizedBox(width: 8),
          figurine,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nom, style: AuraTexte.corps(16, poids: FontWeight.w900)),
              if (detail != null) Text(detail!, style: AuraTexte.corps(12, couleur: AuraCouleurs.texteDoux)),
            ]),
          ),
          Text('case $position', style: AuraTexte.titre(20)),
        ]),
      );
}

class _Classement extends StatefulWidget {
  const _Classement({super.key, required this.service, required this.ligue, required this.positionLocale});
  final ServiceLigues service;
  final Ligue ligue;
  final int positionLocale;

  @override
  State<_Classement> createState() => _ClassementState();
}

class _ClassementState extends State<_Classement> {
  late Future<List<Classe>> _liste = widget.service.classement(widget.ligue);

  @override
  void didUpdateWidget(covariant _Classement old) {
    super.didUpdateWidget(old);
    // Une séance vient d'être validée : on recharge.
    if (old.positionLocale != widget.positionLocale) _liste = widget.service.classement(widget.ligue);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Classe>>(
      future: _liste,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const PopQuiParle(texte: 'Je compte les points…');
        if (snap.hasError) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Panneau(couleur: AuraCouleurs.jaune, child: Text('${snap.error}', style: AuraTexte.corps(14, poids: FontWeight.w900))),
            const SizedBox(height: 12),
            AuraBouton(libelle: 'Réessayer', principal: false, onPressed: () => setState(() => _liste = widget.service.classement(widget.ligue))),
          ]);
        }
        final liste = snap.data ?? const [];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, c) in liste.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Rangee(
                rang: i + 1,
                nom: c.joueurId == widget.service.monId ? '${c.pseudo} (toi)' : c.pseudo,
                detail: '${c.profil.nom}, ${c.seances} séance${c.seances > 1 ? 's' : ''} ce mois-ci',
                position: c.position,
                figurine: Figurine.profil(c.profil, hauteur: 52),
                moi: c.joueurId == widget.service.monId,
              ),
            ),
        ]);
      },
    );
  }
}

/// Créer son joueur : un pseudo, et le profil déjà choisi.
class _Inscription extends StatefulWidget {
  const _Inscription({required this.service, required this.profil, required this.apres});
  final ServiceLigues service;
  final Profil profil;
  final Future<void> Function() apres;

  @override
  State<_Inscription> createState() => _InscriptionState();
}

class _InscriptionState extends State<_Inscription> {
  final _pseudo = TextEditingController();
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _pseudo.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await widget.service.inscrire(_pseudo.text, widget.profil);
      await widget.apres();
    } on ErreurLigue catch (e) {
      _erreur = e.message;
    }
    if (mounted) setState(() => _envoi = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const TitreCartoon('Joue avec tes amis', taille: 38),
      const SizedBox(height: 14),
      Panneau(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('TON PSEUDO', style: AuraTexte.titre(16)),
          const SizedBox(height: 8),
          ChampAura(controleur: _pseudo, indication: 'Jon', longueurMax: 24, onValider: (_) => _valider()),
          const SizedBox(height: 8),
          Text('Ni e-mail ni mot de passe : ton joueur est enregistré sur cet appareil. Ton profil : ${widget.profil.nom}.',
              style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
          if (_erreur != null) ...[
            const SizedBox(height: 8),
            Text(_erreur!, style: AuraTexte.corps(14, poids: FontWeight.w900)),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      AuraBouton(libelle: _envoi ? 'Création…' : 'Créer mon joueur', onPressed: _envoi ? null : _valider),
    ]);
  }
}

/// Créer une ligue, ou rejoindre celle d'un ami avec son code.
class _CreerOuRejoindre extends StatefulWidget {
  const _CreerOuRejoindre({required this.service, required this.annulable, required this.fini});
  final ServiceLigues service;
  final bool annulable;
  final ValueChanged<String?> fini;

  @override
  State<_CreerOuRejoindre> createState() => _CreerOuRejoindreState();
}

class _CreerOuRejoindreState extends State<_CreerOuRejoindre> {
  final _nom = TextEditingController();
  final _code = TextEditingController();
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _nom.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _faire(Future<String?> Function() action) async {
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      final id = await action();
      widget.fini(id);
    } on ErreurLigue catch (e) {
      _erreur = e.message;
    }
    if (mounted) setState(() => _envoi = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TitreCartoon('Salut ${widget.service.pseudo} !', taille: 38),
      const SizedBox(height: 14),
      Panneau(
        inclinaison: -0.01,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('REJOINDRE UNE LIGUE', style: AuraTexte.titre(16)),
          const SizedBox(height: 8),
          ChampAura(controleur: _code, indication: 'Code à 6 caractères', longueurMax: 6, majuscules: true),
          const SizedBox(height: 10),
          AuraBouton(
            libelle: 'Rejoindre',
            onPressed: _envoi
                ? null
                : () => _faire(() async {
                      await widget.service.rejoindre(_code.text);
                      return null;
                    }),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Panneau(
        inclinaison: 0.01,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('OU CRÉER LA TIENNE', style: AuraTexte.titre(16)),
          const SizedBox(height: 8),
          ChampAura(controleur: _nom, indication: 'La ligue des Mardis', longueurMax: 40),
          const SizedBox(height: 10),
          AuraBouton(
            libelle: 'Créer la ligue',
            principal: false,
            onPressed: _envoi ? null : () => _faire(() async => (await widget.service.creer(_nom.text)).id),
          ),
        ]),
      ),
      if (_erreur != null) ...[
        const SizedBox(height: 14),
        Panneau(couleur: AuraCouleurs.jaune, child: Text(_erreur!, style: AuraTexte.corps(14, poids: FontWeight.w900))),
      ],
      if (widget.annulable) ...[
        const SizedBox(height: 16),
        AuraBouton(libelle: 'Retour à mes ligues', principal: false, onPressed: () => widget.fini(null)),
      ],
    ]);
  }
}
