import 'package:flutter/material.dart';

import '../app.dart';
import '../services/etat.dart';
import '../services/ligues.dart';
import '../services/relais.dart';
import '../theme/aura_theme.dart';
import '../widgets/animations.dart';
import '../widgets/aura_widgets.dart';

/// Le Relais (R57) : la chaîne de films de la ligue, à qui c'est le tour,
/// et le film à poser pour passer le relais.
class RelaisEcran extends StatefulWidget {
  const RelaisEcran({super.key, required this.ligues, required this.ligue});
  final ServiceLigues ligues;
  final Ligue ligue;

  @override
  State<RelaisEcran> createState() => _RelaisEcranState();
}

class _RelaisEcranState extends State<RelaisEcran> {
  late final ServiceRelais _service = ServiceRelais(widget.ligues);
  late Future<(List<Classe>, List<Chaine>)> _donnees = _charger();
  bool _envoi = false;
  String? _message;

  Future<(List<Classe>, List<Chaine>)> _charger() async {
    final membres = await widget.ligues.classement(widget.ligue);
    final chaines = await _service.chaines(widget.ligue.id);
    final enCours = chaines.where((c) => !c.cassee).firstOrNull;
    if (enCours != null && enCours.expiree(DateTime.now())) await _service.casser(enCours);
    return (membres, chaines);
  }

