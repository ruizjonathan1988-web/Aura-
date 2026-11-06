import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/config.dart';
import '../services/connexion_vjod.dart';
import '../services/etat.dart';
import '../services/historique.dart';
import '../services/mise_a_jour.dart';
import '../services/sources.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';
import '../widgets/fenetre_mise_a_jour.dart';

enum _Methode { quickConnect, identifiants, cle }

/// Réglages : jouer avec la sélection de démonstration, ou brancher sa
/// bibliothèque VJOD. Trois façons de se connecter, de la plus simple à la
/// plus technique : un code Quick Connect, l'identifiant et le mot de passe
/// VJOD, ou (avancé) l'identifiant Jellyfin et une clé d'API.
class ReglagesEcran extends StatefulWidget {
  const ReglagesEcran({super.key});

  @override
  State<ReglagesEcran> createState() => _ReglagesEcranState();
}

class _ReglagesEcranState extends State<ReglagesEcran> {
  final _adresse = TextEditingController();
  final _nom = TextEditingController();
  final _motDePasse = TextEditingController();
  final _utilisateurId = TextEditingController();
  final _cle = TextEditingController();
  bool _pret = false;
  bool _vjod = false;
  _Methode _methode = _Methode.quickConnect;
  bool _enCours = false;
  String? _message;
  String? _code;
  Timer? _attente;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pret) return;
    _pret = true;
    final etat = PorteeEtat.lire(context);
    _vjod = etat.mode == ModeJeu.vjod;
    _adresse.text = etat.connexion.adresse.isNotEmpty ? etat.connexion.adresse : Config.serveurVjod;
    _utilisateurId.text = etat.connexion.utilisateurId;
    _cle.text = etat.connexion.jeton;
    if (!estTele(context)) _methode = _Methode.identifiants;
  }

  @override
  void dispose() {
    _attente?.cancel();
    for (final c in [_adresse, _nom, _motDePasse, _utilisateurId, _cle]) {
      c.dispose();
    }
    super.dispose();
  }

  ConnexionVjod get _vjodClient => ConnexionVjod(adresse: _adresse.text, appareil: PorteeEtat.lire(context).appareil);

  Future<void> _brancher(ConnexionJellyfin c) async {
    final etat = PorteeEtat.lire(context);
    try {
      final films = await SourceJellyfin(c).catalogue(emotion: Emotion.frissonner);
      await etat.reglerVjod(actif: true, c: c);
      _message = 'Bibliothèque VJOD branchée ! ${films.length} films à 3 étoiles ou plus rien que pour « Frissonner ».';
    } on ErreurSource catch (e) {
      _message = e.message;
    } catch (_) {
      _message = 'Connecté, mais la bibliothèque ne répond pas. Réessaie dans un instant.';
    }
  }

  Future<void> _seConnecter() async {
    setState(() {
      _enCours = true;
      _message = null;
    });
    try {
      final c = switch (_methode) {
        _Methode.identifiants => await _vjodClient.avecIdentifiants(_nom.text, _motDePasse.text),
        _Methode.cle => ConnexionJellyfin(adresse: _adresse.text.trim(), utilisateurId: _utilisateurId.text.trim(), jeton: _cle.text.trim()),
        _Methode.quickConnect => throw StateError('Quick Connect passe par le code'),
      };
      await _brancher(c);
    } on ErreurSource catch (e) {
      _message = e.message;
    } catch (_) {
      _message = 'Le serveur ne répond pas à cette adresse. Vérifie-la (la même que dans VJOD).';
    }
    if (mounted) setState(() => _enCours = false);
  }

  Future<void> _demanderCode() async {
    _attente?.cancel();
    setState(() {
      _enCours = true;
      _message = null;
      _code = null;
    });
    final client = _vjodClient;
    try {
      final (secret, code) = await client.demanderCode();
      if (!mounted) return;
      setState(() => _code = code);
      var essais = 0;
      _attente = Timer.periodic(const Duration(seconds: 3), (t) async {
        if (!mounted) {
          t.cancel();
          return;
        }
        essais++;
        if (essais > 100) {
          t.cancel();
          if (mounted) setState(() => _message = 'Le code a expiré. Demandes-en un nouveau.');
          return;
        }
        try {
          if (await client.codeAccepte(secret)) {
            t.cancel();
            final c = await client.avecQuickConnect(secret);
            await _brancher(c);
            if (mounted) setState(() => _code = null);
          }
        } catch (_) {
          // On réessaie au prochain passage.
        }
      });
    } on ErreurSource catch (e) {
      _message = e.message;
    } catch (_) {
      _message = 'Le serveur ne répond pas à cette adresse. Vérifie-la (la même que dans VJOD).';
    }
    if (mounted) setState(() => _enCours = false);
  }

  Future<void> _demo() async {
    final etat = PorteeEtat.lire(context);
    await etat.reglerVjod(actif: false, c: etat.connexion);
    if (mounted) setState(() => _vjod = false);
  }

  Future<void> _chercherMiseAJour() async {
    setState(() => _message = 'Je regarde s\'il y a une nouvelle version…');
    final v = await MiseAJour.verifier(forcer: true);
    if (!mounted) return;
    setState(() => _message = v == null ? 'Pas de nouvelle version : Aura est à jour (ou GitHub ne répond pas).' : null);
    if (v != null) await proposerMiseAJour(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    final branche = etat.mode == ModeJeu.vjod && etat.connexion.complete;
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
                    const EnTeteRetour(titre: 'Réglages'),
                    const SizedBox(height: 18),
                    Panneau(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('OÙ LE JEU CHOISIT TES FILMS', style: AuraTexte.titre(16)),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          Pastille(libelle: 'Sélection Aura', choisie: !_vjod, onTap: _demo),
                          Pastille(libelle: 'Ma bibliothèque VJOD', choisie: _vjod, autofocus: true, onTap: () => setState(() => _vjod = true)),
                        ]),
                        const SizedBox(height: 10),
                        Text(
                          _vjod
                              ? 'Les cartes viennent de ta bibliothèque VJOD, et « Lancer dans VJOD » ouvre le film directement, sur la télé comme sur le téléphone. Les films que tu termines sont validés automatiquement.'
                              : 'Une sélection de 42 films reconnus, pour découvrir le jeu sans serveur.',
                          style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux),
                        ),
                        if (branche) ...[
                          const SizedBox(height: 10),
                          Text('Connecté à ${etat.connexion.adresse}', style: AuraTexte.corps(13, poids: FontWeight.w900)),
                        ],
                      ]),
                    ),
                    if (_vjod) ...[const SizedBox(height: 16), _connexion()],
                    const SizedBox(height: 16),
                    const _Historique(),
                    if (MiseAJour.possible) ...[
                      const SizedBox(height: 16),
                      AuraBouton(libelle: 'Chercher une mise à jour', icone: Icons.system_update_rounded, principal: false, onPressed: _chercherMiseAJour),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Aura compte de façon anonyme les ouvertures, les cartes jouées et les séances validées, pour devenir plus amusant. Ni nom, ni e-mail, ni titre de film.',
                      style: AuraTexte.corps(12, couleur: AuraCouleurs.creme),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 14),
                      Panneau(couleur: AuraCouleurs.jaune, child: Text(_message!, style: AuraTexte.corps(14, poids: FontWeight.w900))),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _connexion() {
    return Panneau(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('SE CONNECTER AVEC VJOD', style: AuraTexte.titre(16)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pastille(libelle: 'Avec un code', choisie: _methode == _Methode.quickConnect, onTap: () => setState(() => _methode = _Methode.quickConnect)),
          if (!estTele(context))
            Pastille(libelle: 'Identifiant et mot de passe', choisie: _methode == _Methode.identifiants, onTap: () => setState(() => _methode = _Methode.identifiants)),
          Pastille(libelle: 'Avancé', choisie: _methode == _Methode.cle, onTap: () => setState(() => _methode = _Methode.cle)),
        ]),
        const SizedBox(height: 14),
        Text('ADRESSE DU SERVEUR', style: AuraTexte.titre(14)),
        const SizedBox(height: 6),
        _champ(_adresse, 'La même que dans VJOD, par exemple https://…'),
        const SizedBox(height: 12),
        ...switch (_methode) {
          _Methode.quickConnect => _quickConnect(),
          _Methode.identifiants => [
              Text('TON IDENTIFIANT VJOD', style: AuraTexte.titre(14)),
              const SizedBox(height: 6),
              _champ(_nom, 'Ton nom d\'utilisateur'),
              const SizedBox(height: 10),
              Text('TON MOT DE PASSE', style: AuraTexte.titre(14)),
              const SizedBox(height: 6),
              _champ(_motDePasse, 'Ton mot de passe', secret: true),
              const SizedBox(height: 12),
              AuraBouton(libelle: _enCours ? 'Connexion…' : 'Me connecter', onPressed: _enCours ? null : _seConnecter),
            ],
          _Methode.cle => [
              Text('IDENTIFIANT UTILISATEUR JELLYFIN', style: AuraTexte.titre(14)),
              const SizedBox(height: 6),
              _champ(_utilisateurId, 'Dans l\'adresse de la page de ton profil Jellyfin'),
              const SizedBox(height: 10),
              Text('CLÉ D\'API', style: AuraTexte.titre(14)),
              const SizedBox(height: 6),
              _champ(_cle, 'Tableau de bord Jellyfin, Clés API, puis « + »', secret: true),
              const SizedBox(height: 12),
              AuraBouton(libelle: _enCours ? 'Vérification…' : 'Brancher', onPressed: _enCours ? null : _seConnecter),
            ],
        },
      ]),
    );
  }

  List<Widget> _quickConnect() => [
        if (_code == null) ...[
          Text(
            'Aura affiche un code. Sur ton téléphone, dans VJOD ou Jellyfin, ouvre Paramètres puis Quick Connect, et entre ce code. C\'est tout.',
            style: AuraTexte.corps(14),
          ),
          const SizedBox(height: 12),
          AuraBouton(libelle: _enCours ? 'Demande en cours…' : 'Afficher mon code', onPressed: _enCours ? null : _demanderCode),
        ] else ...[
          Text('TON CODE', style: AuraTexte.titre(14)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            decoration: AuraTrait.panneau(couleur: AuraCouleurs.jaune),
            child: Text(_code!, style: AuraTexte.titre(52).copyWith(letterSpacing: 10)),
          ),
          const SizedBox(height: 10),
          Text('Entre-le dans VJOD ou Jellyfin, sur ton téléphone : Paramètres, puis Quick Connect. Aura se connecte dès que c\'est accepté.',
              style: AuraTexte.corps(14)),
          const SizedBox(height: 12),
          AuraBouton(libelle: 'Nouveau code', principal: false, onPressed: _enCours ? null : _demanderCode),
        ],
      ];

  /// Le seul endroit où l'on tape sur la télé : l'adresse du serveur, et
  /// seulement si elle n'est pas déjà connue (exception à la règle R10).
  Widget _champ(TextEditingController c, String indication, {bool secret = false}) => TextField(
        controller: c,
        obscureText: secret,
        style: AuraTexte.corps(15),
        decoration: InputDecoration(
          hintText: indication,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(width: 2.5)),
        ),
      );
}

