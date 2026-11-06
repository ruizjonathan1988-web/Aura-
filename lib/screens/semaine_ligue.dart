import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../services/affiche.dart';
import '../services/etat.dart';
import '../services/ligues.dart';
import '../services/premier_soir.dart';
import '../services/semaine_ligue.dart';
import '../services/tirage.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';

/// L'Affiche de la semaine jouée en ligue : le Programmateur choisit le film,
/// chacun écrit un faux synopsis et cherche le vrai, place son Curseur et
/// écrit son Verdict ; un Faussaire, qui n'a pas vu le film, invente le sien.
/// Le dimanche, on démasque le Faussaire et la Révélation compte les points.
class SemaineDeLigueVue extends StatefulWidget {
  const SemaineDeLigueVue({super.key, required this.service, required this.ligue});
  final ServiceLigues service;
  final Ligue ligue;

  @override
  State<SemaineDeLigueVue> createState() => _SemaineDeLigueVueState();
}

class _SemaineDeLigueVueState extends State<SemaineDeLigueVue> {
  late final String _lundi = EtatJeu.jourDe(Affiche.lundiDe(DateTime.now()));
  late Future<(List<Classe>, SemaineDeLigue)> _donnees = _charger();
  final _bluff = TextEditingController();
  final _verdict = TextEditingController();
  double _curseur = 5;
  bool _envoi = false;
  String? _erreur;

  Future<(List<Classe>, SemaineDeLigue)> _charger() => widget.service.semaine(widget.ligue, _lundi);

  @override
  void dispose() {
    _bluff.dispose();
    _verdict.dispose();
    super.dispose();
  }

