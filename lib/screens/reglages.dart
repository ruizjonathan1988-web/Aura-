import 'package:flutter/material.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/etat.dart';
import '../services/sources.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';

/// Réglages : jouer en démo, ou en édition VJOD branchée sur Jellyfin.
class ReglagesEcran extends StatefulWidget {
  const ReglagesEcran({super.key});

  @override
  State<ReglagesEcran> createState() => _ReglagesEcranState();
}

class _ReglagesEcranState extends State<ReglagesEcran> {
  late final TextEditingController _adresse;
  late final TextEditingController _utilisateur;
  late final TextEditingController _jeton;
  bool _vjod = false;
  bool _test = false;
  String? _resultat;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resultat == null && !_test) {
      final etat = PorteeEtat.of(context);
      _vjod = etat.mode == ModeJeu.vjod;
      _adresse = TextEditingController(text: etat.connexion.adresse);
      _utilisateur = TextEditingController(text: etat.connexion.utilisateurId);
      _jeton = TextEditingController(text: etat.connexion.jeton);
      _resultat = '';
    }
  }

  @override
  void dispose() {
    _adresse.dispose();
    _utilisateur.dispose();
    _jeton.dispose();
    super.dispose();
  }

  ConnexionJellyfin get _connexion =>
      ConnexionJellyfin(adresse: _adresse.text.trim(), utilisateurId: _utilisateur.text.trim(), jeton: _jeton.text.trim());

  Future<void> _tester() async {
    setState(() {
      _test = true;
      _resultat = '';
    });
    try {
      final films = await SourceJellyfin(_connexion).catalogue(emotion: Emotion.frissonner);
      _resultat = 'Connexion réussie : ${films.length} films à 3 étoiles ou plus pour « Frissonner ».';
    } on ErreurSource catch (e) {
      _resultat = e.message;
    } catch (_) {
      _resultat = 'Jellyfin ne répond pas à cette adresse.';
    }
    if (mounted) setState(() => _test = false);
  }

  Widget _champ(String libelle, TextEditingController c, {bool secret = false, String? aide}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: secret,
          style: AuraTexte.corps(15),
          decoration: InputDecoration(
            labelText: libelle,
            helperText: aide,
            helperMaxLines: 2,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(width: 2.5)),
          ),
        ),
      );

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
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Touchable(
                        etiquette: 'Retour',
                        onTap: () => Navigator.of(context).pop(),
                        builder: (context, focus, appui) => Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AuraCouleurs.creme,
                            shape: BoxShape.circle,
                            border: Border.all(width: 3),
                            boxShadow: [if (focus) const BoxShadow(color: AuraCouleurs.jaune, spreadRadius: 4)],
                          ),
                          child: const Icon(Icons.arrow_back_rounded, color: AuraCouleurs.noir),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(child: TitreCartoon('Réglages', taille: 38)),
                    ]),
                    const SizedBox(height: 18),
                    Panneau(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('OÙ LE JEU PIOCHE TES FILMS', style: AuraTexte.titre(16)),
                          const SizedBox(height: 10),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            Pastille(libelle: 'Démonstration', choisie: !_vjod, onTap: () => setState(() => _vjod = false)),
                            Pastille(libelle: 'Édition VJOD', choisie: _vjod, onTap: () => setState(() => _vjod = true)),
                          ]),
                          const SizedBox(height: 10),
                          Text(
                            _vjod
                                ? 'Les cartes viennent de ta bibliothèque Jellyfin, et « Lancer dans VJOD » ouvre le film directement dans VJOD, sur la télé comme sur le téléphone.'
                                : 'Un petit catalogue d\'exemple pour découvrir le jeu sans serveur.',
                            style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux),
                          ),
                        ],
                      ),
                    ),
                    if (_vjod) ...[
                      const SizedBox(height: 16),
                      Panneau(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('TA BIBLIOTHÈQUE JELLYFIN', style: AuraTexte.titre(16)),
                            const SizedBox(height: 12),
                            _champ('Adresse du serveur', _adresse, aide: 'La même que dans VJOD, par exemple https://…'),
                            _champ('Identifiant utilisateur Jellyfin', _utilisateur, aide: 'Tableau de bord Jellyfin, Utilisateurs : l\'identifiant est dans l\'adresse de la page du profil.'),
                            _champ('Clé d\'API', _jeton, secret: true, aide: 'Tableau de bord Jellyfin, Clés API, puis « + ».'),
                            AuraBouton(libelle: _test ? 'Test en cours…' : 'Tester la connexion', principal: false, onPressed: _test || !_connexion.complete ? null : _tester),
                            if ((_resultat ?? '').isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(_resultat!, style: AuraTexte.corps(14, poids: FontWeight.w900)),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    AuraBouton(
                      libelle: 'Enregistrer',
                      onPressed: () async {
                        await etat.reglerVjod(actif: _vjod, c: _connexion);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
