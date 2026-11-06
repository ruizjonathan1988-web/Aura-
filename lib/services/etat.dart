import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/modeles.dart';
import 'affiche.dart';
import 'carte_genres.dart';
import 'collection.dart';
import 'config.dart';
import 'coups.dart';
import 'fidelite.dart';
import 'historique.dart';
import 'ligues.dart';
import 'ma_tv.dart';
import 'mesures.dart';
import 'niveau.dart';
import 'plan_du_jour.dart';
import 'pop.dart';
import 'pouvoirs.dart';
import 'rappels.dart';
import 'source_tmdb.dart';
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
    this.niveau,
  });

  final String titre;
  final String type;
  final int pronostic;
  final int cases;
  final DateTime date;

  /// Le niveau annoncé pour cette séance (« Tu te mets combien ? »), s'il y en avait un.
  final int? niveau;
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
        niveau: niveau,
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
        if (niveau != null) 'niveau': niveau,
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
        niveau: j['niveau'] as int?,
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
    this.niveau,
    this.dureeMinutes,
    this.aPlusieurs = false,
  });

  final int? niveau;

  /// La durée du film, pour le pouvoir Court-métrage du Pressé.
  final int? dureeMinutes;

  /// Vrai si la séance a commencé à plusieurs (Duel, Soirée jeu) : pouvoir
  /// Projectionniste de l'Hôte.
  final bool aPlusieurs;

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
        if (niveau != null) 'niveau': niveau,
        if (dureeMinutes != null) 'duree': dureeMinutes,
        if (aPlusieurs) 'plusieurs': true,
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
        niveau: j['niveau'] as int?,
        dureeMinutes: j['duree'] as int?,
        aPlusieurs: (j['plusieurs'] as bool?) ?? false,
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

  /// Les mesures anonymes de rétention, ou null sans serveur.
  ServiceMesures? mesures;

  void _mesurer(String type, [Map<String, Object?> donnees = const {}]) {
    mesures?.noter(type, donnees);
  }

  Profil profil = Profil.fidele;
  ModeJeu mode = ModeJeu.demo;
  ConnexionJellyfin connexion = const ConnexionJellyfin(adresse: '', utilisateurId: '', jeton: '');
  int position = 1;
  List<Billet> billets = [];

  /// Les cartes jouées qui attendent d'être validées.
  List<SeanceEnCours> enCours = [];

  /// Vrai juste après une avancée : le pion saute sur sa nouvelle case à
  /// la prochaine visite du plateau.
  bool pionVientDAvancer = false;

  /// Le dernier mot de Pop après une séance, affiché sur le plateau.
  String? motDePop;

  /// La case de Pop, l'adversaire du solo.
  int get positionDePop =>
      (Pop.position(DateTime.now(), billets, boucliers: boucliers) + _decalageDePop(moisDe(DateTime.now()))).clamp(1, Regles.taillePlateau);

  /// Ce que les coups du sort ont fait gagner ou perdre à Pop ce mois-là.
  int _decalageDePop(String mois) => _prefs.getInt('pop_decalage_$mois') ?? 0;

  /// La carte des genres du mois, Boucliers compris.
  CarteDesGenres get carte => CarteDesGenres.de(DateTime.now(), billets, boucliers: boucliers);

  // Les Jokers du plateau : un de chaque par mois.

  /// Relance : retirer une nouvelle main de trois cartes.
  bool get relanceDispo => !(_prefs.getBool('relance_${moisDe(DateTime.now())}') ?? false);

  Future<void> utiliserRelance() async {
    await _prefs.setBool('relance_${moisDe(DateTime.now())}', true);
    notifyListeners();
  }

  /// Bouclier : Pop ne peut pas prendre la région qu'il vise cette semaine.
  bool get bouclierDispo => _prefs.getInt('bouclier_${moisDe(DateTime.now())}') == null;

  bool get bouclierCetteSemaine => boucliers.contains(CarteDesGenres.semaineDe(DateTime.now()));

  Set<int> get boucliers => _prefs.getKeys().where((k) => k.startsWith('bouclier_')).map(_prefs.getInt).whereType<int>().toSet();

  Future<void> poserBouclier() async {
    if (!bouclierDispo) return;
    await _prefs.setInt('bouclier_${moisDe(DateTime.now())}', CarteDesGenres.semaineDe(DateTime.now()));
    notifyListeners();
  }

  // La saison : le résultat contre Pop, gardé au changement de mois.

  /// Le résultat d'une saison passée : (ta case, celle de Pop, séances).
  (int, int, int)? resultatDeSaison(DateTime mois) {
    final brut = _prefs.getStringList('saison_${moisDe(mois)}');
    if (brut == null || brut.length < 3) return null;
    return (int.parse(brut[0]), int.parse(brut[1]), int.parse(brut[2]));
  }

  /// Le mois dont le générique attend d'être vu (le mois précédent, une fois).
  DateTime? get generiqueAVoir {
    final maintenant = DateTime.now();
    final precedent = DateTime(maintenant.year, maintenant.month - 1, 1);
    if (resultatDeSaison(precedent) == null) return null;
    if (_prefs.getBool('generique_vu_${moisDe(precedent)}') ?? false) return null;
    return precedent;
  }

  Future<void> generiqueVu(DateTime mois) async {
    await _prefs.setBool('generique_vu_${moisDe(mois)}', true);
    notifyListeners();
  }

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
    if (enregistre != null) {
      _finDeSaison(enregistre);
      position = 1;
    }
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

  /// Le mois [mois] (« 2026-10 ») se termine : on garde le résultat contre
  /// Pop pour le générique, et le titre de champion si on finit devant.
  void _finDeSaison(String mois) {
    final p = mois.split('-');
    final annee = int.tryParse(p.first);
    final m = int.tryParse(p.last);
    if (annee == null || m == null) return;
    final dernierJour = DateTime(annee, m + 1, 0, 23, 59);
    final duMois = billets.where((b) => b.date.year == annee && b.date.month == m).toList();
    final pop = (Pop.position(dernierJour, duMois, boucliers: boucliers) + _decalageDePop(mois)).clamp(1, Regles.taillePlateau);
    _prefs.setStringList('saison_$mois', ['$position', '$pop', '${duMois.length}']);
    if (position > pop && duMois.isNotEmpty) {
      _prefs.setStringList('collection', {...collection, 'champion'}.toList());
    }
  }

  SourceFilms get source {
    final SourceFilms base = mode == ModeJeu.vjod && connexion.complete
        // L'édition VJOD : ta bibliothèque, puis tout ce que VJOD peut lancer en VOD ou demander.
        ? (Config.tmdbCle.isEmpty
            ? SourceJellyfin(connexion)
            : SourceToutVjod(SourceJellyfin(connexion), SourceAvecMaTv(SourceTmdb(Config.tmdbCle), _maTvPour(connexion))))
        : SourceDemo();
    final vus = historique;
    return vus.isEmpty ? base : SourceAvecHistorique(base, vus);
  }

  // Ma TV garde ses réponses le temps de la session, tant que la connexion
  // ne change pas.
  MaTv? _maTv;
  MaTv _maTvPour(ConnexionJellyfin c) {
    final m = _maTv;
    if (m != null && m.connexion.adresse == c.adresse && m.connexion.jeton == c.jeton) return m;
    return _maTv = MaTv(c);
  }

  /// L'historique importé (Letterboxd) : des clés « titre|année ».
  Set<String> get historique => {...?_prefs.getStringList('historique')};

  /// Ajoute des films vus ailleurs ; renvoie combien sont nouveaux.
  Future<int> importerHistorique(List<FilmVu> films) async {
    final deja = historique;
    final nouveaux = films.map((f) => Historique.cle(f.titre, f.annee)).toSet().difference(deja);
    await _prefs.setStringList('historique', [...deja, ...nouveaux]);
    notifyListeners();
    return nouveaux.length;
  }

  Future<void> effacerHistorique() async {
    await _prefs.remove('historique');
    notifyListeners();
  }

  int get casesAujourdhui => casesLe(DateTime.now());

  List<int> get _abandons => [for (final n in _prefs.getStringList('niveaux_abandonnes') ?? const <String>[]) if (int.tryParse(n) != null) int.parse(n)];

  /// « Tu te mets combien ? » : le niveau qu'Aura propose ce soir, d'après
  /// les séances réussies et abandonnées (le joueur décide).
  int get niveauPropose => Niveau.propose(
        reussis: [for (final b in billets) if (b.niveau != null) b.niveau!],
        abandonnes: _abandons,
      );

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
      niveau: carte.niveau,
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
    int? niveau,
    int? dureeMinutes,
    bool aPlusieurs = false,
  }) async {
    _nouveauMois();
    // Une réussite efface les abandons : Aura repart de ce qui marche.
    if (niveau != null) await _prefs.remove('niveaux_abandonnes');
    final maintenant = DateTime.now();
    final ceMois = moisDe(date) == moisDe(maintenant);
    final joker = jokerBluff && ceMois;
    final rattrapage = carteRattrapage && ceMois;
    // Pouvoir armé « au billet » (R39) : il agit maintenant, la charge part
    // même si la condition n'est pas remplie.
    final pouvoir = pouvoirArme && Pouvoirs.moment(profil) == MomentPouvoir.billet;
    final bonusPouvoir = pouvoir
        ? Pouvoirs.bonus(
            profil,
            pronostic: pronostic,
            note: note,
            dureeMinutes: film?.dureeMinutes ?? dureeMinutes,
            aPlusieurs: aPlusieurs,
            derrierePop: position < positionDePop,
          )
        : 0;
    if (pouvoir) await _consommerPouvoir();
    final plafond = pouvoir ? Pouvoirs.plafond(profil, Niveau.plafond(niveau)) : Niveau.plafond(niveau);
    // Crasse « Pop-corn renversé » encaissée : une case de moins, une fois.
    final malus = ceMois ? (_prefs.getInt('malus_cases') ?? 0) : 0;
    if (malus > 0) await _prefs.remove('malus_cases');
    final bonus = (joker ? 1 : 0) + (rattrapage ? Fidelite.rattrapage : 0) + bonusPouvoir - malus;
    final deja = casesLe(date);
    final cases = ceMois ? Regles.casesAccordees(demandees: max(0, demandees + bonus), dejaGagneesAujourdhui: deja, plafond: plafond) : 0;
    // Le pouvoir n'a « agi » que s'il a vraiment fait passer une case de plus.
    final pouvoirAgi = pouvoir &&
        cases > (ceMois ? Regles.casesAccordees(demandees: max(0, demandees + bonus - bonusPouvoir), dejaGagneesAujourdhui: deja, plafond: Niveau.plafond(niveau)) : 0);
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
        niveau: niveau,
      ),
      ...billets,
    ]..sort((a, b) => b.date.compareTo(a.date));
    final pariGagne = Pop.parisPerdus(maintenant, billets) > pariAvant;
    if (cases > 0) pionVientDAvancer = true;
    position = (position + cases).clamp(1, Regles.taillePlateau);
    // Coup de théâtre : le pion s'arrête sur une case 4, 14 ou 24 pas encore jouée ce mois-ci.
    final mois = moisDe(maintenant);
    final coup = cases > 0 && CoupsDuSort.estCaseCoup(position) && !(_prefs.getStringList('coups_$mois') ?? const []).contains('$position');
    if (coup) await _prefs.setString('coup_en_attente', '$mois|$position');
    final nouveaux = await _majCollection();
    _direPop([
      if (pouvoir) Pouvoirs.phrase(profil, agi: pouvoirAgi),
      if (note != null) Pop.surPronostic(pronostic: pronostic, note: note, graine: billets.length),
      if (coup) 'Case Coup de théâtre ! Va voir le plateau.',
      if (malus > 0) 'Pop-corn renversé : une case de moins, merci qui ?',
      if (pariGagne) 'Zut, j\'ai perdu mon pari : je recule de ${Pop.recul} cases. Mais je reviendrai.',
      for (final id in nouveaux) 'Nouvel exploit pour ta collection : ${Collection.nomDe(id)} !',
    ]);
    await _prefs.setInt('position', position);
    await _sauverBillets();
    await _prefs.setInt('stat_billets', (_prefs.getInt('stat_billets') ?? 0) + 1);
    _mesurer('billet', {'auto': auto, 'cases': cases, 'type': type});
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
  Future<void> commencerSeance(CarteDefi carte, {required int pronostic, bool aPlusieurs = false}) async {
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
        niveau: carte.niveau,
        dureeMinutes: carte.film.dureeMinutes,
        aPlusieurs: aPlusieurs,
      ),
      ...enCours,
    ].take(5).toList();
    await _sauverEnCours();
    await _prefs.setInt('stat_cartes', (_prefs.getInt('stat_cartes') ?? 0) + 1);
    Rappels.alorsCeFilm(filmId: carte.film.id, titre: carte.film.titre, carteJouee: DateTime.now());
    _mesurer('carte_jouee', {'type': carte.type.libelle, 'source': carte.film.source.name});
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
      niveau: s.niveau,
      dureeMinutes: s.dureeMinutes,
      aPlusieurs: s.aPlusieurs,
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

  /// Abandonner un film. À 9 et 10, le pari est perdu : le pion recule.
  /// Renvoie le nombre de cases perdues.
  Future<int> abandonnerSeance(SeanceEnCours s) async {
    enCours = enCours.where((x) => x.filmId != s.filmId).toList();
    await _sauverEnCours();
    var perdues = 0;
    if (s.niveau != null) {
      await _prefs.setStringList('niveaux_abandonnes', ['${s.niveau}', ..._abandons.map((n) => '$n')].take(5).toList());
      perdues = min(Niveau.recul(s.niveau), position - 1);
      if (perdues > 0) {
        position -= perdues;
        await _prefs.setInt('position', position);
        _direPop(['Tu t\'étais mis ${s.niveau}, et tu lâches ? Pari perdu : tu recules de ${perdues == 1 ? 'une case' : '$perdues cases'}. Je n\'en attendais pas moins.']);
      }
    }
    notifyListeners();
    return perdues;
  }

  // Les pouvoirs des pions (R39).

  List<UsagePouvoir> get _usagesPouvoir => [
        for (final t in _prefs.getStringList('pouvoir_usages') ?? const <String>[])
          if (UsagePouvoir.depuisTexte(t) != null) UsagePouvoir.depuisTexte(t)!,
      ];

  /// Les charges de pouvoir qui restent : une par semaine, plus une par
  /// tranche de 20 points d'audace du mois.
  int get chargesPouvoir => Pouvoirs.charges(maintenant: DateTime.now(), usages: _usagesPouvoir, audaceDuMois: audaceDuMois);

  /// Vrai quand le pouvoir est armé : il agira au prochain tirage ou billet.
  bool get pouvoirArme => _prefs.getBool('pouvoir_arme') ?? false;

  /// Armer son pouvoir, s'il reste une charge. Renvoie vrai si c'est fait.
  Future<bool> armerPouvoir() async {
    if (pouvoirArme || chargesPouvoir <= 0) return false;
    await _prefs.setBool('pouvoir_arme', true);
    notifyListeners();
    return true;
  }

  /// Désarmer avant qu'il agisse : la charge n'est pas perdue.
  Future<void> desarmerPouvoir() async {
    await _prefs.setBool('pouvoir_arme', false);
    notifyListeners();
  }

  /// La charge part : celle de la semaine d'abord, sinon une charge d'audace.
  Future<void> _consommerPouvoir() async {
    await _depenserCharge();
    await _prefs.setBool('pouvoir_arme', false);
  }

  Future<void> _depenserCharge() async {
    final maintenant = DateTime.now();
    final usages = _usagesPouvoir;
    final audace = !Pouvoirs.chargeDeLaSemaine(maintenant: maintenant, usages: usages);
    final gardes = usages.where((u) => maintenant.difference(u.date).inDays < 62);
    await _prefs.setStringList('pouvoir_usages', [UsagePouvoir(maintenant, audace: audace).versTexte(), for (final u in gardes) u.versTexte()]);
  }

  /// Au tirage de Ce soir : si le pouvoir armé agit au tirage (Boussole,
  /// Madeleine), il est consommé et ses réglages sont renvoyés.
  Future<({int nombre, bool revoir})> pouvoirAuTirage() async {
    if (!pouvoirArme || Pouvoirs.moment(profil) != MomentPouvoir.tirage) return (nombre: 3, revoir: false);
    await _consommerPouvoir();
    _direPop([Pouvoirs.phrase(profil, agi: true)]);
    notifyListeners();
    return (nombre: Pouvoirs.cartesAuTirage(profil), revoir: Pouvoirs.revoir(profil));
  }

  /// L'audace du mois : la somme des points d'audace des billets du mois.
  int get audaceDuMois {
    final m = moisDe(DateTime.now());
    final total = billets.where((b) => b.niveau != null && moisDe(b.date) == m).fold(0, (s, b) => s + Niveau.audace(b.niveau!));
    return max(0, total + (_prefs.getInt('audace_$m') ?? 0));
  }

  // Coups du sort et crasses (R40).

  /// Le coup du sort qui attend une décision, s'il y en a un ce mois-ci.
  ({CoupDuSort coup, int numero})? get coupEnAttente {
    final t = (_prefs.getString('coup_en_attente') ?? '').split('|');
    if (t.length != 2 || t.first != moisDe(DateTime.now())) return null;
    final n = int.tryParse(t.last);
    if (n == null) return null;
    return (coup: CoupsDuSort.pour(DateTime.now(), n), numero: n);
  }

  /// Parer coûte une charge de pouvoir (sans toucher à celle déjà armée).
  bool get peutParerAvecCharge => chargesPouvoir > (pouvoirArme ? 1 : 0);

  /// Régler le coup du sort : l'encaisser, ou le parer avec une charge de
  /// pouvoir ou le Bouclier du mois. Renvoie faux si la parade est impossible.
  Future<bool> resoudreCoup({String? parade}) async {
    final c = coupEnAttente;
    if (c == null) return false;
    final pop = positionDePop;
    final tort = CoupsDuSort.faitDuTort(c.coup, joueur: position, pop: pop);
    if (parade != null) {
      if (!tort) return false;
      if (parade == 'charge' && peutParerAvecCharge) {
        await _depenserCharge();
      } else if (parade == 'bouclier' && bouclierDispo) {
        await poserBouclier();
      } else {
        return false;
      }
      _direPop(['Paré ! ${c.coup.nom} ne t\'a rien fait. Je note, je note.']);
    } else {
      final d = CoupsDuSort.deplacement(c.coup, joueur: position, pop: pop);
      position = (position + d.joueur).clamp(1, Regles.taillePlateau);
      await _prefs.setInt('position', position);
      final cle = 'pop_decalage_${moisDe(DateTime.now())}';
      if (d.pop != 0) await _prefs.setInt(cle, (_prefs.getInt(cle) ?? 0) + d.pop);
      _direPop(['${c.coup.nom} : ${c.coup.effet}']);
    }
    final mois = moisDe(DateTime.now());
    await _prefs.setStringList('coups_$mois', [...?_prefs.getStringList('coups_$mois'), '${c.numero}']);
    await _prefs.remove('coup_en_attente');
    notifyListeners();
    return true;
  }

  /// Crasse « Niveau imposé » : le niveau du prochain tirage, s'il y en a un.
  int? get niveauImpose => _prefs.getInt('niveau_impose');

  /// Le tirage a eu lieu : le niveau imposé est consommé.
  Future<void> oublierNiveauImpose() => _prefs.remove('niveau_impose');

  List<DateTime> _dates(String cle) => [for (final t in _prefs.getStringList(cle) ?? const <String>[]) if (DateTime.tryParse(t) != null) DateTime.parse(t)];

  /// Une crasse par semaine.
  bool get peutFaireUneCrasse => Crasses.peutEnvoyer(DateTime.now(), _dates('crasses_envoyees'));

  /// Un renvoi à l'expéditeur par mois.
  bool get peutRenvoyerUneCrasse => Crasses.peutRenvoyer(DateTime.now(), _dates('crasses_renvois'));

  Future<void> noterCrasseEnvoyee() async =>
      _prefs.setStringList('crasses_envoyees', [DateTime.now().toIso8601String(), ...?_prefs.getStringList('crasses_envoyees')].take(10).toList());

  /// Répondre à une crasse reçue. Encaissée : son effet s'applique ici.
  /// Parée : une charge de pouvoir. Renvoyée : une fois par mois. Renvoie
  /// faux si la parade demandée est impossible.
  Future<bool> repondreCrasse(Crasse c, Reponse r) async {
    switch (r) {
      case Reponse.paree:
        if (!peutParerAvecCharge) return false;
        await _depenserCharge();
        _direPop(['Crasse parée. Ton ami va être déçu, et moi aussi un peu.']);
      case Reponse.renvoyee:
        if (!peutRenvoyerUneCrasse) return false;
        await _prefs.setStringList('crasses_renvois', [DateTime.now().toIso8601String(), ...?_prefs.getStringList('crasses_renvois')].take(10).toList());
        _direPop(['Retour à l\'envoyeur ! J\'adore quand ça se retourne.']);
      case Reponse.encaissee:
        switch (c) {
          case Crasse.niveauImpose:
            await _prefs.setInt('niveau_impose', Crasses.niveauImpose);
          case Crasse.popcorn:
            await _prefs.setInt('malus_cases', 1);
          case Crasse.volDAudace:
            await _ajouterAudace(-Crasses.audaceVolee);
          case Crasse.fauxSpoiler:
            break;
        }
        _direPop(['${c.nom} : ${c.effet}']);
    }
    notifyListeners();
    return true;
  }

  Future<void> _ajouterAudace(int n) async {
    final cle = 'audace_${moisDe(DateTime.now())}';
    await _prefs.setInt(cle, (_prefs.getInt(cle) ?? 0) + n);
  }

  /// Côté expéditeur : un Vol d'audace encaissé par l'ami rapporte ses 5
  /// points, une seule fois par crasse.
  Future<int> encaisserGains(List<CrasseRecue> envoyees) async {
    final comptees = {...?_prefs.getStringList('crasses_comptees')};
    final m = moisDe(DateTime.now());
    var gagne = 0;
    for (final c in envoyees) {
      if (c.crasse == Crasse.volDAudace && c.reponse == Reponse.encaissee && moisDe(c.date) == m && comptees.add(c.id)) gagne += Crasses.audaceVolee;
    }
    if (gagne > 0) {
      await _ajouterAudace(gagne);
      await _prefs.setStringList('crasses_comptees', comptees.toList());
      notifyListeners();
    }
    return gagne;
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

  Future<void> _sauverEnCours() {
    if (enCours.isEmpty) Rappels.annuler();
    return _prefs.setStringList('en_cours', enCours.map((s) => jsonEncode(s.versJson())).toList());
  }

  /// Réponse à la notification du lendemain : une note valide la séance en
  /// un geste ; un simple toucher ouvre l'appli sur « Alors, ce film ? ».
  Future<int?> repondreRappel(String filmId, int? note) async {
    final s = enCours.where((x) => x.filmId == filmId).firstOrNull;
    if (s == null || note == null) return null;
    return validerEnCours(s, note: note);
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
    _mesurer('plan_du_jour', {'trouve': r.trouve, 'indices': r.indices});
    notifyListeners();
  }

  // Le Bluff de la semaine contre Pop : un seul essai par semaine.

  /// null si pas encore joué, sinon vrai si le vrai synopsis a été trouvé.
  bool? bluffDe(String semaine) => _prefs.getBool('bluff_$semaine');

  Future<void> jouerBluff(String semaine, {required bool trouve}) async {
    if (bluffDe(semaine) != null) return;
    await _prefs.setBool('bluff_$semaine', trouve);
    if (trouve) await _prefs.setBool('joker_bluff', true);
    _mesurer('bluff', {'trouve': trouve});
    await _majCollection();
    notifyListeners();
  }

  // La collection : exploits et figurines de saison, gardés pour toujours.

  Set<String> get collection => {...?_prefs.getStringList('collection')};

  int get bluffsGagnes => _prefs.getKeys().where((k) => k.startsWith('bluff_') && (_prefs.getBool(k) ?? false)).length;

  /// Ajoute un exploit gagné hors du plateau (campagne bouclée, cadeau
  /// réussi). Renvoie vrai s'il est nouveau.
  Future<bool> ajouterExploit(String id) async {
    final deja = collection;
    if (deja.contains(id)) return false;
    await _prefs.setStringList('collection', [...deja, id]);
    notifyListeners();
    return true;
  }

  /// Ajoute à la collection ce qui vient d'être mérité ; renvoie les nouveautés.
  Future<List<String>> _majCollection() async {
    final deja = collection;
    final merites = Collection.merites(Bilan(
      billets: billets,
      position: position,
      positionDePop: positionDePop,
      bluffsGagnes: bluffsGagnes,
      maintenant: DateTime.now(),
      boucliers: boucliers,
    ));
    final nouveaux = merites.difference(deja).toList();
    if (nouveaux.isNotEmpty) await _prefs.setStringList('collection', [...deja, ...nouveaux]);
    return nouveaux;
  }

  // La Révélation du dimanche : une fois par semaine.

  bool revelationFaite(String semaine) => _prefs.getBool('revelation_$semaine') ?? false;

  /// Termine la Révélation ; un Médium raté (écart d'au moins 3) donne un
  /// Joker. Renvoie vrai si le Joker est gagné.
  Future<bool> terminerRevelation(String semaine, {required int pari, required int curseur}) async {
    if (revelationFaite(semaine)) return false;
    await _prefs.setBool('revelation_$semaine', true);
    final joker = Affiche.mediumRate(pari, curseur);
    if (joker) await _prefs.setBool('joker_bluff', true);
    notifyListeners();
    return joker;
  }

  // L'Affiche de la semaine : le Curseur placé après la séance.

  int? curseurDe(String semaine) => _prefs.getInt('curseur_$semaine');

  Future<void> placerCurseur(String semaine, int valeur) async {
    await _prefs.setInt('curseur_$semaine', valeur);
    notifyListeners();
  }
}