  Future<void> _jouer(String type, Map<String, dynamic> valeur) async {
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await widget.service.jouer(widget.ligue, _lundi, type, valeur);
      _donnees = _charger();
    } on ErreurLigue catch (e) {
      _erreur = e.message;
    }
    if (mounted) setState(() => _envoi = false);
  }

  /// Trois films proposés au Programmateur (les mieux notés, avec un résumé).
  Future<List<FilmDeLigue>> _propositions(SemaineDeLigue s, {bool parPop = false}) async {
    final films = await PorteeEtat.lire(context).source.catalogue(auHasard: false);
    final avecResume = films.where((f) => Tirage.assezBon(f) && !f.dejaVu && BluffDePop.premierePhrase(f.synopsis).length >= 30).toList();
    final haut = Tirage.hautDuPanier(avecResume)..shuffle(math.Random(s.numero));
    return haut
        .take(3)
        .map((f) => FilmDeLigue(titre: f.titre, filmId: f.id, synopsis: BluffDePop.premierePhrase(f.synopsis), infos: f.infos, parPop: parPop))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<Classe>, SemaineDeLigue)>(
      future: _donnees,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const PopQuiParle(texte: 'Je rassemble la ligue…');
        if (snap.hasError || snap.data == null) {
          return Panneau(
            couleur: AuraCouleurs.jaune,
            child: Text('La semaine de la ligue ne répond pas. ${snap.error ?? ''}', style: AuraTexte.corps(14, poids: FontWeight.w900)),
          );
        }
        final (membres, s) = snap.data!;
        return _contenu(membres, s);
      },
    );
  }

  Widget _contenu(List<Classe> membres, SemaineDeLigue s) {
    final moi = widget.service.monId!;
    final tele = estTele(context);
    final dimanche = Affiche.jourDeRevelation(DateTime.now());
    String nom(String? id) => id == moi ? 'toi' : membres.where((c) => c.joueurId == id).firstOrNull?.pseudo ?? 'un ami';
    final n = membres.length;
    final affiche = s.affiche;
    final blocs = <Widget>[];

    if (n < 2) {
      blocs.add(const PopQuiParle(texte: 'L\'Affiche en ligue se joue à partir de deux. Invite un ami avec ton code !'));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocs);
    }

    // 1. L'Affiche.
    if (affiche == null) {
      final jeProgramme = s.programmateur == moi;
      blocs.add(PopQuiParle(
        texte: jeProgramme
            ? 'Cette semaine, c\'est toi le Programmateur ! Choisis l\'Affiche de la ligue.'
            : 'Cette semaine, ${nom(s.programmateur)} est Programmateur. On attend son choix…',
      ));
      if (jeProgramme || DateTime.now().weekday >= DateTime.wednesday) {
        blocs.add(FutureBuilder<List<FilmDeLigue>>(
          future: _propositions(s, parPop: !jeProgramme),
          builder: (context, p) {
            final films = p.data ?? const <FilmDeLigue>[];
            if (films.isEmpty) return const SizedBox.shrink();
            if (!jeProgramme) {
              return AuraBouton(
                libelle: 'Laisser Pop choisir',
                principal: false,
                onPressed: _envoi ? null : () => _jouer('affiche', films.first.versJson()),
              );
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, f) in films.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ChoixLarge(
                    libelle: '${f.titre}\n${f.infos}',
                    autofocus: i == 0,
                    onTap: _envoi ? null : () => _jouer('affiche', f.versJson()),
                  ),
                ),
            ]);
          },
        ));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _espaces(blocs));
    }

    blocs.add(Panneau(
      inclinaison: -0.015,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('L\'AFFICHE DE LA LIGUE', style: AuraTexte.titre(16)),
        Text(affiche.titre.toUpperCase(), style: AuraTexte.titre(32)),
        Text(
          '${affiche.infos.isEmpty ? '' : '${affiche.infos}. '}${affiche.parPop ? 'Choisi par Pop.' : 'Choisi par ${nom(s.programmateur)}, Programmateur de la semaine.'}',
          style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux),
        ),
      ]),
    ));

    // Où en est la ligue.
    blocs.add(Wrap(spacing: 8, runSpacing: 8, children: [
      for (final (libelle, type) in [('Bluffs', 'bluff'), ('Votes', 'vote_bluff'), ('Curseurs', 'curseur'), ('Verdicts', 'verdict')])
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: AuraCouleurs.creme, borderRadius: BorderRadius.circular(10), border: Border.all(width: 2.5)),
          child: Text('$libelle ${s.combien(type)}/$n', style: AuraTexte.corps(13, poids: FontWeight.w900)),
        ),
    ]));

    // 2. Le rôle secret : seulement sur le téléphone (la télé est partagée).
    final faussaire = s.faussaire;
    if (faussaire != null) {
      blocs.add(tele
          ? Panneau(couleur: AuraCouleurs.violet, child: Text('Les rôles secrets sont sur vos téléphones.', style: AuraTexte.corps(14, poids: FontWeight.w900)))
          : Panneau(
              couleur: AuraCouleurs.violet,
              inclinaison: 0.012,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TON RÔLE SECRET', style: AuraTexte.titre(16)),
                Text(faussaire == moi ? 'FAUSSAIRE' : 'TÉMOIN', style: AuraTexte.titre(30)),
                Text(
                  faussaire == moi
                      ? 'Ne regarde pas le film ! Écris quand même un Verdict crédible. Dimanche, si personne ne te démasque, tu marques.'
                      : 'Un Faussaire n\'a pas vu le film et va inventer son Verdict. Dimanche, démasque-le.',
                  style: AuraTexte.corps(14),
                ),
              ]),
            ));
    }

    // 3. Le Bluff : écrire un faux synopsis, puis trouver le vrai.
    if (s.bluffDe(moi) == null && s.voteBluffDe(moi) == null && !dimanche) {
      blocs.add(Panneau(
        couleur: AuraCouleurs.rose,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('LE BLUFF : ÉCRIS UN FAUX SYNOPSIS', style: AuraTexte.titre(16)),
          const SizedBox(height: 6),
          Text('Invente un résumé crédible de « ${affiche.titre} ». Chaque ami qui le croit vrai te rapporte un point.', style: AuraTexte.corps(13)),
          const SizedBox(height: 8),
          ChampAura(controleur: _bluff, indication: 'Un détective amnésique…', longueurMax: 200),
          if (!tele) ...[
            const SizedBox(height: 8),
            AuraBouton(
              libelle: 'Envoyer mon Bluff',
              onPressed: _envoi ? null : () => _bluff.text.trim().length < 15 ? setState(() => _erreur = 'Un peu plus long, ton Bluff !') : _jouer('bluff', {'texte': _bluff.text.trim()}),
            ),
          ],
        ]),
      ));
    }
    final aDepartager = s.synopsisPour(moi);
    if (s.voteBluffDe(moi) == null && aDepartager.length >= 2) {
      blocs.add(Panneau(
        couleur: AuraCouleurs.rose,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('LE BLUFF : LEQUEL EST LE VRAI ?', style: AuraTexte.titre(16)),
          const SizedBox(height: 8),
          for (final (i, (auteur, texte)) in aDepartager.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChoixLarge(libelle: texte, autofocus: i == 0, onTap: _envoi ? null : () => _jouer('vote_bluff', {'choix': auteur})),
            ),
        ]),
      ));
    } else if (s.voteBluffDe(moi) == null && s.bluffDe(moi) != null) {
      blocs.add(const PopQuiParle(texte: 'Ton Bluff est envoyé. Dès que tes amis auront écrit les leurs, tu pourras chercher le vrai.', taille: 60));
    }

    // 4. Après la séance : le Curseur et le Verdict.
    if (s.curseurDe(moi) == null) {
      blocs.add(Panneau(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('APRÈS LA SÉANCE : TON CURSEUR (À QUEL POINT T\'A-T-IL PLU ?)', style: AuraTexte.titre(15)),
          Row(children: [
            Expanded(
              child: Slider(
                value: _curseur,
                min: 0,
                max: 10,
                divisions: 10,
                activeColor: AuraCouleurs.rouge,
                onChanged: (v) => setState(() => _curseur = v),
              ),
            ),
            SizedBox(width: 40, child: Text('${_curseur.round()}', style: AuraTexte.titre(26))),
          ]),
          AuraBouton(libelle: 'Placer mon Curseur', principal: false, onPressed: _envoi ? null : () => _jouer('curseur', {'valeur': _curseur.round()})),
        ]),
      ));
    }
    if (s.verdictDe(moi) == null) {
      blocs.add(Panneau(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('TON VERDICT EN UNE PHRASE', style: AuraTexte.titre(15)),
          const SizedBox(height: 8),
          ChampAura(controleur: _verdict, indication: 'Froid, précis, inoubliable', longueurMax: 120),
          if (!tele) ...[
            const SizedBox(height: 8),
            AuraBouton(
              libelle: 'Envoyer mon Verdict',
              principal: false,
              onPressed: _envoi ? null : () => _verdict.text.trim().isEmpty ? null : _jouer('verdict', {'texte': _verdict.text.trim()}),
            ),
          ],
        ]),
      ));
    }

    // 5. Le dimanche : démasquer le Faussaire, puis la Révélation.
    if (dimanche) {
      final verdicts = [for (final c in membres) if (s.verdictDe(c.joueurId) != null) (c, s.verdictDe(c.joueurId)!)];
      if (verdicts.isNotEmpty) {
        blocs.add(Panneau(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('LES VERDICTS DE LA SEMAINE', style: AuraTexte.titre(16)),
            const SizedBox(height: 6),
            for (final (c, v) in verdicts) Text('${c.joueurId == moi ? 'Toi' : c.pseudo} : « $v »', style: AuraTexte.corps(tele ? 18 : 14)),
          ]),
        ));
      }
      if (faussaire != null && s.voteFaussaireDe(moi) == null && faussaire != moi) {
        blocs.add(Panneau(
          couleur: AuraCouleurs.violet,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('QUI EST LE FAUSSAIRE ?', style: AuraTexte.titre(16)),
            const SizedBox(height: 8),
            for (final (i, c) in membres.where((c) => c.joueurId != moi).indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ChoixLarge(libelle: c.pseudo, autofocus: i == 0, onTap: _envoi ? null : () => _jouer('vote_faussaire', {'choix': c.joueurId})),
              ),
          ]),
        ));
      }
      final pts = s.points;
      final classement = [...membres]..sort((a, b) => (pts[b.joueurId] ?? 0).compareTo(pts[a.joueurId] ?? 0));
      final m = s.moyenneCurseur;
      blocs.add(Panneau(
        couleur: AuraCouleurs.jaune,
        inclinaison: -0.012,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('LA RÉVÉLATION DE LA LIGUE', style: AuraTexte.titre(tele ? 26 : 18)),
          const SizedBox(height: 6),
          if (m != null) Text('Curseur moyen : ${m.toStringAsFixed(1).replaceAll('.', ',')} sur 10.', style: AuraTexte.corps(tele ? 20 : 15, poids: FontWeight.w900)),
          if (faussaire != null) Text('Le Faussaire était… ${nom(faussaire)} !', style: AuraTexte.corps(tele ? 20 : 15, poids: FontWeight.w900)),
          const SizedBox(height: 8),
          for (final (i, c) in classement.indexed)
            Row(children: [
              SizedBox(width: 28, child: Text('${i + 1}', style: AuraTexte.titre(20))),
              Figurine.profil(c.profil, hauteur: tele ? 48 : 36),
              const SizedBox(width: 8),
              Expanded(child: Text(c.joueurId == moi ? '${c.pseudo} (toi)' : c.pseudo, style: AuraTexte.corps(tele ? 18 : 14, poids: FontWeight.w900))),
              Text('${pts[c.joueurId] ?? 0} pt${(pts[c.joueurId] ?? 0) > 1 ? 's' : ''}', style: AuraTexte.titre(tele ? 24 : 18)),
            ]),
        ]),
      ));
    }

    if (_erreur != null) {
      blocs.add(Panneau(couleur: AuraCouleurs.jaune, child: Text(_erreur!, style: AuraTexte.corps(14, poids: FontWeight.w900))));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _espaces(blocs));
  }

  List<Widget> _espaces(List<Widget> blocs) => [
        for (final (i, b) in blocs.indexed) ...[if (i > 0) const SizedBox(height: 14), b],
      ];
}
