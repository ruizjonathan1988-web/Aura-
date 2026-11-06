import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/modeles.dart';
import 'affiche.dart';
import 'apres_seance.dart';
import 'avis_du_jeu.dart';
import 'carte_genres.dart';
import 'collection.dart';
import 'config.dart';
import 'deblocage.dart';
import 'coups.dart';
import 'fidelite.dart';
import 'historique.dart';
import 'ligues.dart';
import 'ma_tv.dart';
import 'mesures.dart';
import 'niveau.dart';
import 'plan_du_jour.dart';
import 'pont_vjod.dart';
import 'pop.dart';
import 'pouvoirs.dart';
import 'rappels.dart';
import 'retournements.dart';
import 'rivaux.dart';
import 'source_tmdb.dart';
import 'sources.dart';
import 'deck.dart';
import 'festival.dart';
import 'casse.dart';
import 'relais.dart' show Relais;
import 'partage.dart';
import 'sons.dart';
import 'veille.dart';
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
    Sons.actifs = _prefs.getBool('sons') ?? true;
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
      defi: carte.defi,
    );
  }

  Future<int> _ajouterBillet({
    String defi = '',
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
    final popAvant = positionDePop;
    final pp = profilDuPouvoir;
    final pouvoir = pp != null && pouvoirArme && Pouvoirs.moment(pp) == MomentPouvoir.billet;
    final bonusPouvoir = pouvoir
        ? Pouvoirs.bonus(
            pp,
            pronostic: pronostic,
            note: note,
            dureeMinutes: film?.dureeMinutes ?? dureeMinutes,
            aPlusieurs: aPlusieurs,
            derrierePop: position < popAvant,
          )
        : 0;
    if (pouvoir) await _consommerPouvoir();
    final plafond = pouvoir ? Pouvoirs.plafond(pp, Niveau.plafond(niveau)) : Niveau.plafond(niveau);
    // Crasse « Pop-corn renversé » encaissée : une case de moins, une fois.
    final malus = ceMois ? (_prefs.getInt('malus_cases') ?? 0) : 0;
    if (malus > 0) await _prefs.remove('malus_cases');
    // Le Deck d'atouts (R49) : les atouts posés dont le défi est rempli.
    final contexte = ContexteAtout(
      billet: Billet(
        titre: titre,
        type: type,
        pronostic: pronostic,
        cases: 0,
        date: date,
        note: note,
        genres: film?.genres ?? genres,
        annee: film?.annee ?? annee,
        pays: film?.pays ?? pays,
        niveau: niveau,
      ),
      avant: billets,
      dureeMinutes: film?.dureeMinutes ?? dureeMinutes,
    );
    final effetDeck = ceMois ? Deck.effets(deck, atouts, contexte) : (cases: 0, audace: 0, declenches: const <Atout>[]);
    // Le Festival de la semaine (R50).
    final festival = festivalDe(date);
    final enFete = ceMois && festival != null && festival.condition(contexte);
    final caseFestival = enFete && festival.effet == EffetFestival.caseEnPlus ? 1 : 0;
    final audaceDeck = enFete && festival.effet == EffetFestival.audaceDouble ? effetDeck.audace * 2 : effetDeck.audace;
    final bonus = (joker ? 1 : 0) + (rattrapage ? Fidelite.rattrapage : 0) + bonusPouvoir + effetDeck.cases + caseFestival - malus;
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
    // Défi d'après-séance (R44) : trois questions sur ce film, à la prochaine ouverture de Ce soir.
    final nouveau = billets.firstWhere((b) => b.date == date && b.titre == titre);
    if (ceMois && ouvert(Etape.niveaux) && (nouveau.annee != null || nouveau.pays.isNotEmpty || nouveau.genres.isNotEmpty)) {
      await _prefs.setString('defi_apres', jsonEncode(nouveau.versJson()));
    }
    // Vent dans le dos (R41) : une séance vue derrière Pop rapporte de l'audace.
    final vent = ceMois && ouvert(Etape.niveaux) && position < popAvant;
    if (vent) await _ajouterAudace(Retournements.ventDansLeDos);
    if (audaceDeck > 0) await _ajouterAudace(audaceDeck);
    // Le Casse (R56) : les serrures que ce film ouvre.
    if (ceMois && Casse.enCours(date)) {
      final serrures = Casse.serrures(date);
      final ok = casseOuvertes(date);
      for (var i = 0; i < serrures.length; i++) {
        if (serrures[i].condition(contexte)) ok.add(i);
      }
      await _prefs.setStringList('casse_ok_${Casse.mois(date)}', [for (final i in ok) '$i']);
    }
    // Le Défi de la semaine (R52) : une fois par semaine, 3 d'audace et un booster.
    final defiSemaine = defiSemaineDe(date);
    final defiReussi = ceMois && defiSemaine != null && !defiSemaineReussi(date) && defiSemaine.condition(contexte);
    if (defiReussi) {
      await _prefs.setBool('defi_fait_${DefisSemaine.cle(date)}', true);
      await _ajouterAudace(DefisSemaine.audace);
      await _prefs.setInt('booster_reserve', min(boostersDispo(maintenant) + 1, Deck.reserveMax));
      await _prefs.setString('booster_don', jourDe(maintenant));
    }
    final popRecule = enFete && festival.effet == EffetFestival.popRecule;
    if (popRecule) {
      final m = moisDe(maintenant);
      await _prefs.setInt('pop_decalage_$m', _decalageDePop(m) - 1);
    }
    final boosterFestival = enFete && festival.effet == EffetFestival.booster;
    if (boosterFestival) {
      await _prefs.setInt('booster_reserve', min(boostersDispo(maintenant) + 1, Deck.reserveMax));
      await _prefs.setString('booster_don', jourDe(maintenant));
    }
    if (cases > 0) pionVientDAvancer = true;
    position = (position + cases).clamp(1, Regles.taillePlateau);
    // Coup de théâtre : le pion s'arrête sur une case 4, 14 ou 24 pas encore jouée ce mois-ci.
    final mois = moisDe(maintenant);
    final coup = ouvert(Etape.coups) && cases > 0 && CoupsDuSort.estCaseCoup(position) && !(_prefs.getStringList('coups_$mois') ?? const []).contains('$position');
    if (coup) await _prefs.setString('coup_en_attente', '$mois|$position');
    await _noter([
      '« $titre » : ${cases == 0 ? 'aucune case (plafond du jour)' : '+$cases case${cases > 1 ? 's' : ''}'}, case $position.',
      if (pouvoirAgi) 'Pouvoir ${pp.pouvoir} : il a fait passer une case de plus.',
      if (pouvoir && !pouvoirAgi) 'Pouvoir ${pp.pouvoir} : chou blanc, charge utilisée.',
      if (malus > 0) 'Pop-corn renversé : une case de moins.',
      if (effetDeck.declenches.isNotEmpty)
        'Atouts : ${effetDeck.declenches.map((a) => a.nom).join(', ')}${effetDeck.cases > 0 ? ' (+1 case)' : ''}${audaceDeck > 0 ? ', +$audaceDeck d\'audace' : ''}.',
      if (enFete) '${festival.nom} : ${festival.regle}',
      if (defiReussi) 'Défi de la semaine réussi : +${DefisSemaine.audace} d\'audace et un booster.',
      if (vent) 'Vent dans le dos : +${Retournements.ventDansLeDos} points d\'audace (tu étais derrière Pop).',
      if (pariGagne) 'Pari de Pop relevé : il recule de ${Pop.recul} cases.',
      if (coup) 'Case $position : Coup de théâtre !',
    ]);
    final nouveaux = await _majCollection();
    _direPop([
      if (pouvoir) Pouvoirs.phrase(pp, agi: pouvoirAgi),
      if (note != null) Pop.surPronostic(pronostic: pronostic, note: note, graine: billets.length),
      if (effetDeck.declenches.isNotEmpty) Deck.phraseDePop(effetDeck.declenches, graine: billets.length),
      if (popRecule) '${festival.nom} : je recule d\'une case. Je l\'avais bien cherché.',
      if (coup) 'Case Coup de théâtre ! Va voir le plateau.',
      if (malus > 0) 'Pop-corn renversé : une case de moins, merci qui ?',
      if (vent) 'Tu étais derrière moi : ${Retournements.ventDansLeDos} points d\'audace pour toi. Profites-en, ça ne durera pas.',
      if (pariGagne) 'Zut, j\'ai perdu mon pari : je recule de ${Pop.recul} cases. Mais je reviendrai.',
      for (final id in nouveaux) 'Nouvel exploit pour ta collection : ${Collection.nomDe(id)} !',
    ]);
    await _prefs.setInt('position', position);
    await _prefs.setString(
      'derniere_soiree',
      jsonEncode(SoireePartagee(
        date: date,
        defi: defi.isNotEmpty ? defi : type,
        pronostic: pronostic,
        note: note,
        cases: cases,
        position: position,
        pop: positionDePop,
        atouts: [for (final a in effetDeck.declenches) a.nom],
        defiSemaine: defiReussi || defiSemaineReussi(date),
        festival: enFete ? festival.nom : null,
      ).versJson()),
    );
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
  Future<void> commencerSeance(CarteDefi carte, {required int pronostic, bool aPlusieurs = false, DateTime? debut}) async {
    if (enCours.any((s) => s.filmId == carte.film.id)) return;
    enCours = [
      SeanceEnCours(
        titre: carte.film.titre,
        filmId: carte.film.id,
        jellyfin: carte.film.source == SourceFilm.jellyfin,
        type: carte.type.libelle,
        cases: carte.cases,
        pronostic: pronostic,
        debut: debut ?? DateTime.now(),
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
    Rappels.alorsCeFilm(filmId: carte.film.id, titre: carte.film.titre, carteJouee: DateTime.now(), insolent: popInsolent);
    planifierAvis();
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
    }
    if (sisypheActif) {
      // Le pari de Sisyphe est perdu : retour à la case 1.
      perdues = position - 1;
      await _prefs.setString('sisyphe_${moisDe(DateTime.now())}', 'perdu');
      position = 1;
      await _prefs.setInt('position', position);
      _direPop(['Sisyphe ! Le rocher redescend : retour à la case 1. Je t\'avais prévenu, non ?']);
      await _noter(['Film abandonné avec le pari de Sisyphe : retour à la case 1.']);
    } else if (s.niveau != null) {
      if (perdues > 0) {
        position -= perdues;
        await _prefs.setInt('position', position);
        _direPop(['Tu t\'étais mis ${s.niveau}, et tu lâches ? Pari perdu : tu recules de ${perdues == 1 ? 'une case' : '$perdues cases'}. Je n\'en attendais pas moins.']);
        await _noter(['« ${s.titre} » abandonné au niveau ${s.niveau} : −$perdues case${perdues > 1 ? 's' : ''}.']);
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
    if (profilDuPouvoir == null || pouvoirArme || chargesPouvoir <= 0) return false;
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
    final pp = profilDuPouvoir;
    if (pp == null || !pouvoirArme || Pouvoirs.moment(pp) != MomentPouvoir.tirage) return (nombre: 3, revoir: false);
    await _consommerPouvoir();
    _direPop([Pouvoirs.phrase(pp, agi: true)]);
    notifyListeners();
    return (nombre: Pouvoirs.cartesAuTirage(pp), revoir: Pouvoirs.revoir(pp));
  }

  /// L'audace du mois : la somme des points d'audace des billets du mois.
  int get audaceDuMois {
    final m = moisDe(DateTime.now());
    final total = billets.where((b) => b.niveau != null && moisDe(b.date) == m).fold(0, (s, b) => s + Niveau.audace(b.niveau!));
    return max(0, total + (_prefs.getInt('audace_$m') ?? 0));
  }

  // Déblocage progressif (R42).

  /// « Je connais déjà le jeu » : tout est ouvert d'emblée (Réglages).
  bool get toutOuvert => _prefs.getBool('tout_ouvert') ?? false;

  Future<void> changerToutOuvert(bool v) async {
    await _prefs.setBool('tout_ouvert', v);
    notifyListeners();
  }

  bool ouvert(Etape e) => Deblocage.ouvert(e, seances: billets.length, toutOuvert: toutOuvert);

  /// La nouveauté que Pop doit présenter, s'il y en a une.
  Etape? get nouveaute => Deblocage.aAnnoncer(seances: billets.length, annoncees: {...?_prefs.getStringList('etapes_annoncees')}, toutOuvert: toutOuvert);

  Future<void> nouveauteVue(Etape e) async {
    await _prefs.setStringList('etapes_annoncees', {...?_prefs.getStringList('etapes_annoncees'), e.name}.toList());
    notifyListeners();
  }

  /// La situation du soir, pour la carte « Ce soir pour toi ».
  Situation get situation => Situation(
        seances: billets.length,
        position: position,
        pop: positionDePop,
        casesRestantes: Regles.casesParJourMax - casesLe(DateTime.now()),
        toutOuvert: toutOuvert,
        coupEnAttente: coupEnAttente?.numero,
        pouvoirCharge: profilDuPouvoir != null && chargesPouvoir > 0,
        pouvoirArme: pouvoirArme,
        nomPouvoir: profilDuPouvoir?.pouvoir ?? '',
        niveauImpose: niveauImpose,
        sisyphe: sisypheActif,
      );

  /// Les nouvelles des amis (R54), par défaut oui.
  bool get avisAmis => _prefs.getBool(Veille.cleActive) ?? true;

  Future<void> changerAvisAmis(bool v) async {
    await _prefs.setBool(Veille.cleActive, v);
    notifyListeners();
  }

  // Le ton de Pop et les sons.

  /// Pop insolent (par défaut) ou gentil.
  bool get popInsolent => _prefs.getString('pop_ton') != 'gentil';

  Future<void> changerTonDePop(bool insolent) async {
    await _prefs.setString('pop_ton', insolent ? 'insolent' : 'gentil');
    notifyListeners();
  }

  bool get sonsActifs => _prefs.getBool('sons') ?? true;

  Future<void> changerSons(bool v) async {
    await _prefs.setBool('sons', v);
    Sons.actifs = v;
    notifyListeners();
  }

  // Notifications de jeu (R45).

  /// Les notifications de jeu sont actives (Réglages), par défaut oui.
  bool get avisActifs => _prefs.getBool('avis_jeu') ?? true;

  Future<void> changerAvis(bool v) async {
    await _prefs.setBool('avis_jeu', v);
    await planifierAvis();
    notifyListeners();
  }

  /// Les avis des sept prochains jours, jamais le jour du rappel « Alors, ce film ? ».
  List<AvisPrevu> get avisPrevus => AvisDuJeu.prevus(
        maintenant: DateTime.now(),
        pouvoirs: ouvert(Etape.pouvoirs),
        crasses: ouvert(Etape.crasses),
        rappelAlorsCeFilm: enCours.isEmpty ? null : Rappels.moment(enCours.first.debut),
        actifs: avisActifs,
      );

  Future<void> planifierAvis() => Rappels.planifierAvis(avisPrevus);

  // Défi d'après-séance et Pop-cartes (R44).

  /// Le billet dont le défi d'après-séance attend, s'il y en a un.
  Billet? get defiApres {
    final t = _prefs.getString('defi_apres');
    if (t == null) return null;
    try {
      return Billet.depuisJson(jsonDecode(t) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Le défi est joué : l'audace gagnée, et la Pop-carte brille si sans-faute.
  Future<int> repondreDefiApres({required int justes, required int total}) async {
    final b = defiApres;
    if (b == null) return 0;
    await _prefs.remove('defi_apres');
    final gagne = DefiApres.audace(justes, total);
    if (gagne > 0) await _ajouterAudace(gagne);
    if (total > 0 && justes == total) {
      await _prefs.setStringList('cartes_brillantes', {...?_prefs.getStringList('cartes_brillantes'), b.date.toIso8601String()}.take(200).toList());
    }
    _direPop([
      total > 0 && justes == total
          ? 'Sans-faute sur « ${b.titre} » ! Ta Pop-carte brille. +$gagne points d\'audace.'
          : '$justes sur $total. +$gagne point${gagne > 1 ? 's' : ''} d\'audace. Tu regardais ton téléphone, avoue.',
    ]);
    await _noter(['Défi d\'après-séance « ${b.titre} » : $justes sur $total, +$gagne d\'audace.']);
    notifyListeners();
    return gagne;
  }

  Future<void> passerDefiApres() async {
    await _prefs.remove('defi_apres');
    notifyListeners();
  }

  /// Vrai si la Pop-carte de ce billet brille (défi d'après-séance sans faute).
  bool brillante(Billet b) => (_prefs.getStringList('cartes_brillantes') ?? const []).contains(b.date.toIso8601String());

  /// L'album du mois : une Pop-carte par billet, la plus ancienne d'abord.
  List<Billet> get albumDuMois => billets.where((b) => moisDe(b.date) == moisDe(DateTime.now())).toList().reversed.toList();

  // Rivaux robots et figurine du mois (R43).

  /// La figurine du mois : ton pouvoir, l'œuf mystère ou le Figurant.
  FigurineDuMois get figurineDuMois => FigurineDuMois.depuisNom(_prefs.getString('figurine_${moisDe(DateTime.now())}'));

  /// Le choix se fait la première semaine du mois, une fois, pouvoirs ouverts.
  bool get figurineAChoisir =>
      ouvert(Etape.pouvoirs) && _prefs.getString('figurine_${moisDe(DateTime.now())}') == null && DateTime.now().day <= Retournements.joursSisyphe;

  Future<void> choisirFigurine(FigurineDuMois f) async {
    if (!figurineAChoisir) return;
    await _prefs.setString('figurine_${moisDe(DateTime.now())}', f.name);
    if (f != FigurineDuMois.pouvoir) await _prefs.setBool('pouvoir_arme', false);
    _direPop([switch (f) {
      FigurineDuMois.pouvoir => 'Classique. Je respecte.',
      FigurineDuMois.oeuf => 'Un œuf ! Je me demande ce qui va en sortir. Moi, je parie sur un poulet.',
      FigurineDuMois.figurant => 'Le Figurant : tu ne fais rien, mais tu es partout. Comme moi au cinéma.',
    }]);
    await _noter(['Figurine du mois : ${f.nom}.']);
    notifyListeners();
  }

  int get _seancesDuMois => billets.where((b) => moisDe(b.date) == moisDe(DateTime.now())).length;

  /// Vrai quand l'œuf a éclos (3 séances ce mois-ci).
  bool get oeufEclos => figurineDuMois == FigurineDuMois.oeuf && _seancesDuMois >= Oeuf.seancesPourEclore;

  /// Le profil dont on utilise le pouvoir ce mois-ci, ou null s'il n'y en a pas
  /// (pouvoirs pas encore ouverts, œuf pas éclos, Figurant).
  Profil? get profilDuPouvoir {
    if (!ouvert(Etape.pouvoirs)) return null;
    return switch (figurineDuMois) {
      FigurineDuMois.pouvoir => profil,
      FigurineDuMois.oeuf => oeufEclos ? Oeuf.eclosion(profil, DateTime.now()) : null,
      FigurineDuMois.figurant => null,
    };
  }

  /// Le Figurant avance d'une case quand quelque chose arrive, une fois par jour.
  Future<void> _figurant(String quoi) async {
    if (!ouvert(Etape.pouvoirs) || figurineDuMois != FigurineDuMois.figurant) return;
    final cle = 'figurant_${jourDe(DateTime.now())}';
    if (_prefs.getBool(cle) ?? false) return;
    await _prefs.setBool(cle, true);
    position = min(Regles.taillePlateau, position + 1);
    await _prefs.setInt('position', position);
    await _noter(['Le Figurant était dans le champ ($quoi) : +1 case.']);
  }

  /// La case d'un rival, retours de crasse compris.
  int positionDe(Rival r) =>
      (Rivaux.position(r, DateTime.now()) - (_prefs.getInt('rival_${r.name}_${moisDe(DateTime.now())}') ?? 0)).clamp(1, Regles.taillePlateau);

  /// La crasse d'un rival cette semaine, si elle attend une réponse.
  ({Rival rival, Crasse crasse})? get crasseDesRivaux {
    if (!ouvert(Etape.crasses)) return null;
    final c = Rivaux.crasseDeLaSemaine(DateTime.now());
    if (c == null) return null;
    final lundi = Pop.lundiDe(DateTime.now());
    if (_prefs.getBool('crasse_rival_${jourDe(lundi)}') ?? false) return null;
    return c;
  }

  /// Répondre à la crasse d'un rival : comme pour un ami, et un renvoi le fait reculer.
  Future<bool> repondreAuRival(Reponse r) async {
    final c = crasseDesRivaux;
    if (c == null) return false;
    if (!await repondreCrasse(c.crasse, r)) return false;
    if (r == Reponse.renvoyee) {
      final cle = 'rival_${c.rival.name}_${moisDe(DateTime.now())}';
      await _prefs.setInt(cle, (_prefs.getInt(cle) ?? 0) + Rivaux.reculRenvoi);
      await _noter(['${c.rival.nom} recule de ${Rivaux.reculRenvoi} cases : bien fait.']);
    }
    await _prefs.setBool('crasse_rival_${jourDe(Pop.lundiDe(DateTime.now()))}', true);
    notifyListeners();
    return true;
  }

  // Retournements (R41) : journal du plateau, Volte-face, pari de Sisyphe.

  /// Le journal du plateau : ce qui est arrivé ce mois-ci, le plus récent d'abord.
  List<String> get journal => _prefs.getStringList('journal_${moisDe(DateTime.now())}') ?? const [];

  Future<void> _noter(List<String> lignes) async {
    if (lignes.isEmpty) return;
    final cle = 'journal_${moisDe(DateTime.now())}';
    await _prefs.setStringList(cle, [...lignes, ...?_prefs.getStringList(cle)].take(Retournements.tailleJournal).toList());
  }

  /// Volte-face : un Joker par mois, seulement quand on est derrière Pop.
  bool get volteFaceDispo => ouvert(Etape.coups) && !(_prefs.getBool('volte_face_${moisDe(DateTime.now())}') ?? false) && position < positionDePop;

  /// Prendre la place de Pop, et lui donner la sienne. Renvoie faux si impossible.
  Future<bool> volteFace() async {
    if (!volteFaceDispo) return false;
    final mois = moisDe(DateTime.now());
    final pop = positionDePop;
    final d = CoupsDuSort.deplacement(CoupDuSort.echange, joueur: position, pop: pop);
    position += d.joueur;
    await _prefs.setInt('position', position);
    await _prefs.setInt('pop_decalage_$mois', _decalageDePop(mois) + d.pop);
    await _prefs.setBool('volte_face_$mois', true);
    pionVientDAvancer = true;
    _direPop(['Volte-face ! Tu me piques ma place ? C\'est petit. C\'est très petit. Bravo.']);
    await _noter(['Volte-face : tu passes case $position, Pop recule case ${position - d.joueur}.']);
    notifyListeners();
    return true;
  }

  String? get _sisyphe => _prefs.getString('sisyphe_${moisDe(DateTime.now())}');

  /// Le pari de Sisyphe se propose pendant la première semaine du mois, une fois.
  bool get sisypheProposable => ouvert(Etape.coups) && _sisyphe == null && DateTime.now().day <= Retournements.joursSisyphe;

  /// Vrai tant que le pari tient : un film abandonné renvoie à la case 1.
  bool get sisypheActif => _sisyphe == 'actif';

  Future<bool> accepterSisyphe() async {
    if (!sisypheProposable) return false;
    await _prefs.setString('sisyphe_${moisDe(DateTime.now())}', 'actif');
    position = min(Regles.taillePlateau, position + Retournements.avanceSisyphe);
    await _prefs.setInt('position', position);
    pionVientDAvancer = true;
    _direPop(['Pari de Sisyphe accepté : ${Retournements.avanceSisyphe} cases d\'avance. Abandonne un seul film ce mois-ci et tu repars de la case 1.']);
    await _noter(['Pari de Sisyphe : +${Retournements.avanceSisyphe} cases. Un film abandonné ce mois-ci = retour case 1.']);
    notifyListeners();
    return true;
  }

  /// Refuser le pari : il ne se repropose pas ce mois-ci.
  Future<void> refuserSisyphe() async {
    if (!sisypheProposable) return;
    await _prefs.setString('sisyphe_${moisDe(DateTime.now())}', 'refuse');
    notifyListeners();
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
      await _noter(['Case ${c.numero}, ${c.coup.nom} : paré ${parade == 'charge' ? 'avec une charge de pouvoir' : 'avec le Bouclier'}.']);
    } else {
      final d = CoupsDuSort.deplacement(c.coup, joueur: position, pop: pop);
      position = (position + d.joueur).clamp(1, Regles.taillePlateau);
      await _prefs.setInt('position', position);
      final cle = 'pop_decalage_${moisDe(DateTime.now())}';
      if (d.pop != 0) await _prefs.setInt(cle, (_prefs.getInt(cle) ?? 0) + d.pop);
      _direPop(['${c.coup.nom} : ${c.coup.effet}']);
      await _noter(['Case ${c.numero}, ${c.coup.nom} : ${c.coup.effet}']);
    }
    final mois = moisDe(DateTime.now());
    await _prefs.setStringList('coups_$mois', [...?_prefs.getStringList('coups_$mois'), '${c.numero}']);
    await _prefs.remove('coup_en_attente');
    await _figurant('un coup de théâtre');
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

  Future<void> noterCrasseEnvoyee() async {
    await _prefs.setStringList('crasses_envoyees', [DateTime.now().toIso8601String(), ...?_prefs.getStringList('crasses_envoyees')].take(10).toList());
    await _figurant('ta crasse');
  }

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
    await _noter([
      switch (r) {
        Reponse.encaissee => 'Crasse encaissée, ${c.nom} : ${c.effet}',
        Reponse.paree => 'Crasse parée (${c.nom}) avec une charge de pouvoir.',
        Reponse.renvoyee => 'Crasse renvoyée à l\'envoyeur (${c.nom}).',
      }
    ]);
    await _figurant('une crasse');
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
    await synchroniserVjod();
    return crees;
  }

  // Le pont avec VJOD (R46).

  /// Les cartes publiées pour VJOD, par soir (« 2026-11-06 » → 3 cartes en JSON).
  Map<String, List<Map<String, dynamic>>> get cartesPourVjod {
    try {
      final j = jsonDecode(_prefs.getString('pont_cartes') ?? '{}') as Map<String, dynamic>;
      return {for (final e in j.entries) e.key: [for (final c in e.value as List) Map<String, dynamic>.from(c as Map)]};
    } catch (_) {
      return {};
    }
  }

  /// Tire les cartes des soirs qui n'en ont pas encore (7 soirs d'avance),
  /// et oublie les soirs passés. [catalogue] donne les films d'une envie.
  Future<void> preparerCartesVjod(Future<List<Film>> Function(Emotion) catalogue, {DateTime? maintenant}) async {
    final m = maintenant ?? DateTime.now();
    final aujourdhui = DateTime(m.year, m.month, m.day);
    final cartes = {...cartesPourVjod}..removeWhere((jour, _) => jour.compareTo(PontVjod.jourDe(aujourdhui)) < 0);
    final films = <Emotion, List<Film>>{};
    final paysVus = {for (final b in billets) ...b.pays};
    for (var i = 0; i < PontVjod.jours; i++) {
      final jour = aujourdhui.add(Duration(days: i));
      final cle = PontVjod.jourDe(jour);
      if (cartes.containsKey(cle)) continue;
      final envie = PontVjod.envieDuJour(jour);
      final liste = films[envie] ??= await catalogue(envie);
      final tirage = Tirage(hasard: Random(PontVjod.graineDuJour(jour))).tirerSansImpasse(
        catalogue: liste,
        emotion: envie,
        duree: Duree.soiree,
        profil: profil,
        paysVus: paysVus,
        niveau: ouvert(Etape.niveaux) ? niveauPropose : null,
      );
      cartes[cle] = [for (final c in tirage.cartes) PontVjod.carteVersJson(c)];
    }
    await _prefs.setString('pont_cartes', jsonEncode(cartes));
  }

  /// Ce que VJOD a écrit : une carte jouée devient une séance en cours (depuis
  /// l'heure où elle a été jouée), une note de fin de film valide la séance.
  /// Renvoie vrai si quelque chose a changé.
  Future<bool> appliquerDepuisVjod({String? joue, String? note}) async {
    var change = false;
    final j = PontVjod.lireJoue(joue);
    if (j != null) {
      final liste = cartesPourVjod[j.jour] ?? const [];
      final carte = j.index >= 0 && j.index < liste.length ? PontVjod.carteDepuisJson(liste[j.index]) : null;
      if (carte != null && !enCours.any((s) => s.filmId == carte.film.id)) {
        await commencerSeance(carte, pronostic: 3, debut: j.quand);
        await _noter(['Carte jouée depuis VJOD : « ${carte.film.titre} ».']);
        change = true;
      }
    }
    final n = PontVjod.lireNote(note);
    if (n != null) {
      final s = enCours.where((x) => x.filmId == n.filmId).firstOrNull;
      if (s != null) {
        await validerEnCours(s, note: n.note, vuLe: n.quand);
        change = true;
      }
    }
    return change;
  }

  /// L'état publié pour VJOD.
  Map<String, dynamic> get etatPourVjod {
    final s = enCours.firstOrNull;
    return PontVjod.etat(
      maj: DateTime.now(),
      position: position,
      pop: positionDePop,
      niveau: ouvert(Etape.niveaux) ? niveauPropose : null,
      pouvoir: profilDuPouvoir?.pouvoir,
      charge: profilDuPouvoir != null && chargesPouvoir > 0,
      cartes: cartesPourVjod,
      seance: s == null ? null : (filmId: s.filmId, titre: s.titre, cases: s.cases),
    );
  }

  bool _pont = false;

  /// À chaque ouverture : lit ce que VJOD a écrit, l'applique, prépare les
  /// cartes et publie l'état. En édition VJOD seulement ; sans serveur, rien.
  Future<void> synchroniserVjod({ServicePontVjod? service, Future<List<Film>> Function(Emotion)? catalogue}) async {
    if (mode != ModeJeu.vjod || !connexion.complete || _pont) return;
    _pont = true;
    try {
      final pont = service ?? ServicePontVjod(connexion);
      final tout = await pont.lire();
      final prefs = ServicePontVjod.prefsDe(tout);
      await appliquerDepuisVjod(joue: prefs[PontVjod.cleJoue], note: prefs[PontVjod.cleNote]);
      final src = source;
      await preparerCartesVjod(catalogue ?? (e) => src.catalogue(emotion: e, duree: Duree.soiree));
      await pont.ecrire(tout, {
        ...prefs..remove(PontVjod.cleJoue)..remove(PontVjod.cleNote),
        PontVjod.cleEtat: jsonEncode(etatPourVjod),
      });
    } catch (_) {
      // Serveur injoignable : on réessaiera à la prochaine ouverture.
    } finally {
      _pont = false;
    }
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

  // Le Casse de la Cinémathèque (R56).

  /// Les serrures du mois que mes films ont ouvertes (toutes, pas seulement les miennes).
  Set<int> casseOuvertes(DateTime d) => {for (final x in _prefs.getStringList('casse_ok_${Casse.mois(d)}') ?? const <String>[]) int.parse(x)};

  /// Pour la Taupe : ouvrir sa serrure pour de vrai (sinon, pour de faux).
  bool casseVraie(DateTime d) => _prefs.getBool('casse_vraie_${Casse.mois(d)}') ?? false;

  Future<void> changerCasseVraie(DateTime d, bool v) async {
    await _prefs.setBool('casse_vraie_${Casse.mois(d)}', v);
    notifyListeners();
  }

  /// En solo : l'équipe, c'est toi (le Perceur) et les rivaux robots.
  Map<String, Role> get rolesSolo => Casse.roles(['moi', ...Casse.robots], Casse.graine(DateTime.now()), forcePerceur: 'moi');

  String? casseAccuse(DateTime d) => _prefs.getString('casse_accuse_${Casse.mois(d)}');

  Future<void> accuserEnSolo(DateTime d, String robot) async {
    await _prefs.setString('casse_accuse_${Casse.mois(d)}', robot);
    notifyListeners();
  }

  /// Les serrures ouvertes en solo : les miennes si un film les a ouvertes,
  /// celles des robots à leur jour (pour de faux si c'est la Taupe).
  Map<int, bool> ouverturesSolo(DateTime d) {
    final roles = Casse.roles(['moi', ...Casse.robots], Casse.graine(d), forcePerceur: 'moi');
    final mes = casseOuvertes(d);
    final out = <int, bool>{};
    for (final e in roles.entries) {
      for (final s in e.value.serrures) {
        if (e.key == 'moi') {
          if (mes.contains(s)) out[s] = true;
        } else if (Casse.jourDuCasse(d) >= Casse.jourDuRobot(e.key, d)) {
          out[s] = !e.value.taupe;
        }
      }
    }
    return out;
  }

  /// Le résultat déjà révélé ce mois-ci, ou nul.
  ({bool reussi, bool taupeDemasquee})? casseRevele(DateTime d) {
    final r = _prefs.getString('casse_fini_${Casse.mois(d)}');
    if (r == null) return null;
    final p = r.split('|');
    return (reussi: p[0] == '1', taupeDemasquee: p.length > 1 && p[1] == '1');
  }

  /// La révélation : récompenses une seule fois par mois. [jeSuisLaTaupe]
  /// gagne si le Casse rate.
  Future<void> terminerCasse(DateTime d, {required bool reussi, required bool taupeDemasquee, bool jeSuisLaTaupe = false}) async {
    final cle = 'casse_fini_${Casse.mois(d)}';
    if (_prefs.getString(cle) != null) return;
    await _prefs.setString(cle, '${reussi ? 1 : 0}|${taupeDemasquee ? 1 : 0}');
    if (jeSuisLaTaupe) {
      if (!reussi) await _ajouterAudace(Casse.audaceTaupe);
    } else if (reussi) {
      await _ajouterAudace(Casse.audaceReussite);
      final m = moisDe(d);
      await _prefs.setInt('pop_decalage_$m', _decalageDePop(m) - Casse.recul);
      await ajouterExploit('casse');
    }
    notifyListeners();
  }

  /// Le Défi de la semaine (R52). « defi_semaine » le force (« aucun » le
  /// coupe), pour les tests.
  DefiSemaine? defiSemaineDe(DateTime d) {
    final force = _prefs.getString('defi_semaine');
    if (force == 'aucun') return null;
    if (force != null) return DefisSemaine.parId(force);
    // La dernière semaine du mois, place au Casse (R56).
    if (Casse.enCours(d)) return null;
    return DefisSemaine.de(d);
  }

  bool defiSemaineReussi(DateTime d) => _prefs.getBool('defi_fait_${DefisSemaine.cle(d)}') ?? false;

  /// La dernière soirée, pour la partager sans dire le titre.
  SoireePartagee? get derniereSoiree {
    final brut = _prefs.getString('derniere_soiree');
    if (brut == null) return null;
    try {
      return SoireePartagee.depuisJson(jsonDecode(brut));
    } catch (_) {
      return null;
    }
  }

  /// Le Festival de la semaine (R50), une fois les niveaux ouverts (R42).
  /// La préférence « festival » le force (« aucun » le coupe), pour les tests.
  Festival? festivalDe(DateTime d) {
    final force = _prefs.getString('festival');
    if (force == 'aucun') return null;
    if (force != null) return Festivals.parId(force);
    return ouvert(Etape.niveaux) ? Festivals.de(d) : null;
  }

  /// Le Bingo du film (R55) : ses points deviennent de l'audace (5 au plus),
  /// une fois par soirée.
  Future<void> gagnerAudaceBingo(String soiree, int points) async {
    final cle = 'bingo_compte_$soiree';
    if (_prefs.getBool(cle) ?? false) return;
    await _prefs.setBool(cle, true);
    final n = points.clamp(0, 5);
    if (n > 0) await _ajouterAudace(n);
    notifyListeners();
  }

  /// Le Relais (R57) : 2 d'audace par relais passé, une seule fois par maillon.
  Future<void> gagnerAudaceRelais(String chaine, int maillon) async {
    final cle = 'relais_${chaine}_$maillon';
    if (_prefs.getBool(cle) ?? false) return;
    await _prefs.setBool(cle, true);
    await _ajouterAudace(Relais.audaceParMaillon);
    notifyListeners();
  }

  // Le Deck d'atouts (R49).

  /// Les atouts possédés et leur nombre d'exemplaires.
  Map<String, int> get atouts {
    final brut = _prefs.getString('atouts');
    if (brut == null) return const {};
    try {
      return {for (final e in (jsonDecode(brut) as Map).entries) '${e.key}': (e.value as num).toInt()};
    } catch (_) {
      return const {};
    }
  }

  /// Les atouts posés dans le deck.
  List<String> get deck => [for (final id in _prefs.getStringList('deck') ?? const <String>[]) if ((atouts[id] ?? 0) > 0) id];

  int get emplacements => Deck.emplacements(atouts.length);

  DateTime? get _dernierBooster => DateTime.tryParse(_prefs.getString('booster_don') ?? '');

  /// Les boosters à ouvrir aujourd'hui (au plus deux en réserve).
  int boostersDispo([DateTime? aujourdhui]) =>
      Deck.disponibles(reserve: _prefs.getInt('booster_reserve') ?? 0, dernierDon: _dernierBooster, aujourdhui: aujourdhui ?? DateTime.now());

  /// Ouvre un booster : trois atouts, ajoutés à la collection. Les nouveaux
  /// vont dans le deck s'il reste de la place. Une série complète donne son
  /// exploit. Vide quand il n'y a pas de booster à ouvrir.
  Future<({List<Atout> cartes, Set<String> nouveaux, List<Serie> series})> ouvrirBooster({Random? hasard, DateTime? maintenant}) async {
    final m = maintenant ?? DateTime.now();
    final dispo = boostersDispo(m);
    if (dispo <= 0) return (cartes: const <Atout>[], nouveaux: const <String>{}, series: const <Serie>[]);
    final sans = _prefs.getInt('booster_sans_epique') ?? 0;
    final cartes = Deck.booster(hasard ?? Random(), sansEpique: sans);
    final avant = atouts;
    final apres = {...avant};
    for (final c in cartes) {
      apres[c.id] = (apres[c.id] ?? 0) + 1;
    }
    final nouveaux = {for (final c in cartes) if (!avant.containsKey(c.id)) c.id};
    await _prefs.setString('atouts', jsonEncode(apres));
    await _prefs.setInt('booster_reserve', dispo - 1);
    await _prefs.setString('booster_don', jourDe(m));
    await _prefs.setInt('booster_sans_epique', cartes.any((c) => c.rarete.index >= Rarete.epique.index) ? 0 : sans + 1);
    final places = Deck.emplacements(apres.length);
    final d = deck;
    for (final id in nouveaux) {
      if (d.length >= places) break;
      d.add(id);
    }
    await _prefs.setStringList('deck', d);
    final completes = Deck.seriesCompletes(apres).where((s) => !Deck.seriesCompletes(avant).contains(s)).toList();
    for (final s in completes) {
      await ajouterExploit(s.exploit);
    }
    _mesurer('booster', {'nouveaux': nouveaux.length});
    notifyListeners();
    return (cartes: cartes, nouveaux: nouveaux, series: completes);
  }

  /// Pose un atout dans le deck (s'il reste une place) ou l'en retire.
  Future<bool> basculerAtout(String id) async {
    final d = deck;
    if (d.contains(id)) {
      d.remove(id);
    } else {
      if ((atouts[id] ?? 0) <= 0 || d.length >= emplacements) return false;
      d.add(id);
    }
    await _prefs.setStringList('deck', d);
    notifyListeners();
    return true;
  }

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
