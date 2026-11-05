import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/modeles.dart';
import 'sources.dart';
import 'tirage.dart';

enum ModeJeu { demo, vjod }

/// Une séance validée : le billet que le joueur garde dans sa collection.
class Billet {
  const Billet({required this.titre, required this.type, required this.pronostic, required this.cases, required this.date, this.verdict = ''});

  final String titre;
  final String type;
  final int pronostic;
  final int cases;
  final DateTime date;
  final String verdict;

  Map<String, dynamic> versJson() =>
      {'titre': titre, 'type': type, 'pronostic': pronostic, 'cases': cases, 'date': date.toIso8601String(), 'verdict': verdict};

  static Billet depuisJson(Map<String, dynamic> j) => Billet(
        titre: j['titre'] as String,
        type: j['type'] as String,
        pronostic: j['pronostic'] as int,
        cases: j['cases'] as int,
        date: DateTime.parse(j['date'] as String),
        verdict: (j['verdict'] as String?) ?? '',
      );
}

/// L'état du joueur sur cet appareil. Les ligues partagées passeront par
/// Supabase ; le solo fonctionne sans compte.
class EtatJeu extends ChangeNotifier {
  EtatJeu(this._prefs) {
    _charger();
  }

  final SharedPreferences _prefs;

  Profil profil = Profil.fidele;
  ModeJeu mode = ModeJeu.demo;
  ConnexionJellyfin connexion = const ConnexionJellyfin(adresse: '', utilisateurId: '', jeton: '');
  int position = 1;
  List<Billet> billets = [];

  static Future<EtatJeu> ouvrir() async => EtatJeu(await SharedPreferences.getInstance());

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
    final cases = Regles.casesAccordees(demandees: carte.cases, dejaGagneesAujourdhui: casesAujourdhui);
    billets = [
      Billet(titre: carte.film.titre, type: carte.type.libelle, pronostic: pronostic, cases: cases, date: DateTime.now(), verdict: verdict),
      ...billets,
    ];
    position = (position + cases).clamp(1, Regles.taillePlateau);
    await _prefs.setInt('position', position);
    await _prefs.setStringList('billets', billets.map((b) => jsonEncode(b.versJson())).toList());
    notifyListeners();
    return cases;
  }
}
