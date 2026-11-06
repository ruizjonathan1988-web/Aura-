import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/modeles.dart';
import 'fidelite.dart';
import 'ligues.dart';
import 'plan_du_jour.dart';
import 'pop.dart';
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
    this.note,
    this.auto = false,
    this.envoye = false,
    this.genres = const [],
    this.annee,
    this.pays = const [],
  });

  final String titre;
  final String type;
  final int pronostic;
  final int cases;
  final DateTime date;
  final String verdict;

  /// La vraie note donnée après la séance, à comparer au pronostic.
  final int? note;

  /// De quoi placer la séance sur la carte des genres.
  final List<String> genres;
  final int? annee;
  final List<String> pays;

  /// Vrai si le billet s'est créé tout seul (Jellyfin a vu le film passer).
  final bool auto;

  /// Un billet automatique attend encore la note du joueur.
  bool get aNoter => auto && note == null;

  /// Vrai quand la séance est arrivée sur le serveur des ligues.
  final bool envoye;

  Billet copie({int? note, bool? envoye}) => Billet(
        titre: titre,
        type: type,
        pronostic: pronostic,
        cases: cases,
        date: date,
        verdict: verdict,
        note: note ?? this.note,
        auto: auto,
        envoye: envoye ?? this.envoye,
        genres: genres,
        annee: annee,
        pays: pays,
      );

  Billet marqueEnvoye() => copie(envoye: true);

  Map<String, dynamic> versJson() => {
        'titre': titre,
        'type': type,
        'pronostic': pronostic,
        'cases': cases,
        'date': date.toIso8601String(),
        'verdict': verdict,
        if (note != null) 'note': note,
        'auto': auto,
        'envoye': envoye,
        if (genres.isNotEmpty) 'genres': genres,
        if (annee != null) 'annee': annee,
        if (pays.isNotEmpty) 'pays': pays,
      };

  static Billet depuisJson(Map<String, dynamic> j) => Billet(
        titre: j['titre'] as String,
        type: j['type'] as String,
        pronostic: j['pronostic'] as int,
        cases: j['cases'] as int,
        date: DateTime.parse(j['date'] as String),
        verdict: (j['verdict'] as String?) ?? '',
        note: j['note'] as int?,
        auto: (j['auto'] as bool?) ?? false,
        envoye: (j['envoye'] as bool?) ?? false,
        genres: (j['genres'] as List? ?? const []).cast<String>(),
        annee: j['annee'] as int?,
        pays: (j['pays'] as List? ?? const []).cast<String>(),
      );
}

/// Une carte jouée dont le film n'est pas encore validé. Elle survit à la
/// fermeture de l'appli : c'est elle qui permet de ne perdre aucune séance.
class SeanceEnCours {
  const SeanceEnCours({
    required this.titre,
    required this.filmId,
    required this.jellyfin,
    required this.type,
    required this.cases,
    required this.pronostic,
    required this.debut,
    this.genres = const [],
    this.annee,
    this.pays = const [],
  });

  final String titre;
  final String filmId;
  final List<String> genres;
  final int? annee;
  final List<String> pays;

  /// Vrai si le film vient de la bibliothèque Jellyfin : on peut alors
  /// demander au serveur s'il a été vu.
  final bool jellyfin;
  final String type;
  final int cases;
  final int pronostic;
  final DateTime debut;

  Map<String, dynamic> versJson() => {
        'titre': titre,
        'film': filmId,
        'jellyfin': jellyfin,
        'type': type,
        'cases': cases,
        'pronostic': pronostic,
        'debut': debut.toIso8601String(),
        if (genres.isNotEmpty) 'genres': genres,
        if (annee != null) 'annee': annee,
        if (pays.isNotEmpty) 'pays': pays,
      };

