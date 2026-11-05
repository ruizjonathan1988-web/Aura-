import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/modeles.dart';
import 'ligues.dart';
import 'plan_du_jour.dart';
import 'sources.dart';
import 'tirage.dart';

enum ModeJeu { demo, vjod }

/// Une séance validée : le billet que le joueur garde dans sa collection.
class Billet {
  const Billet({
    required this.titre,
    required this.type,
    required this.pronostic,
    required this.cases,
    required this.date,
    this.verdict = '',
    this.envoye = false,
  });

  final String titre;
  final String type;
  final int pronostic;
  final int cases;
  final DateTime date;
  final String verdict;

  /// Vrai quand la séance est arrivée sur le serveur des ligues.
  final bool envoye;

  Billet marqueEnvoye() =>
      Billet(titre: titre, type: type, pronostic: pronostic, cases: cases, date: date, verdict: verdict, envoye: true);

  Map<String, dynamic> versJson() => {
        'titre': titre,
        'type': type,
        'pronostic': pronostic,
        'cases': cases,
        'date': date.toIso8601String(),
        'verdict': verdict,
        'envoye': envoye,
      };

  static Billet depuisJson(Map<String, dynamic> j) => Billet(
        titre: j['titre'] as String,
        type: j['type'] as String,
        pronostic: j['pronostic'] as int,
        cases: j['cases'] as int,
        date: DateTime.parse(j['date'] as String),
        verdict: (j['verdict'] as String?) ?? '',
        envoye: (j['envoye'] as bool?) ?? false,
      );
}

/// L'état du joueur sur cet appareil. Le solo fonctionne sans compte ; les
/// ligues passent par [ligues] quand le serveur est configuré.
class EtatJeu extends ChangeNotifier {
  EtatJeu(this._prefs, {this.ligues}) {
    _charger();
  }

  final SharedPreferences _prefs;

  /// Le jeu partagé, ou null si Aura tourne sans serveur.
  final ServiceLigues? ligues;

  Profil profil = Profil.fidele;
  ModeJeu mode = ModeJeu.demo;
  ConnexionJellyfin connexion = const ConnexionJellyfin(adresse: '', utilisateurId: '', jeton: '');
  int position = 1;
  List<Billet> billets = [];

  static Future<EtatJeu> ouvrir({ServiceLigues? ligues}) async {
    final etat = EtatJeu(await SharedPreferences.getInstance(), ligues: ligues);
    if (ligues != null) {
      ligues.demarrer().then((_) => etat.synchroniser());
    }
    return etat;
  }

  static String moisDe(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  static String jourDe(DateTime d) => '${moisDe(d)}-${d.day.toString().padLeft(2, '0')}';

  void _charger() {
    profil = Profil.depuisNom(_prefs.getString('profil'));
    mode = _prefs.getString('mode') == 'vjod' ? ModeJeu.vjod : ModeJeu.demo;
    connexion = ConnexionJellyfin(
      adresse: _prefs.getString('jf_adresse') ?? '',
      utilisateurId: _prefs.getString('jf_utilisateur') ?? '',
      jeton: _prefs.getString('jf_jeton') ?? '',
    );
    position = _prefs.getInt('position') ?? 1;
    final brut = _prefs.getStringList('billets') ?? const [];
    billets = brut.map((s) => Billet.depuisJson(jsonDecode(s) as Map<String, dynamic>)).toList();
    _nouveauMois();
  }

  /// Le plateau est celui du mois : le 1er, tout le monde repart de la case 1.
  void _nouveauMois() {
    final ce = moisDe(DateTime.now());
    final enregistre = _prefs.getString('mois');
    if (enregistre == ce) return;
    if (enregistre != null) position = 1;
    _prefs.setString('mois', ce);
    _prefs.setInt('position', position);
  }

  SourceFilms get source =>
      mode == ModeJeu.vjod && connexion.complete ? SourceJellyfin(connexion) : SourceDemo();

  int get casesAujourdhui {
    final now = DateTime.now();
    return billets
        .where((b) => b.date.year == now.year && b.date.month == now.month && b.date.day == now.day)
        .fold(0, (s, b) => s + b.cases);
  }

  Future<void> choisirProfil(Profil p) async {
    profil = p;
    await _prefs.setString('profil', p.name);
    notifyListeners();
    await ligues?.changerProfil(p);
  }

  Future<void> reglerVjod({required bool actif, required ConnexionJellyfin c}) async {
    mode = actif ? ModeJeu.vjod : ModeJeu.demo;
    connexion = c;
    await _prefs.setString('mode', actif ? 'vjod' : 'demo');
    await _prefs.setString('jf_adresse', c.adresse.trim());
    await _prefs.setString('jf_utilisateur', c.utilisateurId.trim());
    await _prefs.setString('jf_jeton', c.jeton.trim());
    notifyListeners();
  }

  /// Valide une séance et avance le pion, dans la limite de 3 cases par jour.
  /// Renvoie le nombre de cases réellement gagnées.
  Future<int> validerSeance(CarteDefi carte, {required int pronostic, String verdict = ''}) async {
    _nouveauMois();
    final cases = Regles.casesAccordees(demandees: carte.cases, dejaGagneesAujourdhui: casesAujourdhui);
    billets = [
      Billet(titre: carte.film.titre, type: carte.type.libelle, pronostic: pronostic, cases: cases, date: DateTime.now(), verdict: verdict),
      ...billets,
    ];
    position = (position + cases).clamp(1, Regles.taillePlateau);
    await _prefs.setInt('position', position);
    await _sauverBillets();
    notifyListeners();
    synchroniser();
    return cases;
  }

  /// Envoie aux ligues les séances du mois qui ne sont pas encore parties.
  Future<void> synchroniser() async {
    final l = ligues;
    if (l == null || !l.inscrit) return;
    final mois = moisDe(DateTime.now());
    var change = false;
    for (var i = 0; i < billets.length; i++) {
      final b = billets[i];
      if (b.envoye || moisDe(b.date) != mois) continue;
      if (await l.envoyerSeance(b)) {
        billets[i] = b.marqueEnvoye();
        change = true;
      } else {
        break; // hors ligne : on réessaiera plus tard
      }
    }
    if (change) await _sauverBillets();
  }

  Future<void> _sauverBillets() =>
      _prefs.setStringList('billets', billets.map((b) => jsonEncode(b.versJson())).toList());

  // Le Plan du jour : un seul essai par jour.

  ResultatPlan? get planDuJour {
    if (_prefs.getString('plan_jour') != jourDe(DateTime.now())) return null;
    return ResultatPlan(indices: _prefs.getInt('plan_indices') ?? 3, trouve: _prefs.getBool('plan_trouve') ?? false);
  }

  Future<void> jouerPlanDuJour(ResultatPlan r) async {
    await _prefs.setString('plan_jour', jourDe(DateTime.now()));
    await _prefs.setInt('plan_indices', r.indices);
    await _prefs.setBool('plan_trouve', r.trouve);
    notifyListeners();
  }

  // L'Affiche de la semaine : le Curseur placé après la séance.

  int? curseurDe(String semaine) => _prefs.getInt('curseur_$semaine');

  Future<void> placerCurseur(String semaine, int valeur) async {
    await _prefs.setInt('curseur_$semaine', valeur);
    notifyListeners();
  }
}