/// Importer son historique Letterboxd : les films déjà vus ne sont plus
/// proposés. Au téléphone (choisir un fichier sur la télé n'a pas de sens).
class _Historique extends StatefulWidget {
  const _Historique();

  @override
  State<_Historique> createState() => _HistoriqueState();
}

class _HistoriqueState extends State<_Historique> {
  String? _message;
  bool _enCours = false;

  Future<void> _importer() async {
    final etat = PorteeEtat.lire(context);
    setState(() {
      _enCours = true;
      _message = null;
    });
    try {
      final choix = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip', 'csv'], withData: true);
      final fichier = choix?.files.firstOrNull;
      if (fichier?.bytes == null) {
        _message = null;
      } else {
        final films = Historique.lireExport(fichier!.bytes!, fichier.name);
        if (films.isEmpty) {
          _message = 'Aucun film trouvé dans ce fichier. Choisis le .zip exporté par Letterboxd (ou watched.csv).';
        } else {
          final nouveaux = await etat.importerHistorique(films);
          _message = '$nouveaux film${nouveaux > 1 ? 's' : ''} importé${nouveaux > 1 ? 's' : ''} : Aura ne te les proposera plus.';
        }
      }
    } catch (_) {
      _message = 'Ce fichier n\'a pas pu être lu. Choisis le .zip exporté par Letterboxd.';
    }
    if (mounted) setState(() => _enCours = false);
  }