  static SeanceEnCours depuisJson(Map<String, dynamic> j) => SeanceEnCours(
        titre: j['titre'] as String,
        filmId: j['film'] as String,
        jellyfin: (j['jellyfin'] as bool?) ?? false,
        type: j['type'] as String,
        cases: j['cases'] as int,
        pronostic: j['pronostic'] as int,
        debut: DateTime.parse(j['debut'] as String),
        genres: (j['genres'] as List? ?? const []).cast<String>(),
        annee: j['annee'] as int?,
        pays: (j['pays'] as List? ?? const []).cast<String>(),
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

  /// Les cartes jouées qui attendent d'être validées.
  List<SeanceEnCours> enCours = [];

  /// Le dernier mot de Pop après une séance, affiché sur le plateau.
  String? motDePop;

  /// La case de Pop, l'adversaire du solo.
  int get positionDePop => Pop.position(DateTime.now(), billets);

  static Future<EtatJeu> ouvrir({ServiceLigues? ligues}) async {
    final etat = EtatJeu(await SharedPreferences.getInstance(), ligues: ligues);
    if (ligues != null) {
      ligues.demarrer().then((_) => etat.synchroniser());
    }
    etat.verifierSeances();
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
    _noterVisite();
    enCours = (_prefs.getStringList('en_cours') ?? const [])
        .map((s) => SeanceEnCours.depuisJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
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

  /// Identifiant stable de cet appareil (demandé par Jellyfin à la connexion).
  String get appareil {
    final deja = _prefs.getString('appareil');
    if (deja != null) return deja;
    final r = Random();
    final id = 'aura-${List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join()}';
    _prefs.setString('appareil', id);
    return id;
  }

  SourceFilms get source =>
      mode == ModeJeu.vjod && connexion.complete ? SourceJellyfin(connexion) : SourceDemo();

  int get casesAujourdhui => casesLe(DateTime.now());

  int casesLe(DateTime d) => billets
      .where((b) => b.date.year == d.year && b.date.month == d.month && b.date.day == d.day)
      .fold(0, (s, b) => s + b.cases);

  // Le premier soir : test, figurine, Bluff contre Pop.

  /// Vrai une fois le parcours d'accueil terminé (ou passé).
  bool get accueilFait => _prefs.getBool('accueil_fait') ?? false;

  /// Après une pause de quelques jours : le nombre de jours d'absence, pour
  /// l'accueil « Bon retour » de cette ouverture (null sinon).
  int? bonRetour;

  void _noterVisite() {
    final maintenant = DateTime.now();
    final brut = _prefs.getString('derniere_visite');
    final jours = Fidelite.joursDAbsence(brut == null ? null : DateTime.tryParse(brut), maintenant);
    if (jours != null && jours >= Fidelite.pause && (_prefs.getStringList('billets') ?? const []).isNotEmpty) {
      bonRetour = jours;
      _prefs.setBool('carte_rattrapage', true);
    }
    _prefs.setString('derniere_visite', maintenant.toIso8601String());
  }

  /// La carte de rattrapage offerte au retour : +2 cases sur la prochaine
  /// séance, dans la limite des 3 cases du jour.
  bool get carteRattrapage => _prefs.getBool('carte_rattrapage') ?? false;

  /// La série en semaines (pauses gratuites comprises).
  int get serie => Fidelite.serie(DateTime.now(), billets);

  /// Le Joker gagné au Bluff du premier soir : +1 case sur la prochaine
  /// séance, dans la limite des 3 cases du jour.
  bool get jokerBluff => _prefs.getBool('joker_bluff') ?? false;

  Future<void> terminerAccueil({Profil? profil, bool bluffGagne = false}) async {
    if (profil != null) await choisirProfil(profil);
    if (bluffGagne) await _prefs.setBool('joker_bluff', true);
    await _prefs.setBool('accueil_fait', true);
    notifyListeners();
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
  Future<int> validerSeance(CarteDefi carte, {required int pronostic, int? note, String verdict = ''}) async {
    enCours = enCours.where((s) => s.filmId != carte.film.id).toList();
    await _sauverEnCours();
    return _ajouterBillet(
      titre: carte.film.titre,
      type: carte.type.libelle,
      demandees: carte.cases,
      pronostic: pronostic,
      note: note,
      verdict: verdict,
      date: DateTime.now(),
      film: carte.film,
    );
  }

  Future<int> _ajouterBillet({
    required String titre,
    required String type,
    required int demandees,
    required int pronostic,
    required DateTime date,
    int? note,
    String verdict = '',
    bool auto = false,
    Film? film,
    List<String> genres = const [],
    int? annee,
    List<String> pays = const [],
  }) async {
    _nouveauMois();
    final maintenant = DateTime.now();
    final ceMois = moisDe(date) == moisDe(maintenant);
    final joker = jokerBluff && ceMois;
    final rattrapage = carteRattrapage && ceMois;
    final bonus = (joker ? 1 : 0) + (rattrapage ? Fidelite.rattrapage : 0);
    final cases = ceMois ? Regles.casesAccordees(demandees: demandees + bonus, dejaGagneesAujourdhui: casesLe(date)) : 0;
    if (joker) await _prefs.setBool('joker_bluff', false);
    if (rattrapage) await _prefs.setBool('carte_rattrapage', false);
    final pariAvant = Pop.parisPerdus(maintenant, billets);
    billets = [
      Billet(
        titre: titre,
        type: type,
        pronostic: pronostic,
        cases: cases,
        date: date,
        verdict: verdict,
        note: note,
        auto: auto,
        genres: film?.genres ?? genres,
        annee: film?.annee ?? annee,
        pays: film?.pays ?? pays,
      ),
      ...billets,
    ]..sort((a, b) => b.date.compareTo(a.date));
    final pariGagne = Pop.parisPerdus(maintenant, billets) > pariAvant;
    _direPop([
      if (note != null) Pop.surPronostic(pronostic: pronostic, note: note, graine: billets.length),
      if (pariGagne) 'Zut, j\'ai perdu mon pari : je recule de ${Pop.recul} cases. Mais je reviendrai.',
    ]);
    position = (position + cases).clamp(1, Regles.taillePlateau);
    await _prefs.setInt('position', position);
    await _sauverBillets();
    await _prefs.setInt('stat_billets', (_prefs.getInt('stat_billets') ?? 0) + 1);
    notifyListeners();
    synchroniser();
    return cases;
  }

  void _direPop(List<String> phrases) {
    final m = phrases.join(' ');
    motDePop = m.isEmpty ? null : m;
  }

  // La validation sans effort : la carte jouée est gardée, et le billet se
  // crée dès qu'on sait que le film a été vu.

  /// La carte est jouée : on la garde jusqu'à ce que le film soit vu.
  Future<void> commencerSeance(CarteDefi carte, {required int pronostic}) async {
    if (enCours.any((s) => s.filmId == carte.film.id)) return;
    enCours = [
      SeanceEnCours(
        titre: carte.film.titre,
        filmId: carte.film.id,
        jellyfin: carte.film.source == SourceFilm.jellyfin,
        type: carte.type.libelle,
        cases: carte.cases,
        pronostic: pronostic,
        debut: DateTime.now(),
        genres: carte.film.genres,
        annee: carte.film.annee,
        pays: carte.film.pays,
      ),
      ...enCours,
    ].take(5).toList();
    await _sauverEnCours();
    await _prefs.setInt('stat_cartes', (_prefs.getInt('stat_cartes') ?? 0) + 1);
    notifyListeners();
  }

  /// « Alors, ce film ? » : une note, et le billet est validé.
  Future<int> validerEnCours(SeanceEnCours s, {int? note, DateTime? vuLe, bool auto = false}) async {
    enCours = enCours.where((x) => x.filmId != s.filmId).toList();
    await _sauverEnCours();
    return _ajouterBillet(
      titre: s.titre,
      type: s.type,
      demandees: s.cases,
      pronostic: s.pronostic,
      note: note,
      date: vuLe ?? DateTime.now(),
      auto: auto,
      genres: s.genres,
      annee: s.annee,
      pays: s.pays,
    );
  }

  final _reportees = <String>{};

  /// Les séances en attente à proposer maintenant (sans celles qu'on a
  /// reportées pendant cette ouverture de l'appli).
  List<SeanceEnCours> get enCoursAVoir => enCours.where((s) => !_reportees.contains(s.filmId)).toList();

  /// « Pas encore vu » : on n'insiste pas, on redemandera plus tard.
  void reporterSeance(SeanceEnCours s) {
    _reportees.add(s.filmId);
    notifyListeners();
  }

  Future<void> abandonnerSeance(SeanceEnCours s) async {
    enCours = enCours.where((x) => x.filmId != s.filmId).toList();
    await _sauverEnCours();
    notifyListeners();
  }

  /// Demande à Jellyfin si les films en attente ont été vus. Ceux qui l'ont
  /// été deviennent des billets, sans rien demander au joueur.
  /// Renvoie le nombre de billets créés.
  Future<int> verifierSeances() async {
    final c = connexion;
    if (!c.complete || _verification) return 0;
    _verification = true;
    var crees = 0;
    try {
      final jellyfin = SourceJellyfin(c);
      for (final s in [...enCours.where((s) => s.jellyfin)]) {
        final vu = await jellyfin.vuDepuis(s.filmId, s.debut);
        if (vu != null) {
          await validerEnCours(s, vuLe: vu, auto: true);
          crees++;
        }
      }
    } catch (_) {
      // Serveur injoignable : on réessaiera à la prochaine ouverture.
    } finally {
      _verification = false;
    }
    return crees;
  }

  bool _verification = false;

  /// Le plus récent billet automatique qui attend sa note (7 jours au plus).
  Billet? get billetANoter {
    final limite = DateTime.now().subtract(const Duration(days: 7));
    for (final b in billets) {
      if (b.aNoter && b.date.isAfter(limite)) return b;
    }
    return null;
  }

  /// La note donnée en un geste après coup. Pop a son mot à dire.
  Future<void> noterBillet(Billet b, int note) async {
    final i = billets.indexOf(b);
    if (i < 0) return;
    billets[i] = b.copie(note: note);
    _direPop([Pop.surPronostic(pronostic: b.pronostic, note: note, graine: billets.length)]);
    await _sauverBillets();
    notifyListeners();
    synchroniser();
  }

  /// Part des cartes jouées qui finissent en billet : le chiffre qui dit si
  /// la validation fuit.
  double? get tauxDeValidation {
    final cartes = _prefs.getInt('stat_cartes') ?? 0;
    if (cartes == 0) return null;
    return ((_prefs.getInt('stat_billets') ?? 0) / cartes).clamp(0, 1).toDouble();
  }

  Future<void> _sauverEnCours() =>
      _prefs.setStringList('en_cours', enCours.map((s) => jsonEncode(s.versJson())).toList());

  /// Envoie aux ligues les séances du mois qui ne sont pas encore parties.
  Future<void> synchroniser() async {
    final l = ligues;
    if (l == null || !l.inscrit) return;
    final mois = moisDe(DateTime.now());
    var change = false;
    for (var i = 0; i < billets.length; i++) {
      final b = billets[i];
      if (b.envoye || moisDe(b.date) != mois) continue;
      if (b.aNoter && DateTime.now().difference(b.date).inDays < 2) continue; // on attend la note
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

  // Le Bluff de la semaine contre Pop : un seul essai par semaine.

  /// null si pas encore joué, sinon vrai si le vrai synopsis a été trouvé.
  bool? bluffDe(String semaine) => _prefs.getBool('bluff_$semaine');

  Future<void> jouerBluff(String semaine, {required bool trouve}) async {
    if (bluffDe(semaine) != null) return;
    await _prefs.setBool('bluff_$semaine', trouve);
    if (trouve) await _prefs.setBool('joker_bluff', true);
    notifyListeners();
  }

  // L'Affiche de la semaine : le Curseur placé après la séance.

  int? curseurDe(String semaine) => _prefs.getInt('curseur_$semaine');

  Future<void> placerCurseur(String semaine, int valeur) async {
    await _prefs.setInt('curseur_$semaine', valeur);
    notifyListeners();
  }
}