  Future<void> _poser(EtatJeu etat, List<Classe> membres, Chaine? chaine, Billet b) async {
    setState(() {
      _envoi = true;
      _message = null;
    });
    try {
      final moi = widget.ligues.monId!;
      final personnes = await _service.personnes(b.titre, b.annee);
      if (personnes.isEmpty) {
        _message = 'Je ne trouve pas l\'équipe de « ${b.titre} ». Essaie un autre film.';
      } else {
        final ids = [for (final m in membres) m.joueurId];
        final suivant = Relais.suivant(ids, moi);
        if (chaine == null) {
          await _service.lancer(widget.ligue.id, Maillon(joueur: moi, pseudo: widget.ligues.pseudo ?? '?', titre: b.titre, annee: b.annee, personnes: personnes, quand: DateTime.now()), suivant);
          _message = 'Relais lancé ! ${membres.firstWhere((m) => m.joueurId == suivant, orElse: () => membres.first).pseudo} a 48 heures.';
        } else {
          final dernier = chaine.maillons.last;
          final lien = Relais.lien(dernier.personnes, personnes, interdit: dernier.lien?.nom);
          if (lien == null) {
            _message = dernier.lien != null && personnes.any((p) => p.endsWith(':${dernier.lien!.nom}'))
                ? 'Pop coupe : on ne passe pas deux fois de suite par ${dernier.lien!.nom}.'
                : 'Aucun lien avec « ${dernier.titre} » : ni acteur, ni réalisateur, ni compositeur en commun.';
          } else {
            await _service.passer(chaine, Maillon(joueur: moi, pseudo: widget.ligues.pseudo ?? '?', titre: b.titre, annee: b.annee, personnes: personnes, lien: lien, quand: DateTime.now()), suivant);
            await etat.gagnerAudaceRelais(chaine.id, chaine.maillons.length);
            _message = 'Relais passé : ${lien.phrase} (+${lien.points}). À ${membres.firstWhere((m) => m.joueurId == suivant, orElse: () => membres.first).pseudo} !';
            if (mounted) await celebrer(context);
          }
        }
        _donnees = _charger();
      }
    } on Exception {
      _message = 'Le relais n\'est pas passé. La migration 0009 est-elle lancée dans Supabase ?';
    }
    if (mounted) setState(() => _envoi = false);
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
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const EnTeteRetour(
                    titre: 'Le Relais',
                    regle: 'Un membre lance le relais avec un film qu\'il a vu. Le suivant a 48 heures pour poser un film vu depuis, qui a quelqu\'un en commun avec le précédent.\n'
                        'Acteur en commun : +1. Réalisateur : +2. Compositeur : +3. Le lien le plus fort compte.\n'
                        'Jamais deux fois de suite la même personne. Délai dépassé : le relais casse, et un nouveau peut partir. Chaque relais passé rapporte 2 d\'audace.',
                  ),
                  const SizedBox(height: 14),
                  FutureBuilder<(List<Classe>, List<Chaine>)>(
                    future: _donnees,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) return const PopQuiParle(texte: 'Je démêle la pellicule…');
                      if (snap.hasError || snap.data == null) {
                        return const Panneau(couleur: AuraCouleurs.jaune, child: Text('Le Relais n\'est pas encore installé sur le serveur (migration 0009).'));
                      }
                      final (membres, chaines) = snap.data!;
                      return _contenu(etat, membres, chaines);
                    },
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contenu(EtatJeu etat, List<Classe> membres, List<Chaine> chaines) {
    final moi = widget.ligues.monId;
    final maintenant = DateTime.now();
    final enCours = chaines.where((c) => !c.expiree(maintenant)).firstOrNull;
    final record = Relais.record(chaines);
    String nom(String? id) => id == moi ? 'toi' : membres.where((m) => m.joueurId == id).firstOrNull?.pseudo ?? '?';
    final depuis = enCours?.maillons.last.quand ?? maintenant.subtract(const Duration(days: 14));
    final mesFilms = etat.billets.where((b) => b.date.isAfter(depuis)).take(8).toList();
    final aMoi = enCours == null || enCours.porteur == moi;
    final blocs = <Widget>[
      const PopQuiParle(
        texte: 'Un film, puis un autre qui a quelqu\'un en commun. 48 heures chacun. Battez le record.',
      ),
      Panneau(
        couleur: AuraCouleurs.jaune,
        child: Text('RECORD DE LA LIGUE : $record FILM${record > 1 ? 'S' : ''}${enCours != null ? ' · RELAIS EN COURS : ${enCours.maillons.length} (${enCours.points} pts)' : ''}', style: AuraTexte.titre(16)),
      ),
      if (enCours != null)
        for (final (i, m) in enCours.maillons.indexed) ...[
          if (m.lien != null) Center(child: Text('↓ ${m.lien!.phrase} (+${m.lien!.points})', style: AuraTexte.corps(14, poids: FontWeight.w900, couleur: AuraCouleurs.creme))),
          Entree(
            delai: Duration(milliseconds: 80 * i),
            child: Panneau(
              child: Text('${m.titre}${m.annee != null ? ' (${m.annee})' : ''} · ${nom(m.joueur)}', style: AuraTexte.corps(16, poids: FontWeight.w900)),
            ),
          ),
        ],
      if (enCours != null && !aMoi)
        Text('À ${nom(enCours.porteur)} de jouer : il reste ${enCours.echeance!.difference(maintenant).inHours} h.', style: AuraTexte.corps(15, poids: FontWeight.w900, couleur: AuraCouleurs.creme)),
      if (aMoi) ...[
        Text(enCours == null ? 'LANCE UN RELAIS AVEC UN FILM QUE TU AS VU' : 'À TOI ! POSE UN FILM VU DEPUIS LE DERNIER RELAIS', style: AuraTexte.titre(16, couleur: AuraCouleurs.creme)),
        if (mesFilms.isEmpty)
          Text(enCours == null ? 'Vois un film d\'abord, puis reviens.' : 'Vois un film qui a quelqu\'un en commun avec « ${enCours.maillons.last.titre} », puis reviens.',
              style: AuraTexte.corps(14, couleur: AuraCouleurs.creme))
        else
          for (final (i, b) in mesFilms.indexed)
            ChoixLarge(libelle: '${b.titre}${b.annee != null ? ' (${b.annee})' : ''}', autofocus: i == 0, onTap: _envoi ? null : () => _poser(etat, membres, enCours, b)),
      ],
      if (_message != null) Panneau(couleur: AuraCouleurs.jaune, child: Text(_message!, style: AuraTexte.corps(14, poids: FontWeight.w900))),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, b) in blocs.indexed) ...[if (i > 0) const SizedBox(height: 10), b],
    ]);
  }
}