  @override
  Widget build(BuildContext context) {
    final etat = PorteeEtat.of(context);
    final n = etat.historique.length;
    return Panneau(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('TON HISTORIQUE LETTERBOXD', style: AuraTexte.titre(16)),
        const SizedBox(height: 6),
        Text(
          n == 0
              ? 'Importe les films que tu as déjà vus : Aura ne te les proposera plus. Sur Letterboxd : Paramètres, Import et export, « Export your data », puis choisis ici le fichier .zip reçu.'
              : '$n films de ton historique sont connus d\'Aura : ils ne te seront plus proposés.',
          style: AuraTexte.corps(13),
        ),
        const SizedBox(height: 10),
        if (estTele(context))
          Text('L\'import se fait depuis le téléphone.', style: AuraTexte.corps(13, poids: FontWeight.w900))
        else
          AuraBouton(libelle: _enCours ? 'Lecture…' : 'Importer depuis Letterboxd', principal: false, onPressed: _enCours ? null : _importer),
        if (n > 0) ...[
          const SizedBox(height: 8),
          AuraBouton(libelle: 'Effacer l\'historique importé', principal: false, onPressed: () => etat.effacerHistorique()),
        ],
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(_message!, style: AuraTexte.corps(14, poids: FontWeight.w900)),
        ],
      ]),
    );
  }
}
