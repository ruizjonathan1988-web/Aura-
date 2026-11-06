// Les règles du jeu, une par une. Chaque test porte le numéro de la règle
// qu'il protège (voir « Les règles et leurs tests » dans REPRISE.md).
// Une règle nouvelle = un test nouveau ici. Si un test casse, c'est qu'une
// règle a changé : on le décide exprès, jamais par accident.

import 'dart:convert';
import 'dart:math';

import 'package:aura/models/modeles.dart';
import 'package:aura/services/affiche.dart';
import 'package:aura/services/apres_seance.dart';
import 'package:aura/services/deck.dart';
import 'package:aura/services/aura.dart';
import 'package:aura/services/avis_du_jeu.dart';
import 'package:aura/services/cadeaux.dart';
import 'package:aura/services/campagnes.dart';
import 'package:aura/services/carte_genres.dart';
import 'package:aura/services/collection.dart';
import 'package:aura/services/config.dart';
import 'package:aura/services/connexion_vjod.dart';
import 'package:aura/services/coups.dart';
import 'package:aura/services/deblocage.dart';
import 'package:aura/services/duel.dart';
import 'package:aura/services/etat.dart';
import 'package:aura/services/fidelite.dart';
import 'package:aura/services/generique.dart';
import 'package:aura/services/historique.dart';
import 'package:aura/services/juste_un_film.dart';
import 'package:aura/services/ligues.dart';
import 'package:aura/services/ma_tv.dart';
import 'package:aura/services/mesures.dart';
import 'package:aura/services/mise_a_jour.dart';
import 'package:aura/services/niveau.dart';
import 'package:aura/services/plan_du_jour.dart';
import 'package:aura/services/plateformes.dart';
import 'package:aura/services/pont_vjod.dart';
import 'package:aura/services/pop.dart';
import 'package:aura/services/pouvoirs.dart';
import 'package:aura/services/premier_soir.dart';
import 'package:aura/services/rappels.dart';
import 'package:aura/services/retournements.dart';
import 'package:aura/services/rivaux.dart';
import 'package:aura/services/semaine_ligue.dart';
import 'package:aura/services/source_tmdb.dart';
import 'package:aura/services/soiree.dart';
import 'package:aura/services/sources.dart';
import 'package:aura/services/tirage.dart';
import 'package:aura/services/traduction.dart';
import 'package:aura/services/vjod_lien.dart';
import 'package:aura/screens/plateau.dart';
import 'package:aura/widgets/animations.dart';
import 'package:aura/widgets/aura_widgets.dart';
import 'package:aura/widgets/ou_le_voir.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Film _film(String id,
        {double? note = 7.5, int annee = 2010, int duree = 100, bool vu = false, int? votes, List<String> genres = const ['Thriller'], List<String> pays = const ['France']}) =>
    Film(id: id, titre: 'Film $id', note: note, annee: annee, dureeMinutes: duree, genres: genres, pays: pays, dejaVu: vu, nombreVotes: votes);

CarteDefi _carte(String id, {TypeCarte type = TypeCarte.retro, int cases = 3, int duree = 100}) => CarteDefi(
      type: type,
      defi: 'Défi',
      indice: '',
      cases: cases,
      joker: '',
      film: _film(id, duree: duree),
      bulleDePop: '',
    );

/// Pour les tests qui comptent l'audace au point près : le joueur n'est pas
/// derrière Pop, donc pas de Vent dans le dos (R41).
final Map<String, Object> _devantPop = {'pop_decalage_${EtatJeu.moisDe(DateTime.now())}': -60};

/// Par défaut, toutes les règles sont ouvertes (R42) : chaque test vérifie
/// sa règle, pas le déblocage, qui a ses propres tests.
Future<EtatJeu> _etat([Map<String, Object> valeurs = const {}]) async {
  SharedPreferences.setMockInitialValues({'tout_ouvert': true, ...valeurs});
  return EtatJeu(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final maintenant = DateTime.now();

  group('R1 Zéro navet', () {
    final catalogue = [for (var i = 0; i < 10; i++) _film('bon$i'), for (var i = 0; i < 30; i++) _film('navet$i', note: 5.9)];

    test('R1 l\'Affiche de la semaine n\'est jamais un navet ni un film déjà vu', () {
      final avecVu = [...catalogue, for (var i = 0; i < 30; i++) _film('vu$i', note: 9, vu: true)];
      for (var j = 0; j < 28; j++) {
        final a = Affiche.de(DateTime(2026, 11, 1 + j), avecVu, EtatJeu.jourDe)!;
        expect(a.film.id, startsWith('bon'));
      }
    });

    test('R1 le Plan du jour ne fait deviner que des films à 3 étoiles ou plus', () {
      for (var j = 1; j <= 28; j++) {
        final p = PlanDuJour.du(DateTime(2026, 11, j), catalogue)!;
        expect(p.choix.every((f) => f.id.startsWith('bon')), isTrue);
      }
    });

    test('R1 le tirage privilégie les films les mieux notés', () {
      final lot = [
        for (var i = 0; i < 50; i++) _film('moyen$i', note: 6.0 + (i % 10) / 20),
        for (var i = 0; i < 10; i++) _film('top$i', note: 8.5, annee: 1960 + i * 5),
      ];
      for (var graine = 0; graine < 20; graine++) {
        final cartes = Tirage(hasard: Random(graine)).tirer(catalogue: lot, emotion: Emotion.frissonner, duree: Duree.soiree, profil: Profil.fidele);
        expect(cartes.every((c) => (c.film.note ?? 0) >= 6.3), isTrue);
      }
    });

    test('R1 le Plan du jour et l\'Affiche choisissent des films très bien notés', () {
      // 40 films : le haut du panier en garde 16, tous parmi les 20 « top ».
      final lot = [
        for (var i = 0; i < 20; i++) _film('moyen$i', note: 6.1),
        for (var i = 0; i < 20; i++) _film('top$i', note: 8.6),
      ];
      for (var j = 1; j <= 28; j++) {
        expect(PlanDuJour.du(DateTime(2026, 11, j), lot)!.film.id, startsWith('top'));
        expect(Affiche.de(DateTime(2026, 11, j), lot, EtatJeu.jourDe)!.film.id, startsWith('top'));
      }
    });

    test('R1 un film récent a besoin d\'assez d\'avis, un vieux film un peu moins', () {
      expect(Tirage.assezBon(_film('a', votes: 149)), isFalse);
      expect(Tirage.assezBon(_film('b', votes: 150)), isTrue);
      expect(Tirage.assezBon(_film('c', votes: 30, annee: 1960)), isTrue);
    });
  });

  group('R2 Plafond de 3 cases par jour', () {
    test('R2 deux cartes Rétro le même jour : la seconde ne rapporte plus rien', () async {
      final e = await _etat();
      expect(await e.validerSeance(_carte('a'), pronostic: 3), 3);
      expect(await e.validerSeance(_carte('b'), pronostic: 3), 0);
      expect(e.position, 4);
      expect(e.billets, hasLength(2), reason: 'la séance est gardée même sans case');
    });

    test('R2 un film vu hier compte sur la journée d\'hier, pas sur celle d\'aujourd\'hui', () async {
      final e = await _etat();
      await e.validerSeance(_carte('a'), pronostic: 3);
      await e.commencerSeance(_carte('b'), pronostic: 3);
      final hier = maintenant.subtract(const Duration(days: 1));
      final gagnees = await e.validerEnCours(e.enCours.first, vuLe: hier, auto: true);
      expect(gagnees, hier.month == maintenant.month ? 3 : 0);
    });
  });

  group('R3 Jamais de points au temps passé', () {
    test('R3 un film de 5 heures ne rapporte pas plus qu\'un film d\'1 h 20', () async {
      final court = await _etat();
      final long = await _etat();
      expect(await court.validerSeance(_carte('c', duree: 80), pronostic: 3), await long.validerSeance(_carte('l', duree: 300), pronostic: 3));
    });

    test('R3 la durée choisie ne sert qu\'à filtrer, jamais à compter', () {
      final cartes = Tirage().tirer(catalogue: [for (var i = 0; i < 9; i++) _film('f$i', annee: 1950 + i * 9)], emotion: Emotion.frissonner, duree: Duree.soiree, profil: Profil.fidele);
      expect(cartes.every((c) => c.cases >= 1 && c.cases <= Regles.casesParJourMax), isTrue);
    });
  });

  group('R4 Revenir ne punit jamais', () {
    test('R4 une séance sans case ne fait jamais reculer le pion', () async {
      final e = await _etat({'mois': EtatJeu.moisDe(maintenant), 'position': 9});
      await e.validerSeance(_carte('a'), pronostic: 3);
      final apres = e.position;
      await e.validerSeance(_carte('b'), pronostic: 3);
      expect(e.position, apres);
      expect(apres, greaterThanOrEqualTo(9));
    });

    test('R4 rouvrir l\'appli plus tard dans le mois garde la position', () async {
      final e = await _etat({'mois': EtatJeu.moisDe(maintenant), 'position': 17});
      expect(e.position, 17);
    });
  });

  group('R5 Le plateau du mois', () {
    test('R5 le 1er du mois, tout le monde repart de la case 1', () async {
      final e = await _etat({'mois': '2000-01', 'position': 22});
      expect(e.position, 1);
    });

    test('R5 personne ne dépasse la case 30', () async {
      final e = await _etat({'mois': EtatJeu.moisDe(maintenant), 'position': 29});
      await e.validerSeance(_carte('a'), pronostic: 3);
      expect(e.position, Regles.taillePlateau);
    });

    test('R5 une séance du mois dernier ne fait pas avancer le plateau de ce mois', () async {
      final e = await _etat();
      await e.commencerSeance(_carte('a'), pronostic: 3);
      final moisDernier = DateTime(maintenant.year, maintenant.month - 1, 15);
      expect(await e.validerEnCours(e.enCours.first, vuLe: moisDernier, auto: true), 0);
      expect(e.position, 1);
    });
  });

  group('R6 Le Plan du jour', () {
    test('R6 un seul essai par jour', () async {
      final e = await _etat();
      expect(e.planDuJour, isNull);
      await e.jouerPlanDuJour(const ResultatPlan(indices: 2, trouve: false));
      expect(e.planDuJour?.trouve, isFalse, reason: 'le résultat du jour est figé');
    });

    test('R6 le lendemain, une nouvelle partie', () async {
      final e = await _etat({'plan_jour': '2000-01-01', 'plan_indices': 1, 'plan_trouve': true});
      expect(e.planDuJour, isNull);
    });

    test('R6 3 indices, et 4 réponses à choisir : rien à taper', () {
      final p = PlanDuJour.du(DateTime(2026, 11, 5), [for (var i = 0; i < 8; i++) _film('p$i')])!;
      expect(p.indices, hasLength(3));
      expect(p.choix, hasLength(4));
    });
  });

  group('R7 L\'Affiche de la semaine', () {
    test('R7 le Curseur placé reste secret jusqu\'au dimanche', () {
      expect(Affiche.jourDeRevelation(DateTime(2026, 11, 7)), isFalse); // samedi
      expect(Affiche.jourDeRevelation(DateTime(2026, 11, 8)), isTrue); // dimanche
    });

    test('R7 le Curseur se garde d\'une ouverture à l\'autre', () async {
      final e = await _etat();
      await e.placerCurseur('2026-11-02', 7);
      expect(e.curseurDe('2026-11-02'), 7);
      expect(e.curseurDe('2026-11-09'), isNull);
    });
  });

  group('R8 Pop, l\'adversaire du solo', () {
    test('R8 il triche rarement : jamais plus de 5 cases volées par mois', () {
      for (var an = 2026; an <= 2028; an++) {
        for (var m = 1; m <= 12; m++) {
          var triches = 0;
          for (var j = 1; j <= 31; j++) {
            final d = DateTime(an, m, j);
            if (d.month == m && Pop.triche(d)) triches++;
          }
          expect(triches, lessThanOrEqualTo(5), reason: '$m/$an');
        }
      }
    });

    test('R8 son pari ne change pas en cours de semaine', () {
      final lundi = DateTime(2026, 11, 2);
      for (var j = 0; j < 7; j++) {
        expect(Pop.pariDe(lundi.add(Duration(days: j))).texte, Pop.pariDe(lundi).texte);
      }
    });

    test('R8 un pari perdu ne le fait reculer qu\'une fois', () {
      final jour = DateTime(2026, 11, 5, 21);
      final lundi = Pop.lundiDe(jour);
      final semaine = [
        for (var i = 0; i < 6; i++)
          for (final t in ['Rétro', 'Voyage', 'Affiche'])
            Billet(titre: 'T$i$t', type: t, pronostic: 3, note: 3, verdict: 'Oui', cases: 1, date: lundi.add(Duration(hours: 20 + i))),
      ];
      expect(Pop.position(jour, semaine), Pop.position(jour, const []) - Pop.recul);
    });

    test('R8 il reste toujours sur le plateau', () {
      final billets = [
        for (var j = 1; j <= 30; j++)
          for (final t in ['Rétro', 'Voyage', 'Affiche']) Billet(titre: 'T', type: t, pronostic: 3, note: 3, verdict: 'Oui', cases: 1, date: DateTime(2026, 11, j, 20)),
      ];
      for (var j = 1; j <= 30; j++) {
        final p = Pop.position(DateTime(2026, 11, j, 22), billets);
        expect(p, inInclusiveRange(1, Regles.taillePlateau));
      }
    });
  });

  group('R9 Aucune séance perdue', () {
    test('R9 une carte jouée est gardée jusqu\'à sa validation', () async {
      final e = await _etat();
      await e.commencerSeance(_carte('a'), pronostic: 4);
      final relu = await _etatDepuis(e);
      expect(relu.enCours.single.filmId, 'a');
      expect(relu.enCours.single.pronostic, 4);
    });

    test('R9 valider dans Ce soir retire la carte de l\'attente', () async {
      final e = await _etat();
      await e.commencerSeance(_carte('a'), pronostic: 4);
      await e.validerSeance(_carte('a'), pronostic: 4);
      expect(e.enCours, isEmpty);
    });

    test('R9 « Alors, ce film ? » : une note suffit à valider', () async {
      final e = await _etat();
      await e.commencerSeance(_carte('a'), pronostic: 4);
      expect(await e.validerEnCours(e.enCours.first, note: 2), 3);
      expect(e.billets.single.note, 2);
      expect(e.motDePop, isNotNull, reason: 'Pop chambre un pronostic raté');
    });

    test('R9 un billet automatique se note en un geste, après coup', () async {
      final e = await _etat();
      await e.commencerSeance(_carte('a'), pronostic: 4);
      await e.validerEnCours(e.enCours.first, vuLe: maintenant, auto: true);
      expect(e.billetANoter, isNotNull);
      await e.noterBillet(e.billetANoter!, 4);
      expect(e.billetANoter, isNull);
      expect(e.billets.single.note, 4);
    });

    test('R9 Jellyfin ne valide que les films vus après la carte jouée', () {
      final debut = DateTime(2026, 11, 5, 21);
      expect(SourceJellyfin.dateDeVisionnage({'Played': true, 'LastPlayedDate': '2026-11-04T20:00:00Z'}, debut), isNull);
      expect(SourceJellyfin.dateDeVisionnage({'Played': true, 'LastPlayedDate': '2026-11-06T20:00:00Z'}, debut), isNotNull);
    });

    test('R9 le taux cartes jouées / billets se mesure', () async {
      final e = await _etat();
      await e.commencerSeance(_carte('a'), pronostic: 3);
      await e.commencerSeance(_carte('b'), pronostic: 3);
      await e.validerEnCours(e.enCours.first, note: 3);
      expect(e.tauxDeValidation, 0.5);
    });
  });

  group('R10 Tout se joue à la télécommande', () {
    test('R10 au-delà de 900 points de large, Aura se comporte en appli de télé (champs de texte remplacés)', () {
      expect(estLargeurTele(390), isFalse);
      expect(estLargeurTele(960), isTrue);
      expect(estLargeurTele(1920), isTrue);
    });
  });

  group('R11 Le premier soir', () {
    test('R11 le test est équilibré : chaque profil revient trois fois', () {
      final compte = <Profil, int>{};
      for (final q in TestSpectateur.questions) {
        expect(q.reponses, hasLength(4));
        for (final r in q.reponses) {
          compte[r.$2] = (compte[r.$2] ?? 0) + 1;
        }
      }
      expect(compte.keys.toSet(), Profil.values.toSet());
      expect(compte.values.every((n) => n == 3), isTrue);
    });

    test('R11 le profil le plus choisi gagne ; à égalité, le plus récent', () {
      expect(TestSpectateur.resultat([Profil.critique, Profil.hote, Profil.critique]), Profil.critique);
      expect(TestSpectateur.resultat([Profil.critique, Profil.hote]), Profil.hote);
    });

    test('R11 le Bluff de Pop : un seul vrai synopsis, deux faux, jamais de navet ni de documentaire', () async {
      final demo = await SourceDemo().catalogue();
      for (var graine = 0; graine < 40; graine++) {
        final b = BluffDePop.pour(demo, Random(graine))!;
        expect(b.synopsis, hasLength(3));
        expect(b.synopsis.toSet(), hasLength(3));
        expect(b.synopsis[b.vrai], BluffDePop.premierePhrase(b.film.synopsis));
        expect(b.synopsis.where(BluffDePop.fauxDePop.contains), hasLength(2));
        expect(Tirage.assezBon(b.film), isTrue);
        expect(b.film.genres, isNot(contains('Documentary')));
      }
    });

    test('R11 un synopsis Jellyfin trop long est ramené à sa première phrase', () {
      expect(BluffDePop.premierePhrase('Un homme part. Puis il revient.'), 'Un homme part.');
      expect(BluffDePop.premierePhrase(null), '');
    });

    test('R11 le Joker du Bluff : +1 case une seule fois, sans dépasser 3 par jour', () async {
      final e = await _etat();
      await e.terminerAccueil(profil: Profil.critique, bluffGagne: true);
      expect(e.accueilFait, isTrue);
      expect(e.profil, Profil.critique);
      expect(await e.validerSeance(_carte('a', type: TypeCarte.envie, cases: 1), pronostic: 3), 2);
      expect(e.jokerBluff, isFalse);
      expect(await e.validerSeance(_carte('b', type: TypeCarte.envie, cases: 1), pronostic: 3), 1);

      final f = await _etat();
      await f.terminerAccueil(bluffGagne: true);
      expect(await f.validerSeance(_carte('c'), pronostic: 3), 3, reason: 'le Joker ne fait pas sauter le plafond');
    });
  });

  group('R12 La carte des genres contre Pop', () {
    Billet dans(Region r, DateTime d) => Billet(
          titre: 'Film ${r.name}',
          type: 'Envie',
          pronostic: 3,
          cases: 1,
          date: d,
          genres: r.genres.isEmpty ? const [] : [r.genres.first],
          annee: r == Region.classiques ? 1955 : 2010,
          pays: r == Region.ailleurs ? const ['Japon'] : const ['France'],
        );

    test('R12 une séance rend la région tienne, et un film peut en couvrir plusieurs', () {
      final samourai = Billet(titre: 'Le Samouraï', type: 'Rétro', pronostic: 4, cases: 3, date: DateTime(2026, 11, 3, 21), genres: const ['Crime'], annee: 1967, pays: const ['France']);
      final c = CarteDesGenres.de(DateTime(2026, 11, 4), [samourai]);
      expect(c.proprios[Region.polar], Proprio.joueur);
      expect(c.proprios[Region.classiques], Proprio.joueur);
      expect(c.proprios[Region.ailleurs], Proprio.libre);
    });

    test('R12 une région visée et pas défendue avant dimanche est prise par Pop', () {
      final visee = CarteDesGenres.de(DateTime(2026, 11, 4), const []).cible!;
      final apres = CarteDesGenres.de(DateTime(2026, 11, 10), const []);
      expect(apres.proprios[visee], Proprio.pop);
      expect(apres.regionsDePop, 1);
      expect(apres.prisesCetteSemaine, [visee]);
      expect(CarteDesGenres.de(DateTime(2026, 11, 17), const []).regionsDePop, 2);
    });

    test('R12 regarder un film dans la région visée la défend', () {
      final visee = CarteDesGenres.de(DateTime(2026, 11, 4), const []).cible!;
      final c = CarteDesGenres.de(DateTime(2026, 11, 10), [dans(visee, DateTime(2026, 11, 5, 21))]);
      expect(c.proprios[visee], Proprio.joueur);
      expect(c.regionsDePop, 0);
    });

    test('R12 une région prise par Pop se reprend', () {
      final prise = CarteDesGenres.de(DateTime(2026, 11, 10), const []).prisesCetteSemaine.single;
      final c = CarteDesGenres.de(DateTime(2026, 11, 12), [dans(prise, DateTime(2026, 11, 11, 21))]);
      expect(c.proprios[prise], Proprio.joueur);
    });

    test('R12 avant le premier lundi du mois, Pop ne vise rien', () {
      expect(CarteDesGenres.de(DateTime(2026, 11, 1, 20), const []).cible, isNull);
      expect(CarteDesGenres.de(DateTime(2026, 11, 1, 20), const []).regionsDePop, 0);
    });

    test('R12 chaque région de Pop lui vaut une case', () {
      final jour = DateTime(2026, 11, 10, 20);
      final visee = CarteDesGenres.de(DateTime(2026, 11, 4), const []).cible!;
      final defendu = [dans(visee, DateTime(2026, 11, 5, 21))];
      expect(Pop.position(jour, const []) - Pop.position(jour, defendu), 1);
    });
  });

  group('R13 Se connecter avec VJOD sans clé d\'API', () {
    final reponse = jsonEncode({'AccessToken': 'jeton42', 'User': {'Id': 'u7'}, 'ServerId': 's1'});

    test('R13 identifiant et mot de passe donnent une connexion complète', () async {
      late http.Request recue;
      final client = MockClient((r) async {
        recue = r;
        return http.Response(reponse, 200);
      });
      final c = await ConnexionVjod(adresse: 'vjod.exemple.fr/', appareil: 'aura-test', client: client).avecIdentifiants(' jon ', 'secret');
      expect(c.complete, isTrue);
      expect(c.jeton, 'jeton42');
      expect(c.utilisateurId, 'u7');
      expect(recue.url.toString(), 'https://vjod.exemple.fr/Users/AuthenticateByName');
      expect(recue.headers['X-Emby-Authorization'], contains('DeviceId="aura-test"'));
      expect(recue.headers['Authorization'], startsWith('MediaBrowser Client="Aura"'));
      expect(recue.headers['Authorization'], contains('DeviceId="aura-test"'));
      expect(jsonDecode(recue.body), {'Username': 'jon', 'Pw': 'secret'});
    });

    test('R13 la bibliothèque est lue avec l\'en-tête des Jellyfin récents', () async {
      late http.Request recue;
      final client = MockClient((r) async {
        recue = r;
        return http.Response('{"Items": []}', 200);
      });
      await SourceJellyfin(const ConnexionJellyfin(adresse: 'https://vjod.exemple.fr', utilisateurId: 'u7', jeton: 'jeton42'), client: client).catalogue();
      expect(recue.headers['Authorization'], startsWith('MediaBrowser '));
      expect(recue.headers['Authorization'], contains('Token="jeton42"'));
    });

    test('R13 le serveur VJOD de Jon est pré-rempli, chemin /jellyfin compris', () async {
      expect(Config.serveurVjod, 'https://ava88.zen.usbx.me/jellyfin');
      late Uri appel;
      final client = MockClient((r) async {
        appel = r.url;
        return http.Response(reponse, 200);
      });
      await ConnexionVjod(adresse: Config.serveurVjod, appareil: 'a', client: client).avecIdentifiants('jon', 'x');
      expect(appel.toString(), 'https://ava88.zen.usbx.me/jellyfin/Users/AuthenticateByName');
    });

    test('R13 un mauvais mot de passe donne un message clair', () async {
      final client = MockClient((r) async => http.Response('', 401));
      await expectLater(
        ConnexionVjod(adresse: 'https://vjod.exemple.fr', appareil: 'a', client: client).avecIdentifiants('jon', 'faux'),
        throwsA(isA<ErreurSource>().having((e) => e.message, 'message', contains('mot de passe'))),
      );
    });

    test('R13 Quick Connect : code affiché, accepté sur le téléphone, puis connecté', () async {
      var accepte = false;
      final client = MockClient((r) async {
        final chemin = r.url.path;
        if (chemin.endsWith('/QuickConnect/Initiate')) return http.Response(jsonEncode({'Secret': 'sec', 'Code': '123456'}), 200);
        if (chemin.endsWith('/QuickConnect/Connect')) return http.Response(jsonEncode({'Authenticated': accepte}), 200);
        if (chemin.endsWith('/Users/AuthenticateWithQuickConnect')) return http.Response(reponse, 200);
        return http.Response('', 404);
      });
      final vjod = ConnexionVjod(adresse: 'https://vjod.exemple.fr', appareil: 'a', client: client);
      final (secret, code) = await vjod.demanderCode();
      expect(code, '123456');
      expect(await vjod.codeAccepte(secret), isFalse);
      accepte = true;
      expect(await vjod.codeAccepte(secret), isTrue);
      expect((await vjod.avecQuickConnect(secret)).jeton, 'jeton42');
    });
  });

  group('R14 Le Duel du canapé', () {
    Duel nouveau() => Duel([for (var i = 0; i < 3; i++) _carte('a$i')], [for (var i = 0; i < 3; i++) _carte('b$i')]);
    CarteEnJeu de(Duel d, int j, int n) => d.cartes.where((c) => c.joueur == j).elementAt(n);

    test('R14 on écarte à tour de rôle une carte de l\'autre', () {
      final d = nouveau();
      expect(d.tour, 0);
      expect(d.peutEcarter(de(d, 0, 0)), isFalse, reason: 'pas ses propres cartes tant que l\'autre en a plusieurs');
      d.ecarter(de(d, 1, 0));
      expect(d.tour, 1);
      expect(() => d.ecarter(de(d, 1, 1)), throwsStateError);
    });

    test('R14 un Veto par joueur protège une carte de l\'adversaire', () {
      final d = nouveau();
      d.proteger(de(d, 0, 2));
      expect(d.veto[0], isFalse);
      expect(d.peutEcarter(de(d, 0, 2)), isFalse);
      expect(d.peutProteger(de(d, 1, 0)), isTrue);
      d.ecarter(de(d, 0, 0));
      expect(d.peutProteger(de(d, 0, 1)), isFalse, reason: 'le Veto ne sert qu\'une fois');
    });

    test('R14 la partie finit toujours avec une carte chacun', () {
      for (var graine = 0; graine < 30; graine++) {
        final hasard = Random(graine);
        final d = nouveau();
        var coups = 0;
        while (!d.fini && coups < 20) {
          final veto = d.cartes.where(d.peutProteger).toList();
          if (veto.isNotEmpty && hasard.nextInt(4) == 0) {
            d.proteger(veto[hasard.nextInt(veto.length)]);
          } else {
            final possibles = d.cartes.where(d.peutEcarter).toList();
            expect(possibles, isNotEmpty, reason: 'il y a toujours un coup possible');
            d.ecarter(possibles[hasard.nextInt(possibles.length)]);
          }
          coups++;
        }
        expect(d.fini, isTrue);
        expect(d.restantes(0), hasLength(1));
        expect(d.restantes(1), hasLength(1));
      }
    });

    test('R14 le quiz : 4 réponses différentes dont la bonne, jamais deux fois la même question', () {
      for (final q in Quiz.questions) {
        expect(q.reponses, hasLength(4));
        expect(q.reponses.toSet(), hasLength(4));
      }
      final tirees = Quiz.tirer(6, Random(1));
      expect(tirees.map((q) => q.texte).toSet(), hasLength(6));
    });
  });

  group('R15 Revenir après une pause', () {
    Billet le(DateTime d) => Billet(titre: 'T', type: 'Envie', pronostic: 3, cases: 1, date: d);

    test('R15 après 3 jours d\'absence, une carte de rattrapage (+2 cases, plafond respecté)', () async {
      final ilYa = maintenant.subtract(const Duration(days: 4)).toIso8601String();
      final ancien = '{"titre":"T","type":"Envie","pronostic":3,"cases":1,"date":"$ilYa","verdict":""}';
      final e = await _etat({'derniere_visite': ilYa, 'billets': [ancien]});
      expect(e.bonRetour, 4);
      expect(e.carteRattrapage, isTrue);
      expect(await e.validerSeance(_carte('a', type: TypeCarte.envie, cases: 1), pronostic: 3), 3);
      expect(e.carteRattrapage, isFalse);
    });

    test('R15 pas de carte de rattrapage au premier lancement ni après une courte absence', () async {
      expect((await _etat()).bonRetour, isNull);
      final hier = maintenant.subtract(const Duration(days: 1)).toIso8601String();
      expect((await _etat({'derniere_visite': hier, 'billets': ['{"titre":"T","type":"Envie","pronostic":3,"cases":1,"date":"$hier","verdict":""}']})).carteRattrapage, isFalse);
    });

    test('R15 la série se compte en semaines, et une semaine de pause ne la casse pas', () {
      final jeudi = DateTime(2026, 11, 5, 21);
      expect(Fidelite.serie(jeudi, const []), 0);
      final avecPause = [le(DateTime(2026, 11, 3)), le(DateTime(2026, 10, 20)), le(DateTime(2026, 10, 13))];
      expect(Fidelite.serie(jeudi, avecPause), 3, reason: 'la semaine du 26 octobre est une pause gratuite');
      final cassee = [le(DateTime(2026, 11, 3)), le(DateTime(2026, 10, 13))];
      expect(Fidelite.serie(jeudi, cassee), 1, reason: 'deux semaines vides remettent à zéro');
    });

    test('R15 un lundi matin sans film ne fait pas perdre la série', () {
      final lundi = DateTime(2026, 11, 9, 8);
      expect(Fidelite.serie(lundi, [le(DateTime(2026, 11, 5)), le(DateTime(2026, 10, 29))]), 2);
    });
  });

  group('R16 Le Bluff de la semaine contre Pop', () {
    test('R16 le vrai synopsis de l\'Affiche est parmi trois, avec deux faux de Pop', () async {
      final film = (await SourceDemo().catalogue()).first;
      final b = BluffDePop.pourFilm(film, Random(3))!;
      expect(b.synopsis[b.vrai], BluffDePop.premierePhrase(film.synopsis));
      expect(b.synopsis.where(BluffDePop.fauxDePop.contains), hasLength(2));
      expect(BluffDePop.pourFilm(_film('sans'), Random(3)), isNull, reason: 'pas de Bluff sans synopsis');
    });

    test('R16 un seul essai par semaine, et le vrai trouvé donne un Joker', () async {
      final e = await _etat();
      expect(e.bluffDe('2026-11-02'), isNull);
      await e.jouerBluff('2026-11-02', trouve: true);
      expect(e.bluffDe('2026-11-02'), isTrue);
      expect(e.jokerBluff, isTrue);
      await e.jouerBluff('2026-11-02', trouve: false);
      expect(e.bluffDe('2026-11-02'), isTrue, reason: 'le premier essai compte');
      expect(e.bluffDe('2026-11-09'), isNull);
    });
  });

  group('R17 Mesurer sans gêner', () {
    test('R17 une seule ouverture comptée par jour', () {
      final soir = DateTime(2026, 11, 6, 21);
      expect(ServiceMesures.premiereOuvertureDuJour(null, soir), isTrue);
      expect(ServiceMesures.premiereOuvertureDuJour('2026-11-06', soir), isFalse);
      expect(ServiceMesures.premiereOuvertureDuJour('2026-11-05', soir), isTrue);
    });

    test('R17 hors ligne, la file d\'attente ne dépasse jamais 200 événements', () {
      var file = <String>[];
      for (var i = 0; i < 250; i++) {
        file = ServiceMesures.ajouter(file, 'e$i');
      }
      expect(file, hasLength(ServiceMesures.maxEnAttente));
      expect(file.first, 'e50');
      expect(file.last, 'e249');
    });

    test('R17 seuls des événements prévus partent, sans titre de film', () {
      expect(ServiceMesures.types, {'ouverture', 'carte_jouee', 'billet', 'plan_du_jour', 'duel', 'bluff'});
    });
  });

  group('R18 Les amis donnent des raisons de revenir', () {
    test('R18 le fil raconte la séance d\'un ami en une phrase', () {
      final n = Nouvelle.depuisJson({
        'titre': 'Le Samouraï',
        'note': 4,
        'verdict': 'Froid et parfait',
        'vu_le': '2026-11-05T21:00:00Z',
        'joueur_id': 'lea',
        'joueurs': {'pseudo': 'Léa', 'profil': 'critique'},
      }, 'jon');
      expect(n.phrase, 'Léa a vu « Le Samouraï » et lui donne 4 sur 5.');
      expect(n.profil, Profil.critique);
      expect(n.moi, isFalse);
    });

    test('R18 ses propres séances sont racontées à la deuxième personne', () {
      final n = Nouvelle.depuisJson({'titre': 'Coco', 'vu_le': '2026-11-05T21:00:00Z', 'joueur_id': 'jon', 'joueurs': {'pseudo': 'Jon'}}, 'jon');
      expect(n.phrase, 'Tu as vu « Coco ».');
    });
  });

  group('R19 Les animations respectent l\'accessibilité', () {
    testWidgets('R19 si l\'appareil demande moins d\'animations, Aura les coupe', (tester) async {
      bool? reduit;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(builder: (c) {
          reduit = animationsReduites(c);
          return const SizedBox();
        }),
      ));
      expect(reduit, isTrue);
    });

    testWidgets('R19 une entrée en scène s\'affiche directement, sans mouvement', (tester) async {
      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Entree(delai: Duration(seconds: 5), child: SizedBox(key: Key('carte'), width: 10, height: 10)),
        ),
      ));
      expect(find.byKey(const Key('carte')), findsOneWidget);
      expect(find.ancestor(of: find.byKey(const Key('carte')), matching: find.byType(Opacity)), findsNothing);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('R19 sinon, la carte arrive en fondu', (tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: Entree(child: SizedBox(key: Key('carte'), width: 10, height: 10)),
      ));
      expect(find.ancestor(of: find.byKey(const Key('carte')), matching: find.byType(Opacity)), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('R20 Le rappel du lendemain', () {
    test('R20 un seul rappel, le lendemain à midi et demi', () {
      expect(Rappels.moment(DateTime(2026, 11, 5, 21, 40)), DateTime(2026, 11, 6, 12, 30));
      expect(Rappels.moment(DateTime(2026, 11, 30, 23, 59)), DateTime(2026, 12, 1, 12, 30));
    });

    test('R20 les trois boutons donnent une note, un simple toucher n\'en donne pas', () {
      expect(Rappels.lire('d1', 'note_4'), ('d1', 4));
      expect(Rappels.lire('d1', null), ('d1', null));
      expect(Rappels.lire(null, 'note_5'), isNull);
    });

    test('R20 noter depuis la notification valide la séance en un geste', () async {
      final e = await _etat();
      await e.commencerSeance(_carte('a'), pronostic: 4);
      expect(await e.repondreRappel('a', null), isNull);
      expect(e.enCours, hasLength(1), reason: 'un simple toucher ne valide rien');
      expect(await e.repondreRappel('a', 5), 3);
      expect(e.enCours, isEmpty);
      expect(e.billets.single.note, 5);
    });
  });

  group('R21 La Révélation du dimanche', () {
    test('R21 le pari de Pop le Médium est entre 0 et 10, fixé pour la semaine', () {
      for (final semaine in ['2026-11-02', '2026-11-09', '2027-01-04']) {
        final p = Affiche.pariDuMedium(semaine);
        expect(p, inInclusiveRange(0, 10));
        expect(Affiche.pariDuMedium(semaine), p);
      }
    });

    test('R21 un Médium raté de 3 crans ou plus donne un Joker, une seule fois par semaine', () async {
      final e = await _etat();
      expect(Affiche.mediumRate(2, 5), isTrue);
      expect(Affiche.mediumRate(4, 5), isFalse);
      expect(await e.terminerRevelation('2026-11-02', pari: 2, curseur: 8), isTrue);
      expect(e.jokerBluff, isTrue);
      expect(e.revelationFaite('2026-11-02'), isTrue);
      expect(await e.terminerRevelation('2026-11-02', pari: 2, curseur: 8), isFalse);
    });
  });

  group('R22 La collection', () {
    Billet b(String type, {int? note, List<String> pays = const ['France']}) =>
        Billet(titre: 'T', type: type, pronostic: 4, cases: 1, date: maintenant, note: note, pays: pays);
    Bilan bilan(List<Billet> billets, {int position = 5, int pop = 9, int bluffs = 0}) =>
        Bilan(billets: billets, position: position, positionDePop: pop, bluffsGagnes: bluffs, maintenant: maintenant);

    test('R22 les exploits se méritent par le jeu', () {
      expect(Collection.merites(bilan(const [])), isEmpty);
      expect(Collection.merites(bilan([b('Envie')])), contains('premiere'));
      expect(Collection.merites(bilan([for (var i = 0; i < 3; i++) b('Rétro')])), contains('retro'));
      expect(Collection.merites(bilan([for (final p in ['France', 'Japon', 'Iran', 'Brésil', 'Italie']) b('Voyage', pays: [p])])), contains('globe'));
      expect(Collection.merites(bilan([for (var i = 0; i < 3; i++) b('Envie', note: 4)])), contains('devin'));
      expect(Collection.merites(bilan([b('Envie')], position: 12, pop: 9)), contains('devant'));
      expect(Collection.merites(bilan(const [], bluffs: 3)), contains('detecteur'));
    });

    test('R22 la figurine de saison se gagne à la case 20 et porte le nom du mois', () {
      expect(Collection.merites(bilan([b('Envie')], position: 19)), isNot(contains(Collection.saison(maintenant))));
      expect(Collection.merites(bilan([b('Envie')], position: 20)), contains(Collection.saison(maintenant)));
      expect(Collection.nomDeSaison('saison_2026_11'), 'Figurine de saison, novembre 2026');
    });

    test('R22 un exploit obtenu reste à toi, même quand le plateau repart à zéro', () async {
      final e = await _etat({'mois': EtatJeu.moisDe(maintenant), 'position': 29});
      await e.validerSeance(_carte('a'), pronostic: 3);
      expect(e.collection, containsAll(['premiere', 'finale', Collection.saison(maintenant)]));
      expect(e.motDePop, contains('Nouvel exploit'));
      final relu = await _etat({'mois': '2000-01', 'position': 29, 'collection': e.collection.toList()});
      expect(relu.position, 1);
      expect(relu.collection, contains('finale'));
    });
  });

  group('R23 L\'Affiche de la semaine en ligue', () {
    const membres = ['lea', 'jon', 'ines', 'max'];
    Geste g(String j, String type, Map<String, dynamic> v, [int minute = 0]) =>
        Geste(joueurId: j, type: type, valeur: v, quand: DateTime(2026, 11, 2, 20, minute));
    SemaineDeLigue semaine(List<Geste> gestes) => SemaineDeLigue(membres: membres, semaine: '2026-11-02', gestes: gestes);

    test('R23 chacun programme à son tour ; le Faussaire n\'est jamais le Programmateur', () {
      final vus = <String>{};
      for (var k = 0; k < 8; k++) {
        final lundi = DateTime(2026, 11, 2).add(Duration(days: 7 * k));
        final s = SemaineDeLigue(membres: membres, semaine: '${lundi.year}-${lundi.month.toString().padLeft(2, '0')}-${lundi.day.toString().padLeft(2, '0')}', gestes: const []);
        vus.add(s.programmateur!);
        expect(s.faussaire, isNot(s.programmateur));
      }
      expect(vus, membres.toSet(), reason: 'en quatre semaines, tout le monde a programmé');
      expect(SemaineDeLigue(membres: const ['a', 'b'], semaine: '2026-11-02', gestes: const []).faussaire, isNull, reason: 'pas de Faussaire à deux');
    });

    test('R23 la première Affiche choisie compte', () {
      final s = semaine([
        g('max', 'affiche', {'titre': 'Coco', 'par_pop': true}, 5),
        g('lea', 'affiche', {'titre': 'Le Samouraï', 'synopsis': 'Un tueur à gages.'}, 1),
      ]);
      expect(s.affiche!.titre, 'Le Samouraï');
    });

    test('R23 chacun départage le vrai synopsis et les faux des autres, jamais le sien', () {
      final s = semaine([
        g('lea', 'affiche', {'titre': 'Le Samouraï', 'synopsis': 'Le vrai.'}),
        g('jon', 'bluff', {'texte': 'Faux de Jon.'}),
        g('max', 'bluff', {'texte': 'Faux de Max.'}),
      ]);
      final pourJon = s.synopsisPour('jon');
      expect(pourJon.map((e) => e.$1).toSet(), {'vrai', 'max'});
      expect(s.synopsisPour('ines').map((e) => e.$2).toSet(), {'Le vrai.', 'Faux de Jon.', 'Faux de Max.'});
      expect(s.synopsisPour('ines'), s.synopsisPour('ines'), reason: 'même ordre à chaque ouverture');
    });

    test('R23 les points de la Révélation', () {
      final s = semaine([
        g('lea', 'affiche', {'titre': 'Le Samouraï', 'synopsis': 'Le vrai.'}),
        g('jon', 'bluff', {'texte': 'Faux de Jon.'}),
        g('ines', 'vote_bluff', {'choix': 'vrai'}),
        g('max', 'vote_bluff', {'choix': 'jon'}),
        g('lea', 'curseur', {'valeur': 4}),
        g('jon', 'curseur', {'valeur': 6}),
        g('max', 'curseur', {'valeur': 9}),
      ]);
      final p = s.points;
      expect(s.moyenneCurseur, closeTo(19 / 3, 1e-9));
      expect(p['ines'], 2, reason: 'vrai synopsis trouvé');
      expect(p['jon'], 1 + 1, reason: 'Max piégé par son Bluff, et Curseur le plus proche de la moyenne');
      final f = s.faussaire!;
      final autres = membres.where((m) => m != f).toList();
      final avecFaussaire = semaine([
        g(autres[0], 'vote_faussaire', {'choix': f}),
        g(autres[1], 'vote_faussaire', {'choix': autres[2]}),
      ]);
      expect(avecFaussaire.points[autres[0]], 2);
      expect(avecFaussaire.points[f], 1);
    });

    test('R23 on compte où en est la ligue', () {
      final s = semaine([g('jon', 'curseur', {'valeur': 3}), g('lea', 'curseur', {'valeur': 5}), g('inconnu', 'curseur', {'valeur': 1})]);
      expect(s.combien('curseur'), 2, reason: 'seuls les membres comptent');
    });
  });

  group('R24 La Soirée jeu (téléphones en manettes)', () {
    final joueurs = [
      {'id': 'jon', 'pseudo': 'Jon', 'profil': 'fidele'},
      {'id': 'lea', 'pseudo': 'Léa', 'profil': 'critique'},
    ];
    Map<String, dynamic> partie() => PartieSoiree.distribuer(
          joueurs,
          [
            [for (var i = 0; i < 3; i++) _carte('a$i')],
            [for (var i = 0; i < 3; i++) _carte('b$i')],
          ],
          Quiz.tirer(PartieSoiree.nbQuestions, Random(2)),
          Random(2),
        );

    test('R24 le code de soirée : 4 lettres faciles à lire', () {
      for (var i = 0; i < 50; i++) {
        expect(PartieSoiree.code(Random(i)), matches(RegExp(r'^[ABCDEFGHJKMNPRSTUVWXYZ]{4}$')));
      }
    });

    test('R24 chacun joue à son tour depuis son téléphone ; les gestes interdits sont refusés', () {
      var e = partie();
      expect(PartieSoiree.appliquer(e, 'lea', {'type': 'ecarter', 'carte': 0}), isNull, reason: 'pas son tour');
      expect(PartieSoiree.appliquer(e, 'jon', {'type': 'ecarter', 'carte': 0}), isNull, reason: 'pas sa propre carte');
      expect(PartieSoiree.appliquer(e, 'inconnu', {'type': 'ecarter', 'carte': 3}), isNull);
      e = PartieSoiree.appliquer(e, 'jon', {'type': 'ecarter', 'carte': 3})!;
      expect(e['tour'], 1);
      e = PartieSoiree.appliquer(e, 'lea', {'type': 'veto', 'carte': 4})!;
      expect(PartieSoiree.appliquer(e, 'jon', {'type': 'ecarter', 'carte': 4}), isNull, reason: 'carte protégée par le Veto');
    });

    test('R24 une partie complète : table, quiz en simultané, film du gagnant', () {
      final hasard = Random(5);
      var e = partie();
      var coups = 0;
      while (e['phase'] == 'table' && coups < 20) {
        final tour = e['tour'] as int;
        final qui = tour == 0 ? 'jon' : 'lea';
        final possibles = [for (var i = 0; i < 6; i++) if (PartieSoiree.peutEcarter(e, i)) i];
        expect(possibles, isNotEmpty);
        e = PartieSoiree.appliquer(e, qui, {'type': 'ecarter', 'carte': possibles[hasard.nextInt(possibles.length)]})!;
        coups++;
      }
      expect(e['phase'], 'quiz');
      for (var q = 0; q < PartieSoiree.nbQuestions; q++) {
        final bonne = ((e['questions'] as List)[q] as Map)['bonne'] as String;
        e = PartieSoiree.appliquer(e, 'jon', {'type': 'reponse', 'question': q, 'choix': bonne})!;
        expect(PartieSoiree.appliquer(e, 'jon', {'type': 'reponse', 'question': q, 'choix': bonne}), isNull, reason: 'une seule réponse');
        e = PartieSoiree.appliquer(e, 'lea', {'type': 'reponse', 'question': q, 'choix': 'faux'})!;
        expect(e['revele'], isTrue);
        e = PartieSoiree.suivante(e);
      }
      expect(e['phase'], 'fin');
      expect(e['points'], [PartieSoiree.nbQuestions, 0]);
      expect(e['gagnant'], 0);
      final film = PartieSoiree.filmDepuisJson((e['film'] as Map).cast<String, dynamic>());
      expect(film.id, startsWith('a'));
    });

    test('R24 de 2 à 4 joueurs : une partie à quatre se termine avec une carte chacun', () {
      final quatre = [for (final n in ['jon', 'lea', 'ines', 'max']) {'id': n, 'pseudo': n, 'profil': 'fidele'}];
      for (var graine = 0; graine < 20; graine++) {
        final hasard = Random(graine);
        var e = PartieSoiree.distribuer(
          quatre,
          [for (var j = 0; j < 4; j++) [for (var i = 0; i < 3; i++) _carte('j$j-$i')]],
          Quiz.tirer(PartieSoiree.nbQuestions, hasard),
          hasard,
        );
        var coups = 0;
        while (e['phase'] == 'table' && coups < 40) {
          final qui = quatre[e['tour'] as int]['id'] as String;
          final veto = [for (var i = 0; i < 12; i++) if (PartieSoiree.peutProteger(e, i)) i];
          final possibles = [for (var i = 0; i < 12; i++) if (PartieSoiree.peutEcarter(e, i)) i];
          expect(possibles, isNotEmpty, reason: 'il y a toujours un coup possible');
          e = veto.isNotEmpty && hasard.nextInt(5) == 0
              ? PartieSoiree.appliquer(e, qui, {'type': 'veto', 'carte': veto.first})!
              : PartieSoiree.appliquer(e, qui, {'type': 'ecarter', 'carte': possibles[hasard.nextInt(possibles.length)]})!;
          coups++;
        }
        expect(e['phase'], 'quiz');
        for (var j = 0; j < 4; j++) {
          expect(PartieSoiree.restantes(e, j), 1);
        }
        // Tout le monde répond : la question se révèle dès la quatrième réponse.
        for (final (k, j) in quatre.indexed) {
          expect(e['revele'], isFalse);
          e = PartieSoiree.appliquer(e, j['id'] as String, {'type': 'reponse', 'question': 0, 'choix': k == 2 ? ((e['questions'] as List)[0] as Map)['bonne'] : 'x'})!;
        }
        expect(e['revele'], isTrue);
        expect((e['points'] as List)[2], 1);
      }
    });

    test('R24 si quelqu\'un ne répond pas, la télé révèle quand même', () {
      var e = partie();
      e['phase'] = 'quiz';
      e = PartieSoiree.appliquer(e, 'jon', {'type': 'reponse', 'question': 0, 'choix': 'x'})!;
      expect(e['revele'], isFalse);
      e = PartieSoiree.suivante(e);
      expect(e['revele'], isTrue);
      e = PartieSoiree.suivante(e);
      expect(e['question'], 1);
    });
  });

  group('R25 L\'historique Letterboxd', () {
    const csv = 'Date,Name,Year,Letterboxd URI,Rating\n'
        '2024-01-02,The Godfather,1972,https://boxd.it/x,5\n'
        '2024-01-03,"Le Bon, la Brute et le Truand",1966,https://boxd.it/y,4.5\n'
        '2024-01-04,"The ""Quoted"" Film",2001,https://boxd.it/z,\n';

    test('R25 le CSV Letterboxd se lit, virgules et guillemets compris', () {
      final films = Historique.lireCsv(csv);
      expect(films.map((f) => f.titre), ['The Godfather', 'Le Bon, la Brute et le Truand', 'The "Quoted" Film']);
      expect(films.first.annee, 1972);
      expect(films.first.note, 5);
      expect(films.last.note, isNull);
    });

    test('R25 un film est reconnu par son titre ou son titre original, à un an près', () {
      final vus = {for (final f in Historique.lireCsv(csv)) Historique.cle(f.titre, f.annee)};
      const parrain = Film(id: 'p', titre: 'Le Parrain', annee: 1972, autresTitres: ['The Godfather']);
      const samourai = Film(id: 's', titre: 'Le Samouraï', annee: 1967);
      expect(Historique.dejaVu(parrain, vus), isTrue);
      expect(Historique.dejaVu(const Film(id: 'b', titre: 'Le bon la brute et le truand', annee: 1967), vus), isTrue);
      expect(Historique.dejaVu(samourai, vus), isFalse);
      expect(Historique.normaliser('Le Samouraï'), Historique.normaliser('Le Samourai'));
    });

    test('R25 les films importés ne sont plus proposés, et ne rapportent aucune case', () async {
      final e = await _etat();
      expect(await e.importerHistorique(Historique.lireCsv(csv)), 3);
      expect(await e.importerHistorique(Historique.lireCsv(csv)), 0, reason: 'pas de doublon');
      final films = await e.source.catalogue();
      final parrain = films.firstWhere((f) => f.titre == 'Le Parrain');
      expect(parrain.dejaVu, isTrue);
      final cartes = Tirage(hasard: Random(1)).tirer(catalogue: films, emotion: Emotion.frissonner, duree: Duree.soiree, profil: Profil.fidele);
      expect(cartes.any((c) => c.film.titre == 'Le Parrain'), isFalse);
      expect(e.billets, isEmpty);
      expect(e.position, 1);
      await e.effacerHistorique();
      expect((await e.source.catalogue()).firstWhere((f) => f.titre == 'Le Parrain').dejaVu, isFalse);
    });
  });

  group('R26 Où voir le film (TMDB, données JustWatch)', () {
    final fournisseurs = jsonEncode({
      'results': {
        'FR': {
          'link': 'https://www.themoviedb.org/movie/238/watch?locale=FR',
          'flatrate': [{'provider_name': 'Netflix'}, {'provider_name': 'Canal+'}],
          'rent': [{'provider_name': 'Apple TV'}],
          'buy': [{'provider_name': 'Google Play Movies'}],
        },
        'US': {'flatrate': [{'provider_name': 'Paramount Plus'}]},
      },
    });

    test('R26 on ne garde que la France, abonnement d\'abord', () {
      final p = Plateformes.depuisJson(jsonDecode(fournisseurs) as Map<String, dynamic>);
      expect(p.abonnement, ['Netflix', 'Canal+']);
      expect(p.resume, 'En abonnement : Netflix, Canal+ · En location : Apple TV');
      expect(Plateformes.depuisJson({'results': {}}).vide, isTrue);
    });

    test('R26 un film sans identifiant TMDB est cherché par titre et année', () async {
      final appels = <String>[];
      final client = MockClient((r) async {
        appels.add(r.url.path);
        if (r.url.path.endsWith('/search/movie')) {
          expect(r.url.queryParameters['year'], '1972');
          expect(r.url.queryParameters['api_key'], 'cle');
          return http.Response(jsonEncode({'results': [{'id': 238}]}), 200);
        }
        return http.Response(fournisseurs, 200);
      });
      final p = await ServicePlateformes('cle', client: client).pour(const Film(id: 'd', titre: 'Le Parrain', annee: 1972));
      expect(p!.abonnement, contains('Netflix'));
      expect(appels, ['/3/search/movie', '/3/movie/238/watch/providers']);
    });

    test('R26 un film Jellyfin donne directement son identifiant TMDB', () async {
      final appels = <String>[];
      final client = MockClient((r) async {
        appels.add(r.url.path);
        return http.Response(fournisseurs, 200);
      });
      await ServicePlateformes('cle', client: client).pour(const Film(id: 'j', titre: 'X', tmdbId: 238, source: SourceFilm.jellyfin));
      expect(appels, ['/3/movie/238/watch/providers']);
      expect(SourceJellyfin.filmDepuisJellyfin({'Id': 'j', 'Name': 'X', 'ProviderIds': {'Tmdb': '238'}}).tmdbId, 238);
    });

    test('R26 si TMDB ne répond pas, rien ne s\'affiche et rien ne plante', () async {
      final client = MockClient((r) async => http.Response('', 500));
      expect(await ServicePlateformes('cle', client: client).pour(const Film(id: 'x', titre: 'Inconnu')), isNull);
    });
  });

  group('R27 Jokers, finale et générique', () {
    test('R27 le Bouclier empêche Pop de prendre la région visée cette semaine-là', () {
      final semaine = CarteDesGenres.semaineDe(DateTime(2026, 11, 4));
      final sans = CarteDesGenres.de(DateTime(2026, 11, 10), const []);
      final avec = CarteDesGenres.de(DateTime(2026, 11, 10), const [], boucliers: {semaine});
      expect(sans.regionsDePop, 1);
      expect(avec.regionsDePop, 0);
      expect(Pop.position(DateTime(2026, 11, 10), const [], boucliers: {semaine}), Pop.position(DateTime(2026, 11, 10), const []) - 1);
    });

    test('R27 un Joker de chaque par mois : Relance et Bouclier', () async {
      final e = await _etat();
      expect(e.relanceDispo, isTrue);
      await e.utiliserRelance();
      expect(e.relanceDispo, isFalse);
      expect(e.bouclierDispo, isTrue);
      await e.poserBouclier();
      expect(e.bouclierDispo, isFalse);
      expect(e.bouclierCetteSemaine, isTrue);
      final moisProchain = await _etat({'relance_2000-01': true});
      expect(moisProchain.relanceDispo, isTrue, reason: 'nouveau mois, nouveaux Jokers');
    });

    test('R27 en fin de mois, le résultat contre Pop est gardé ; devant lui, on est champion', () async {
      final passe = DateTime(maintenant.year, maintenant.month - 1, 10);
      final mois = EtatJeu.moisDe(passe);
      final billet = '{"titre":"T","type":"Envie","pronostic":3,"cases":1,"date":"${passe.toIso8601String()}","verdict":""}';
      final e = await _etat({'mois': mois, 'position': 30, 'billets': [billet]});
      final r = e.resultatDeSaison(passe)!;
      expect(r.$1, 30);
      expect(r.$3, 1);
      expect(r.$2, inInclusiveRange(1, 30));
      expect(e.collection.contains('champion'), r.$1 > r.$2, reason: 'champion seulement devant Pop');
      expect(e.position, 1);
      expect(e.generiqueAVoir, DateTime(passe.year, passe.month, 1));
      await e.generiqueVu(DateTime(passe.year, passe.month, 1));
      expect(e.generiqueAVoir, isNull);
    });

    test('R27 le générique cite les films dans l\'ordre d\'apparition', () {
      final b = [
        Billet(titre: 'Coco', type: 'Envie', pronostic: 3, cases: 1, date: DateTime(2026, 11, 9)),
        Billet(titre: 'Le Samouraï', type: 'Rétro', pronostic: 4, cases: 3, date: DateTime(2026, 11, 2), verdict: 'Froid et parfait', note: 5),
        Billet(titre: 'Hors saison', type: 'Envie', pronostic: 3, cases: 1, date: DateTime(2026, 10, 30)),
      ];
      final l = Generique.lignes(mois: DateTime(2026, 11), billets: b, position: 12, positionDePop: 9, terminee: true);
      expect(l, containsAllInOrder(['La saison de novembre 2026', 'Le Samouraï', 'Coco']));
      expect(l, isNot(contains('Hors saison')));
      expect(l, contains('Meilleur Verdict : « Froid et parfait »'));
      expect(l.any((x) => x.startsWith('Champion de la saison')), isTrue);
      expect(Generique.partage(l), isNot(contains('\n\n')));
    });
  });

  group('R28 Les campagnes', () {
    test('R28 chaque campagne garde les cinq films les mieux notés de son thème', () async {
      final demo = await SourceDemo().catalogue();
      for (final c in Campagnes.liste) {
        final films = Campagnes.films(c, demo);
        expect(films.length, lessThanOrEqualTo(Campagnes.taille));
        expect(films.every(c.garde), isTrue);
        for (var i = 1; i < films.length; i++) {
          expect(films[i - 1].note!, greaterThanOrEqualTo(films[i].note!));
        }
      }
      final monde = Campagnes.films(Campagnes.liste.firstWhere((c) => c.id == 'monde'), demo);
      expect(monde.map((f) => f.pays.first).toSet(), hasLength(monde.length), reason: 'un film par pays');
    });

    test('R28 la campagne avance avec les billets, et se boucle', () async {
      final demo = await SourceDemo().catalogue();
      final c = Campagnes.liste.firstWhere((c) => c.id == 'classiques');
      final films = Campagnes.films(c, demo);
      final billets = [for (final f in films.take(2)) Billet(titre: f.titre, type: 'Campagne', pronostic: 3, cases: 2, date: maintenant)];
      expect(Campagnes.avancee(films, billets), 2);
      expect(Campagnes.terminee(films, billets), isFalse);
      final tous = [for (final f in films) Billet(titre: f.titre, type: 'Campagne', pronostic: 3, cases: 2, date: maintenant)];
      expect(Campagnes.terminee(films, tous), isTrue);
      expect(Campagnes.carte(c, films.first).cases, 2);
    });

    test('R28 boucler une campagne rapporte l\'exploit une seule fois', () async {
      final e = await _etat();
      expect(await e.ajouterExploit('campagne'), isTrue);
      expect(await e.ajouterExploit('campagne'), isFalse);
      expect(e.collection, contains('campagne'));
    });
  });

  group('R29 Cadeau cacheté et Flair', () {
    Cadeau cadeau(String de, int? note, {DateTime? ouvrirLe}) => Cadeau(
          id: '$de$note',
          de: de,
          pour: 'jon',
          film: const Film(id: 'f', titre: 'Coco'),
          ouvrirLe: ouvrirLe ?? DateTime(2026, 11, 6),
          note: note,
        );

    test('R29 un cadeau reste scellé jusqu\'au jour prévu', () {
      final c = cadeau('lea', null, ouvrirLe: DateTime(2026, 11, 13));
      expect(c.ouvrable(DateTime(2026, 11, 12, 23, 59)), isFalse);
      expect(c.ouvrable(DateTime(2026, 11, 13, 0, 1)), isTrue);
      expect(Cadeaux.quand(DateTime(2026, 11, 13), DateTime(2026, 11, 11)), 'à ouvrir vendredi');
      expect(Cadeaux.quand(DateTime(2026, 11, 12), DateTime(2026, 11, 11)), 'à ouvrir demain');
    });

    test('R29 les dates proposées : ce soir, demain, puis vendredi, samedi, dimanche', () {
      final mercredi = DateTime(2026, 11, 11, 18);
      final d = Cadeaux.dates(mercredi);
      expect(d.map((x) => x.$1), ['Ce soir', 'Demain', 'Vendredi', 'Samedi', 'Dimanche']);
      expect(d[2].$2, DateTime(2026, 11, 13));
      final samedi = Cadeaux.dates(DateTime(2026, 11, 14, 18));
      expect(samedi.map((x) => x.$1), ['Ce soir', 'Demain', 'Vendredi'], reason: 'pas de doublon avec ce soir et demain');
    });

    test('R29 le Flair : la part des cadeaux notés 4 ou 5, les cadeaux pas encore notés ne comptent pas', () {
      final f = Cadeaux.flair([cadeau('lea', 5), cadeau('lea', 2), cadeau('lea', 4), cadeau('lea', null), cadeau('max', 3)]);
      expect(f['lea'], (2, 3));
      expect(Cadeaux.pourcentage(f['lea']!), '67 %');
      expect(f['max'], (0, 1));
      expect(f.containsKey('jon'), isFalse);
    });

    test('R29 jouer un cadeau ouvert rapporte 2 cases, comme une carte', () {
      final carte = Cadeaux.carte(cadeau('lea', null), 'Léa');
      expect(carte.type, TypeCarte.cadeau);
      expect(carte.cases, 2);
      expect(carte.defi, 'Cadeau de Léa');
    });
  });

  group('R30 Les cartes suivent l\'envie', () {
    test('R30 chaque envie donne d\'autres défis et seulement des films de ses genres', () {
      final catalogue = [
        for (var i = 0; i < 6; i++) _film('rire$i', note: 7.8, annee: 1950 + i * 12, pays: ['Pays$i'], genres: const ['Comedy']),
        for (var i = 0; i < 6; i++) _film('peur$i', note: 7.8, annee: 1950 + i * 12, pays: ['Pays$i'], genres: const ['Horror']),
      ];
      final rire = Tirage(hasard: Random(1)).tirer(catalogue: catalogue, emotion: Emotion.rire, duree: Duree.soiree, profil: Profil.fidele);
      final peur = Tirage(hasard: Random(1)).tirer(catalogue: catalogue, emotion: Emotion.frissonner, duree: Duree.soiree, profil: Profil.fidele);
      expect(rire.every((c) => c.film.id.startsWith('rire')), isTrue);
      expect(peur.every((c) => c.film.id.startsWith('peur')), isTrue);
      expect(rire.every((c) => c.defi.contains('pour rire')), isTrue);
      expect(peur.every((c) => c.defi.contains('frissonner')), isTrue);
    });

    test('R30 un pays déjà vu ne fait pas une carte Voyage', () {
      final catalogue = [_film('a', note: 7, annee: 2000, pays: const ['France'], genres: const ['Comedy'])];
      final cartes = Tirage(hasard: Random(1)).tirer(catalogue: catalogue, emotion: Emotion.rire, duree: Duree.soiree, profil: Profil.fidele, paysVus: {'France'});
      expect(cartes.any((c) => c.type == TypeCarte.voyage), isFalse);
    });
  });

  group('R31 Juste un film', () {
    final catalogue = [
      for (var i = 0; i < 12; i++) _film('ok$i', note: 7 + i / 10, annee: 1950 + i * 6, genres: const ['Comedy']),
      _film('navet', note: 5.5, genres: const ['Comedy']),
      _film('vu', vu: true, genres: const ['Comedy']),
    ];

    test('R31 trois idées, jamais de navet ni de film déjà vu, même sans envie', () {
      final choix = JusteUnFilm(hasard: Random(1));
      for (var tour = 0; tour < 10; tour++) {
        final idees = choix.proposer(catalogue, duree: Duree.soiree);
        expect(idees, hasLength(3));
        expect(idees.map((f) => f.id).toSet(), hasLength(3));
        expect(idees.any((f) => f.id == 'navet' || f.id == 'vu'), isFalse);
      }
    });

    test('R31 on change autant qu\'on veut : rien ne revient avant d\'avoir tout vu', () {
      final choix = JusteUnFilm(hasard: Random(2));
      final vus = <String>{};
      for (var tour = 0; tour < 4; tour++) {
        final idees = choix.proposer(catalogue, duree: Duree.soiree);
        expect(idees.any((f) => vus.contains(f.id)), isFalse, reason: 'tour $tour');
        vus.addAll(idees.map((f) => f.id));
      }
      expect(vus, hasLength(12));
      // Le cinquième tour recommence la boucle au lieu de s'arrêter.
      expect(choix.proposer(catalogue, duree: Duree.soiree), hasLength(3));
    });

    test('R31 « Une autre idée » ne change que la carte touchée', () {
      final choix = JusteUnFilm(hasard: Random(3));
      final avant = choix.proposer(catalogue, duree: Duree.soiree);
      final apres = choix.remplacer(catalogue, avant, 1, duree: Duree.soiree);
      expect(apres[0].id, avant[0].id);
      expect(apres[2].id, avant[2].id);
      expect(apres[1].id, isNot(avant[1].id));
      expect(apres.map((f) => f.id).toSet(), hasLength(3));
    });

    test('R31 l\'époque et la durée filtrent', () {
      final idees = JusteUnFilm(hasard: Random(4)).proposer(catalogue, duree: Duree.soiree, epoque: Epoque.classique);
      expect(idees, isNotEmpty);
      expect(idees.every((f) => f.annee! < 1980), isTrue);
      final courts = JusteUnFilm().proposer([_film('long', duree: 200, genres: const ['Comedy'])], duree: Duree.courte);
      expect(courts, isEmpty);
    });

    test('R31 hors du jeu : rien ne bouge sur le plateau', () async {
      SharedPreferences.setMockInitialValues({});
      final etat = EtatJeu(await SharedPreferences.getInstance());
      JusteUnFilm().proposer(await SourceDemo().catalogue(), duree: Duree.soiree);
      expect(etat.billets, isEmpty);
      expect(etat.enCours, isEmpty);
      expect(etat.position, 1);
    });
  });

  group('R32 Jamais d\'impasse, des envies cohérentes', () {
    test('R32 une comédie de guerre ne fait pas « réfléchir », un dessin animé familial ne fait pas « frissonner »', () {
      final vadrouille = _film('v', genres: const ['Comedy', 'War']);
      final toy = _film('t', genres: const ['Animation', 'Comedy', 'Family']);
      final bachir = _film('b', genres: const ['Animation', 'Documentary', 'War']);
      expect(Tirage.correspond(vadrouille, Emotion.reflechir, Duree.soiree), isFalse);
      expect(Tirage.correspond(vadrouille, Emotion.rire, Duree.soiree), isTrue);
      expect(Tirage.correspond(toy, Emotion.frissonner, Duree.soiree), isFalse);
      expect(Tirage.correspond(toy, Emotion.evader, Duree.soiree), isTrue);
      expect(Tirage.correspond(bachir, Emotion.reflechir, Duree.soiree), isTrue);
      expect(Tirage.correspond(bachir, Emotion.evader, Duree.soiree), isFalse);
    });

    test('R32 la sélection de démonstration a trois cartes pour chaque envie et chaque durée', () async {
      final catalogue = await SourceDemo().catalogue();
      for (final e in Emotion.values) {
        for (final d in Duree.values) {
          final cartes = Tirage(hasard: Random(1)).tirer(catalogue: catalogue, emotion: e, duree: d, profil: Profil.fidele);
          expect(cartes, hasLength(3), reason: '${e.name} / ${d.name}');
        }
      }
    });

    test('R32 trop court : Pop allonge la durée et le dit', () {
      final catalogue = [for (var i = 0; i < 4; i++) _film('doc$i', duree: 110, annee: 1990 + i, pays: ['P$i'], genres: const ['Documentary'])];
      final t = Tirage(hasard: Random(1)).tirerSansImpasse(catalogue: catalogue, emotion: Emotion.reflechir, duree: Duree.courte, profil: Profil.fidele);
      expect(t.cartes, hasLength(3));
      expect(t.message, contains('plus longs'));
    });

    test('R32 aucune envie possible : de vraies cartes quand même, jamais de navet', () {
      final catalogue = [for (var i = 0; i < 4; i++) _film('rire$i', duree: 85, pays: ['P$i'], genres: const ['Comedy']), _film('navet', note: 4, genres: const ['Documentary'])];
      final t = Tirage(hasard: Random(1)).tirerSansImpasse(catalogue: catalogue, emotion: Emotion.reflechir, duree: Duree.courte, profil: Profil.fidele);
      expect(t.cartes, isNotEmpty);
      expect(t.cartes.every((c) => c.film.id.startsWith('rire')), isTrue);
      expect(t.message, isNotNull);
    });

    test('R32 tout va bien : pas de message', () async {
      final t = Tirage(hasard: Random(1)).tirerSansImpasse(catalogue: await SourceDemo().catalogue(), emotion: Emotion.rire, duree: Duree.moyenne, profil: Profil.fidele);
      expect(t.cartes, hasLength(3));
      expect(t.message, isNull);
    });
  });

  group('R33 Tout le cinéma de VJOD', () {
    final reponse = jsonEncode({
      'results': [
        {'id': 550, 'title': 'Fight Club', 'original_title': 'Fight Club', 'release_date': '1999-10-15', 'vote_average': 8.4, 'vote_count': 30000, 'genre_ids': [18, 53], 'overview': 'Un employé de bureau insomniaque rencontre un vendeur de savon.'},
        {'id': 680, 'title': 'Pulp Fiction', 'original_title': 'Pulp Fiction', 'release_date': '1994-09-10', 'vote_average': 8.5, 'vote_count': 28000, 'genre_ids': [53, 80], 'overview': ''},
        {'id': 999, 'title': '', 'vote_average': 9},
      ],
    });

    test('R33 TMDB est interrogé sans navet, avec l\'envie et la durée', () async {
      final appels = <Uri>[];
      final client = MockClient((r) async {
        appels.add(r.url);
        return http.Response.bytes(utf8.encode(reponse), 200);
      });
      final films = await SourceTmdb('cle', client: client, hasard: Random(1)).catalogue(emotion: Emotion.frissonner, duree: Duree.courte);
      expect(appels, hasLength(2));
      final q = appels.first.queryParameters;
      expect(q['vote_average.gte'], '6');
      expect(int.parse(q['vote_count.gte']!), greaterThanOrEqualTo(150));
      expect(q['with_runtime.lte'], '90');
      expect(q['language'], 'fr-FR');
      expect(q['with_genres']!.split('|'), containsAll(['53', '27', '9648', '80']));
      expect(q['without_genres']!.split(','), containsAll(['35', '10751', '16']));
      expect(films.map((f) => f.titre), unorderedEquals(['Fight Club', 'Pulp Fiction']));
      final fc = films.firstWhere((f) => f.tmdbId == 550);
      expect(fc.source, SourceFilm.catalogueVjod);
      expect(fc.annee, 1999);
      expect(fc.genres, ['Drama', 'Thriller']);
      expect(Tirage.assezBon(fc), isTrue);
    });

    test('R33 « toute la soirée » ne limite pas la durée', () {
      expect(SourceTmdb.parametres(duree: Duree.soiree, page: 1).containsKey('with_runtime.lte'), isFalse);
    });

    test('R33 un film du serveur passe avant sa version TMDB, et TMDB en panne ne bloque rien', () async {
      final serveur = _SourceFixe([const Film(id: 'jf1', titre: 'Fight Club', tmdbId: 550, note: 8.4, source: SourceFilm.jellyfin)]);
      final tmdb = _SourceFixe([
        const Film(id: 'tmdb:550', titre: 'Fight Club', tmdbId: 550, note: 8.4, source: SourceFilm.catalogueVjod),
        const Film(id: 'tmdb:680', titre: 'Pulp Fiction', tmdbId: 680, note: 8.5, source: SourceFilm.catalogueVjod),
      ]);
      final tout = await SourceToutVjod(serveur, tmdb).catalogue();
      expect(tout.map((f) => f.id), ['jf1', 'tmdb:680']);
      final enPanne = await SourceToutVjod(serveur, _SourceEnPanne()).catalogue();
      expect(enPanne.map((f) => f.id), ['jf1']);
    });

    test('R33 « Lancer dans VJOD » ouvre la fiche du titre quand il n\'est pas sur le serveur', () {
      const f = Film(id: 'tmdb:680', titre: 'Pulp Fiction', tmdbId: 680, source: SourceFilm.catalogueVjod);
      final lien = VjodLien.pour(f);
      expect(lien.scheme, 'moonfin');
      expect(lien.host, 'tmdb');
      expect(lien.queryParameters, {'id': '680', 'type': 'movie', 'title': 'Pulp Fiction'});
      const jf = Film(id: 'abc', titre: 'X', serveurId: 's', source: SourceFilm.jellyfin);
      expect(VjodLien.pour(jf).host, 'play');
    });
  });

  group('R34 Ma TV dit à l\'avance : en VOD ou à demander', () {
    const connexion = ConnexionJellyfin(adresse: 'http://jf', utilisateurId: 'u1', jeton: 'jeton-jf');
    String description(Map<String, String> j) => 'Sources TV de VJOD.\nVJOD-TV:${base64Url.encode(utf8.encode(jsonEncode(j))).replaceAll('=', '')}';
    final collection = jsonEncode({
      'Items': [
        {'Name': 'VJOD – réglages', 'Overview': 'VJOD-CONFIG:abc'},
        {'Name': 'VJOD – TV', 'Overview': description({'v': '1', 'url': 'https://seedbox.example/iptv-checker/', 'key': 'commune'})},
      ],
    });
    http.Response jf() => http.Response(collection, 200, headers: {'content-type': 'application/json; charset=utf-8'});
    Film horsServeur(int id) => Film(id: 'tmdb:$id', titre: 'Film $id', tmdbId: id, note: 8, source: SourceFilm.catalogueVjod);

    test('R34 l\'adresse de Ma TV se lit dans la collection « VJOD – TV »', () {
      final s = ServeurMaTv.depuisDescription(description({'url': 'https://seedbox.example/iptv-checker/', 'key': 'abc_DEF-123'}))!;
      expect(s.adresse, 'https://seedbox.example/iptv-checker');
      expect(s.cle, 'abc_DEF-123');
      expect(s.point('/tv/api/vod/tmdb', {'kind': 'movie'}).toString(), 'https://seedbox.example/iptv-checker/tv/api/vod/tmdb?kind=movie&k=abc_DEF-123');
      expect(ServeurMaTv.depuisDescription('Pas de marqueur ici'), isNull);
      expect(ServeurMaTv.depuisDescription('VJOD-TV:@@@'), isNull);
      expect(ServeurMaTv.depuisDescription(description({'url': 'pas une adresse', 'key': 'k'})), isNull);
    });

    test('R34 avec sa clé de profil, Ma TV marque chaque film hors serveur', () async {
      final demandes = <http.Request>[];
      final client = MockClient((r) async {
        demandes.add(r);
        if (r.url.host == 'jf') {
          expect(r.headers['Authorization'], contains('Token="jeton-jf"'));
          expect(r.url.queryParameters['IncludeItemTypes'], 'BoxSet');
          expect(r.url.queryParameters['Fields'], 'Overview');
          return jf();
        }
        if (r.url.path.endsWith('/tv/api/enroll')) {
          expect(r.method, 'POST');
          expect(r.url.queryParameters['k'], 'commune');
          expect(jsonDecode(r.body), {'token': 'jeton-jf'});
          return http.Response(jsonEncode({'key': 'perso'}), 200);
        }
        expect(r.url.path, '/iptv-checker/tv/api/vod/tmdb');
        expect(r.url.queryParameters, {'kind': 'movie', 'ids': '550,680', 'k': 'perso'});
        return http.Response(jsonEncode({'550': [{'id': '9', 'name': 'Fight Club'}], '680': []}), 200);
      });
      const serveur = Film(id: 'jf1', titre: 'Sur le serveur', tmdbId: 13, source: SourceFilm.jellyfin);
      final films = await SourceAvecMaTv(_SourceFixe([horsServeur(550), horsServeur(680), serveur]), MaTv(connexion, client: client)).catalogue();
      expect(films.map((f) => f.enVod), [true, false, null]);
      expect(films[0].titre, 'Film 550');
      expect(demandes.length, 3);
    });

    test('R34 un Ma TV ancien garde la clé commune, 150 films par demande, réponses gardées', () async {
      final lots = <int>[];
      final client = MockClient((r) async {
        if (r.url.host == 'jf') return jf();
        if (r.url.path.endsWith('/tv/api/enroll')) return http.Response('', 404);
        expect(r.url.queryParameters['k'], 'commune');
        final ids = r.url.queryParameters['ids']!.split(',');
        lots.add(ids.length);
        return http.Response(jsonEncode({for (final id in ids) id: int.parse(id).isEven ? [{'id': id}] : []}), 200);
      });
      final maTv = MaTv(connexion, client: client);
      final films = [for (var i = 1; i <= 200; i++) horsServeur(i)];
      final marques = await maTv.marquer(films);
      expect(lots, [150, 50]);
      expect(marques.where((f) => f.enVod == true).length, 100);
      expect(marques.every((f) => f.enVod != null), isTrue);
      await maTv.marquer(films);
      expect(lots, [150, 50], reason: 'Ma TV n\'est pas redemandé pour des films déjà connus');
    });

    test('R34 Ma TV absent, coupé ou en panne : rien ne casse, on ne sait rien', () async {
      Future<List<Film>> avec(Future<http.Response> Function(http.Request) repondre) =>
          MaTv(connexion, client: MockClient(repondre)).marquer([horsServeur(550)]);
      // Pas de collection « VJOD – TV ».
      var films = await avec((r) async => http.Response(jsonEncode({'Items': []}), 200));
      expect(films.single.enVod, isNull);
      // Jellyfin injoignable.
      films = await avec((r) async => throw Exception('hors ligne'));
      expect(films.single.enVod, isNull);
      // L'administrateur a coupé ce profil : Ma TV n'est pas interrogé.
      var vod = 0;
      films = await avec((r) async {
        if (r.url.host == 'jf') return jf();
        if (r.url.path.endsWith('/tv/api/enroll')) return http.Response('', 403);
        vod++;
        return http.Response('{}', 200);
      });
      expect(films.single.enVod, isNull);
      expect(vod, 0);
      // Ma TV en panne.
      films = await avec((r) async {
        if (r.url.host == 'jf') return jf();
        if (r.url.path.endsWith('/tv/api/enroll')) return http.Response('', 404);
        return http.Response('erreur', 500);
      });
      expect(films.single.enVod, isNull);
    });

    test('R34 « Où le voir » dit ce que Ma TV a répondu, et la soirée s\'en souvient', () {
      expect(OuLeVoir.ligneVjod(horsServeur(1).avecVod(true)), 'Dans VJOD : en VOD, prêt à lancer');
      expect(OuLeVoir.ligneVjod(horsServeur(1).avecVod(false)), 'Dans VJOD : pas en VOD, à demander');
      expect(OuLeVoir.ligneVjod(horsServeur(1)), 'Dans VJOD : en VOD tout de suite, ou à demander');
      final relu = PartieSoiree.filmDepuisJson(jsonDecode(jsonEncode(PartieSoiree.filmVersJson(horsServeur(7).avecVod(false)))) as Map<String, dynamic>);
      expect(relu.enVod, isFalse);
      expect(relu.tmdbId, 7);
      expect(horsServeur(7).avecVod(true).vu().enVod, isTrue);
    });
  });

  group('R35 Mise à jour automatique', () {
    final installee = DateTime.utc(2026, 11, 6, 10);
    Map<String, dynamic> release(String publiee, {String corps = '', String nom = 'aura.apk'}) => {
          'tag_name': 'derniere',
          'body': corps,
          'assets': [
            {'name': nom, 'updated_at': publiee, 'size': 42000000, 'browser_download_url': 'https://github.com/ruizjonathan1988-web/Aura-/releases/download/derniere/$nom'},
          ],
        };

    test('R35 un APK publié après l\'installation est proposé, avec ce qui change', () {
      final v = MiseAJour.depuisRelease(
        release('2026-11-06T13:32:00Z', corps: 'Aura, le jeu de société du cinéma.\n\nCe qui change :\n- Mise à jour automatique\n- \n'),
        installee,
      )!;
      expect(v.adresse.toString(), endsWith('/derniere/aura.apk'));
      expect(v.nouveautes, ['Mise à jour automatique']);
      expect(v.taille, 42000000);
      expect(v.publieeLe, DateTime.utc(2026, 11, 6, 13, 32));
    });

    test('R35 à jour, APK manquant ou réponse bizarre : rien n\'est proposé', () {
      // Publié juste avant l'installation (la marge de deux minutes).
      expect(MiseAJour.depuisRelease(release('2026-11-06T10:01:30Z'), installee), isNull);
      expect(MiseAJour.depuisRelease(release('2026-11-05T22:00:00Z'), installee), isNull);
      expect(MiseAJour.depuisRelease(release('2026-11-06T13:00:00Z', nom: 'autre.apk'), installee), isNull);
      expect(MiseAJour.depuisRelease({'message': 'Not Found'}, installee), isNull);
      expect(MiseAJour.depuisRelease('pas un objet', installee), isNull);
      expect(MiseAJour.nouveautesDepuis('Sans rubrique'), isEmpty);
    });

    test('R35 sans le canal Android, la vérification ne casse rien', () async {
      // Ici (tests), le canal Android n'existe pas : jamais d'erreur, rien de proposé.
      expect(await MiseAJour.verifier(forcer: true), isNull);
    });
  });

  group('R36 Les époques par décennie', () {
    test('R36 depuis 2000, une époque par décennie', () {
      expect(Epoque.values.map((e) => e.libelle), ['Peu importe', 'Avant 1980', 'Années 80 et 90', 'Années 2000', 'Années 2010', 'Années 2020']);
      expect(Epoque.annees2000.contient(2009), isTrue);
      expect(Epoque.annees2000.contient(2010), isFalse);
      expect(Epoque.annees2010.contient(2010), isTrue);
      expect(Epoque.annees2010.contient(2019), isTrue);
      expect(Epoque.annees2020.contient(2019), isFalse);
      expect(Epoque.annees2020.contient(2025), isTrue);
      expect(Epoque.annees2020.contient(null), isFalse);
      expect(Epoque.toutes.contient(null), isTrue);
    });

    test('R36 TMDB et Jellyfin ne cherchent que dans la décennie choisie', () async {
      final q = SourceTmdb.parametres(epoque: Epoque.annees2010, page: 1);
      expect(q['primary_release_date.gte'], '2010-01-01');
      expect(q['primary_release_date.lte'], '2019-12-31');
      expect(SourceTmdb.parametres(epoque: Epoque.annees2020, page: 1).containsKey('primary_release_date.lte'), isFalse);
      expect(SourceTmdb.parametres(page: 1).containsKey('primary_release_date.gte'), isFalse);

      late Uri appel;
      final client = MockClient((r) async {
        appel = r.url;
        return http.Response('{"Items": []}', 200);
      });
      await SourceJellyfin(const ConnexionJellyfin(adresse: 'https://vjod.exemple.fr', utilisateurId: 'u7', jeton: 'j'), client: client)
          .catalogue(epoque: Epoque.annees2000);
      expect(appel.queryParameters['MinPremiereDate'], '2000-01-01T00:00:00Z');
      expect(appel.queryParameters['MaxPremiereDate'], '2009-12-31T23:59:59Z');
    });

    test('R36 la sélection de démonstration a trois idées pour chaque décennie', () async {
      final films = await SourceDemo().catalogue();
      for (final e in Epoque.values) {
        final idees = JusteUnFilm(hasard: Random(2)).proposer(films, duree: Duree.soiree, epoque: e);
        expect(idees, hasLength(3), reason: e.libelle);
        expect(idees.every((f) => e.contient(f.annee)), isTrue, reason: e.libelle);
      }
    });
  });

  group('R37 Tu te mets combien ?', () {
    test('R37 le niveau annoncé donne les cases : 1 à 3 : 1, 4 à 6 : 2, 7 à 9 : 3, 10 : 4', () {
      expect([for (var n = 1; n <= 10; n++) Niveau.cases(n)], [1, 1, 1, 2, 2, 2, 3, 3, 3, 4]);
      expect(Niveau.nom(2), 'Tranquille');
      expect(Niveau.nom(5), 'Curieux');
      expect(Niveau.nom(8), 'Audacieux');
      expect(Niveau.nom(10), 'Coup d\'audace');
    });

    test('R37 un film connu et récent est facile, un film rare, ancien et lointain est difficile', () {
      final facile = _film('f', annee: 2015, votes: 30000, pays: const ['États-Unis'], duree: 110);
      final rare = _film('r', annee: 1953, votes: 800, pays: const ['Japon'], duree: 160);
      expect(Niveau.de(facile), 1);
      expect(Niveau.de(rare), 10);
      expect(Niveau.de(_film('m', annee: 1975, votes: 3000, pays: const ['Italie'])), inInclusiveRange(4, 8));
    });

    test('R37 le tirage suit le niveau, et chaque carte rapporte les cases du niveau', () {
      final faciles = [for (var i = 0; i < 12; i++) _film('f$i', annee: 2015, votes: 30000, pays: const ['États-Unis'])];
      final rares = [for (var i = 0; i < 12; i++) _film('r$i', annee: 1955 + i, votes: 800, pays: const ['Japon'], duree: 160)];
      final catalogue = [...faciles, ...rares];
      final haut = Tirage(hasard: Random(3)).tirer(catalogue: catalogue, emotion: Emotion.frissonner, duree: Duree.soiree, profil: Profil.fidele, niveau: 9);
      expect(haut, hasLength(3));
      expect(haut.every((c) => c.film.id.startsWith('r')), isTrue);
      expect(haut.every((c) => c.cases == 3 && c.niveau == 9), isTrue);
      expect(haut.first.joker, contains('Tu t\'es mis 9'));
      final bas = Tirage(hasard: Random(3)).tirer(catalogue: catalogue, emotion: Emotion.frissonner, duree: Duree.soiree, profil: Profil.fidele, niveau: 2);
      expect(bas.every((c) => c.film.id.startsWith('f') && c.cases == 1), isTrue);
      // Sans niveau (Duel, soirée entre amis), les cartes gardent leurs cases.
      final libre = Tirage(hasard: Random(3)).tirer(catalogue: catalogue, emotion: Emotion.frissonner, duree: Duree.soiree, profil: Profil.fidele);
      expect(libre.every((c) => c.niveau == null), isTrue);
      expect(libre.firstWhere((c) => c.type == TypeCarte.retro).cases, 3);
    });

    test('R37 en solo, Aura propose un niveau d\'après les séances, sans l\'imposer', () {
      expect(Niveau.propose(reussis: const []), 3);
      expect(Niveau.propose(reussis: const [5, 5, 5]), 6, reason: 'deux réussites à ce niveau : un cran de plus');
      expect(Niveau.propose(reussis: const [6, 4]), 5);
      expect(Niveau.propose(reussis: const [5, 5], abandonnes: const [7]), 5, reason: 'abandon au-dessus : un cran de moins');
      expect(Niveau.propose(reussis: const [10, 10, 10]), 10);
      expect(Niveau.propose(reussis: const [], abandonnes: const [2]), 1);
    });

    test('R37 le niveau suit la séance jusqu\'au billet, et le 10 donne le trophée Coup d\'audace', () async {
      final e = await _etat();
      final carte = CarteDefi(type: TypeCarte.envie, defi: 'Défi', indice: '', cases: Niveau.cases(10), joker: '', film: _film('a'), bulleDePop: '', niveau: 10);
      await e.commencerSeance(carte, pronostic: 4);
      expect(e.enCours.single.niveau, 10);
      expect(SeanceEnCours.depuisJson(e.enCours.single.versJson()).niveau, 10);
      expect(await e.validerEnCours(e.enCours.single, note: 4), 4);
      expect(e.billets.single.niveau, 10);
      expect(Billet.depuisJson(e.billets.single.versJson()).niveau, 10);
      expect(e.collection, contains('audace'));
      expect(e.niveauPropose, 10);
    });

    test('R37 un abandon fait redescendre la proposition', () async {
      final e = await _etat();
      CarteDefi carte(String id, int n) => CarteDefi(type: TypeCarte.envie, defi: 'Défi', indice: '', cases: Niveau.cases(n), joker: '', film: _film(id), bulleDePop: '', niveau: n);
      await e.validerSeance(carte('a', 5), pronostic: 4);
      expect(e.niveauPropose, 5);
      await e.commencerSeance(carte('b', 5), pronostic: 4);
      await e.abandonnerSeance(e.enCours.single);
      expect(e.niveauPropose, 4);
    });
  });

  group('R38 Viser haut : plus fort, mais risqué', () {
    CarteDefi carte(String id, int n) =>
        CarteDefi(type: TypeCarte.envie, defi: 'Défi', indice: '', cases: Niveau.cases(n), joker: '', film: _film(id), bulleDePop: '', niveau: n);

    test('R38 le 10 est le seul à dépasser le plafond du jour', () async {
      expect(Regles.casesAccordees(demandees: 4, dejaGagneesAujourdhui: 0), 3);
      expect(Regles.casesAccordees(demandees: 4, dejaGagneesAujourdhui: 0, plafond: Niveau.plafond(10)), 4);
      final e = await _etat();
      expect(await e.validerSeance(carte('a', 10), pronostic: 4), 4);
      expect(e.position, 5);
      final f = await _etat();
      expect(await f.validerSeance(carte('a', 7), pronostic: 4), 3);
      expect(await f.validerSeance(carte('b', 10), pronostic: 4), 1, reason: 'déjà 3 cases ce jour : il en reste une sous le plafond du 10');
      expect(await f.validerSeance(carte('c', 9), pronostic: 4), 0);
    });

    test('R38 abandonner un 9 coûte une case, un 10 deux cases, en dessous rien', () async {
      final e = await _etat({'position': 10});
      for (final (id, n, perte) in [('a', 8, 0), ('b', 9, 1), ('c', 10, 2), ('d', 3, 0)]) {
        await e.commencerSeance(carte(id, n), pronostic: 4);
        expect(await e.abandonnerSeance(e.enCours.first), perte, reason: 'niveau $n');
      }
      expect(e.position, 7);
      // Jamais sous la case de départ.
      final f = await _etat();
      await f.commencerSeance(carte('z', 10), pronostic: 4);
      expect(await f.abandonnerSeance(f.enCours.single), 0);
      expect(f.position, 1);
    });

    test('R38 l\'audace du mois : le niveau de chaque billet, doublé à 9 et 10', () async {
      expect([for (var n = 1; n <= 10; n++) Niveau.audace(n)], [1, 2, 3, 4, 5, 6, 7, 8, 18, 20]);
      final e = await _etat(_devantPop);
      await e.validerSeance(carte('a', 5), pronostic: 4);
      await e.validerSeance(carte('b', 10), pronostic: 4);
      await e.validerSeance(_carte('c'), pronostic: 4);
      expect(e.audaceDuMois, 25);
      expect(Niveau.risque(5), 'Aucun risque.');
      expect(Niveau.risque(10), contains('deux cases'));
    });
  });

  group('R39 Les pouvoirs des pions', () {
    CarteDefi carte(String id, {int cases = 1, int duree = 100, int? niveau}) => CarteDefi(
        type: TypeCarte.envie, defi: 'Défi', indice: '', cases: cases, joker: '', film: _film(id, duree: duree), bulleDePop: '', niveau: niveau);

    test('R39 une charge par semaine, plus une par tranche de 20 points d\'audace du mois', () {
      final m = DateTime(2026, 11, 18); // un mercredi
      expect(Pouvoirs.charges(maintenant: m, usages: const [], audaceDuMois: 0), 1);
      expect(Pouvoirs.charges(maintenant: m, usages: const [], audaceDuMois: 45), 3);
      expect(Pouvoirs.charges(maintenant: m, usages: [UsagePouvoir(DateTime(2026, 11, 16))], audaceDuMois: 45), 2, reason: 'la charge de la semaine a servi lundi');
      expect(Pouvoirs.charges(maintenant: m, usages: [UsagePouvoir(DateTime(2026, 11, 15))], audaceDuMois: 0), 1, reason: 'dimanche, c\'était la semaine d\'avant');
      expect(Pouvoirs.charges(maintenant: m, usages: [UsagePouvoir(DateTime(2026, 11, 2), audace: true)], audaceDuMois: 20), 1);
      expect(Pouvoirs.charges(maintenant: m, usages: [UsagePouvoir(DateTime(2026, 10, 30), audace: true)], audaceDuMois: 20), 2, reason: 'une charge d\'audace d\'octobre ne compte pas en novembre');
      expect(UsagePouvoir.depuisTexte(UsagePouvoir(m, audace: true).versTexte())!.audace, isTrue);
    });

    test('R39 chaque pouvoir vaut une case, et seulement si sa condition est remplie', () {
      expect(Pouvoirs.bonus(Profil.degustateur, pronostic: 3, note: 2), 1);
      expect(Pouvoirs.bonus(Profil.degustateur, pronostic: 3), 0);
      expect(Pouvoirs.bonus(Profil.critique, pronostic: 4, note: 4), 1);
      expect(Pouvoirs.bonus(Profil.critique, pronostic: 4, note: 3), 1, reason: 'équilibrage R45 : à un cran près');
      expect(Pouvoirs.bonus(Profil.critique, pronostic: 4, note: 2), 0);
      expect(Pouvoirs.bonus(Profil.presse, pronostic: 3, dureeMinutes: 85), 1);
      expect(Pouvoirs.bonus(Profil.presse, pronostic: 3, dureeMinutes: 90), 0);
      expect(Pouvoirs.bonus(Profil.hote, pronostic: 3, aPlusieurs: true), 1);
      expect(Pouvoirs.bonus(Profil.hote, pronostic: 3), 0);
      expect(Pouvoirs.bonus(Profil.supporter, pronostic: 3, derrierePop: true), 1);
      expect(Pouvoirs.bonus(Profil.supporter, pronostic: 3), 0);
      expect(Pouvoirs.bonus(Profil.devoreur, pronostic: 3, note: 3), 0, reason: 'le Marathon relève le plafond, il n\'ajoute rien');
      expect(Pouvoirs.plafond(Profil.devoreur, 3), 4);
      expect(Pouvoirs.plafond(Profil.devoreur, 4), 4);
      expect(Pouvoirs.plafond(Profil.critique, 3), 3);
      expect(Pouvoirs.cartesAuTirage(Profil.explorateur), 4);
      expect(Pouvoirs.revoir(Profil.fidele), isTrue);
      expect(Profil.supporter.pouvoir, 'Remontada');
      expect(Profil.values.map((p) => p.effet).every((t) => t.startsWith('Une fois armé')), isTrue);
    });

    test('R39 armé, le pouvoir agit au billet suivant puis la charge part', () async {
      final e = await _etat({'profil': 'degustateur'});
      expect(e.chargesPouvoir, 1);
      expect(await e.armerPouvoir(), isTrue);
      expect(await e.armerPouvoir(), isFalse);
      expect(await e.validerSeance(carte('a'), pronostic: 3, note: 4), 2);
      expect(e.pouvoirArme, isFalse);
      expect(e.chargesPouvoir, 0);
      expect(await e.armerPouvoir(), isFalse);
      // Sans pouvoir armé, rien de plus.
      expect(await e.validerSeance(carte('b'), pronostic: 3, note: 4), 1);
    });

    test('R39 la charge part même si la condition n\'est pas remplie ; désarmer la garde', () async {
      final e = await _etat({'profil': 'critique'});
      await e.armerPouvoir();
      await e.desarmerPouvoir();
      expect(e.chargesPouvoir, 1, reason: 'désarmé avant d\'agir : rien n\'est perdu');
      await e.armerPouvoir();
      expect(await e.validerSeance(carte('a'), pronostic: 4, note: 2), 1);
      expect(e.chargesPouvoir, 0);
      expect(e.motDePop, contains('Plume'));
    });

    test('R39 l\'audace recharge : un 10 réussi donne une charge de plus', () async {
      final e = await _etat({..._devantPop, 'profil': 'degustateur'});
      await e.validerSeance(carte('a', cases: Niveau.cases(10), niveau: 10), pronostic: 3);
      expect(e.audaceDuMois, 20);
      expect(e.chargesPouvoir, 2);
    });

    test('R39 Marathon : plafond à 4 pour ce billet seulement ; les bonus restent sous le plafond', () async {
      final e = await _etat({'profil': 'devoreur'});
      expect(await e.validerSeance(carte('a', cases: 3), pronostic: 3), 3);
      await e.armerPouvoir();
      expect(await e.validerSeance(carte('b', cases: 2), pronostic: 3), 1);
      expect(await e.validerSeance(carte('c', cases: 2), pronostic: 3), 0);
      final f = await _etat({'profil': 'degustateur'});
      expect(await f.validerSeance(carte('a', cases: 3), pronostic: 3), 3);
      await f.armerPouvoir();
      expect(await f.validerSeance(carte('b'), pronostic: 3, note: 5), 0, reason: 'Slow ne perce pas le plafond de 3');
    });

    test('R39 Court-métrage et Projectionniste suivent la séance en cours', () async {
      final e = await _etat({'profil': 'hote'});
      await e.armerPouvoir();
      await e.commencerSeance(carte('a', duree: 80), pronostic: 3, aPlusieurs: true);
      final s = SeanceEnCours.depuisJson(e.enCours.single.versJson());
      expect(s.aPlusieurs, isTrue);
      expect(s.dureeMinutes, 80);
      expect(await e.validerEnCours(s, note: 3), 2);
      final f = await _etat({'profil': 'presse'});
      await f.armerPouvoir();
      await f.commencerSeance(carte('b', duree: 80), pronostic: 3);
      expect(await f.validerEnCours(f.enCours.single), 2);
    });

    test('R39 Boussole et Madeleine agissent au tirage', () async {
      final catalogue = [for (var i = 0; i < 12; i++) _film('t$i')];
      final quatre = Tirage(hasard: Random(1)).tirer(catalogue: catalogue, emotion: Emotion.frissonner, duree: Duree.soiree, profil: Profil.explorateur, nombre: 4);
      expect(quatre, hasLength(4));
      expect(quatre.map((c) => c.film.id).toSet(), hasLength(4));
      final vus = [for (var i = 0; i < 6; i++) _film('v$i', vu: true)];
      expect(Tirage(hasard: Random(1)).tirer(catalogue: vus, emotion: Emotion.frissonner, duree: Duree.soiree, profil: Profil.fidele), isEmpty);
      expect(Tirage(hasard: Random(1)).tirer(catalogue: vus, emotion: Emotion.frissonner, duree: Duree.soiree, profil: Profil.fidele, revoir: true), hasLength(3));
      final e = await _etat({'profil': 'explorateur'});
      expect(await e.pouvoirAuTirage(), (nombre: 3, revoir: false), reason: 'pas armé : rien');
      await e.armerPouvoir();
      expect(await e.pouvoirAuTirage(), (nombre: 4, revoir: false));
      expect(e.chargesPouvoir, 0);
      final f = await _etat({'profil': 'degustateur'});
      await f.armerPouvoir();
      expect(await f.pouvoirAuTirage(), (nombre: 3, revoir: false));
      expect(f.pouvoirArme, isTrue, reason: 'Slow attend le billet');
    });
  });

  group('R40 Coups du sort et crasses', () {
    String mois(DateTime d) => EtatJeu.moisDe(d);
    CarteDefi carte(String id, {int cases = 1, int? niveau}) => CarteDefi(
        type: TypeCarte.envie, defi: 'Défi', indice: '', cases: cases, joker: '', film: _film(id), bulleDePop: '', niveau: niveau);

    test('R40 les cases 4, 14 et 24 sont les Coups de théâtre, avec trois coups différents chaque mois', () {
      for (var n = 1; n <= Regles.taillePlateau; n++) {
        expect(CoupsDuSort.estCaseCoup(n), Circuit.typeDe(n) == TypeCase.coup, reason: 'case $n');
      }
      for (var m = 1; m <= 24; m++) {
        final d = DateTime(2026, m);
        expect({for (final n in [4, 14, 24]) CoupsDuSort.pour(d, n)}, hasLength(3), reason: 'mois $m');
      }
    });

    test('R40 ce que chaque coup déplace, toujours entre 1 et 30', () {
      expect(CoupsDuSort.deplacement(CoupDuSort.toboggan, joueur: 14, pop: 10), (joueur: -2, pop: 0));
      expect(CoupsDuSort.deplacement(CoupDuSort.toboggan, joueur: 2, pop: 10), (joueur: -1, pop: 0));
      expect(CoupsDuSort.deplacement(CoupDuSort.echange, joueur: 10, pop: 14), (joueur: 4, pop: -4));
      expect(CoupsDuSort.deplacement(CoupDuSort.vol, joueur: 10, pop: 29), (joueur: 0, pop: 1));
      expect(CoupsDuSort.deplacement(CoupDuSort.public, joueur: 30, pop: 10), (joueur: 0, pop: 0));
      expect(CoupsDuSort.deplacement(CoupDuSort.entracte, joueur: 5, pop: 5), (joueur: 0, pop: 0));
      expect(CoupsDuSort.faitDuTort(CoupDuSort.echange, joueur: 10, pop: 14), isFalse, reason: 'derrière Pop, l\'échange est une aubaine');
      expect(CoupsDuSort.faitDuTort(CoupDuSort.echange, joueur: 20, pop: 14), isTrue);
      expect(CoupsDuSort.faitDuTort(CoupDuSort.toboggan, joueur: 3, pop: 14), isTrue);
      expect(CoupsDuSort.faitDuTort(CoupDuSort.public, joueur: 3, pop: 14), isFalse);
    });

    test('R40 s\'arrêter sur une case Coup de théâtre déclenche le coup, une fois par case et par mois', () async {
      final e = await _etat();
      await e.validerSeance(carte('a', cases: 3), pronostic: 3);
      expect(e.position, 4);
      final c = e.coupEnAttente!;
      expect(c.numero, 4);
      expect(c.coup, CoupsDuSort.pour(DateTime.now(), 4));
      final (avant, pop) = (e.position, e.positionDePop);
      final d = CoupsDuSort.deplacement(c.coup, joueur: avant, pop: pop);
      expect(await e.resoudreCoup(), isTrue);
      expect(e.position, avant + d.joueur);
      expect(e.positionDePop, pop + d.pop);
      expect(e.coupEnAttente, isNull);
      expect(await e.resoudreCoup(), isFalse);
      final f = await _etat({'coups_${mois(DateTime.now())}': ['4']});
      await f.validerSeance(carte('a', cases: 3), pronostic: 3);
      expect(f.coupEnAttente, isNull, reason: 'déjà joué ce mois-ci');
    });

    test('R40 un coup qui fait du tort se pare : charge de pouvoir ou Bouclier ; sinon pas de parade', () async {
      final maintenant = DateTime.now();
      final m = mois(maintenant);
      final nuisible = [4, 14, 24].where((n) => CoupsDuSort.pour(maintenant, n).nuisible).firstOrNull;
      final sansTort = [4, 14, 24].firstWhere((n) => !CoupsDuSort.pour(maintenant, n).nuisible);
      final g = await _etat({'position': 5, 'coup_en_attente': '$m|$sansTort'});
      if (!CoupsDuSort.faitDuTort(g.coupEnAttente!.coup, joueur: g.position, pop: g.positionDePop)) {
        expect(await g.resoudreCoup(parade: 'charge'), isFalse);
        expect(g.coupEnAttente, isNotNull);
      }
      if (nuisible == null) return; // ce mois-ci, aucune case n'est nuisible
      final e = await _etat({'position': 12, 'coup_en_attente': '$m|$nuisible'});
      expect(e.peutParerAvecCharge, isTrue);
      expect(await e.resoudreCoup(parade: 'charge'), isTrue);
      expect(e.position, 12);
      expect(e.chargesPouvoir, 0);
      expect(e.coupEnAttente, isNull);
      final f = await _etat({'position': 12, 'coup_en_attente': '$m|$nuisible'});
      expect(await f.resoudreCoup(parade: 'bouclier'), isTrue);
      expect(f.bouclierDispo, isFalse);
      expect(f.position, 12);
      final h = await _etat({'position': 12, 'coup_en_attente': '$m|$nuisible', 'bouclier_$m': 1});
      await h.armerPouvoir();
      expect(h.peutParerAvecCharge, isFalse, reason: 'la seule charge est déjà armée');
      expect(await h.resoudreCoup(parade: 'charge'), isFalse);
    });

    test('R40 une crasse par semaine, un renvoi par mois', () {
      final mercredi = DateTime(2026, 11, 18);
      expect(Crasses.peutEnvoyer(mercredi, const []), isTrue);
      expect(Crasses.peutEnvoyer(mercredi, [DateTime(2026, 11, 16, 9)]), isFalse);
      expect(Crasses.peutEnvoyer(mercredi, [DateTime(2026, 11, 15, 23)]), isTrue, reason: 'dimanche dernier, c\'était l\'autre semaine');
      expect(Crasses.peutRenvoyer(mercredi, [DateTime(2026, 11, 2)]), isFalse);
      expect(Crasses.peutRenvoyer(mercredi, [DateTime(2026, 10, 30)]), isTrue);
      final c = CrasseRecue.depuisJson({'id': 'x', 'ligue_id': 'l', 'de': 'a', 'pour': 'b', 'type': 'popcorn', 'reponse': 'paree', 'cree_le': '2026-11-06T10:00:00Z', 'renvoi': true})!;
      expect((c.crasse, c.reponse, c.renvoi), (Crasse.popcorn, Reponse.paree, true));
      expect(CrasseRecue.depuisJson({'id': 'x', 'ligue_id': 'l', 'de': 'a', 'pour': 'b', 'type': 'inconnue', 'cree_le': '2026-11-06T10:00:00Z'}), isNull);
    });

    test('R40 encaisser une crasse : chaque effet s\'applique une fois', () async {
      final e = await _etat();
      expect(await e.repondreCrasse(Crasse.popcorn, Reponse.encaissee), isTrue);
      expect(await e.validerSeance(carte('a', cases: 2), pronostic: 3), 1, reason: 'une case de moins');
      expect(await e.validerSeance(carte('b', cases: 1), pronostic: 3), 1, reason: 'une seule fois');
      await e.repondreCrasse(Crasse.niveauImpose, Reponse.encaissee);
      expect(e.niveauImpose, 8);
      await e.oublierNiveauImpose();
      expect(e.niveauImpose, isNull);
      await e.repondreCrasse(Crasse.volDAudace, Reponse.encaissee);
      expect(e.audaceDuMois, 0, reason: 'jamais d\'audace négative');
      final f = await _etat(_devantPop);
      await f.validerSeance(carte('a', cases: Niveau.cases(10), niveau: 10), pronostic: 3);
      await f.repondreCrasse(Crasse.volDAudace, Reponse.encaissee);
      expect(f.audaceDuMois, 15);
      await f.repondreCrasse(Crasse.fauxSpoiler, Reponse.encaissee);
      expect(f.motDePop, contains('chien'));
    });

    test('R40 parer coûte une charge, renvoyer une fois par mois, et le voleur touche ses points', () async {
      final e = await _etat(_devantPop);
      expect(await e.repondreCrasse(Crasse.popcorn, Reponse.paree), isTrue);
      expect(e.chargesPouvoir, 0);
      expect(await e.repondreCrasse(Crasse.popcorn, Reponse.paree), isFalse);
      expect(await e.repondreCrasse(Crasse.popcorn, Reponse.renvoyee), isTrue);
      expect(await e.repondreCrasse(Crasse.popcorn, Reponse.renvoyee), isFalse);
      expect(await e.validerSeance(carte('a', cases: 2), pronostic: 3), 2, reason: 'parée ou renvoyée : aucun effet');
      expect(e.peutFaireUneCrasse, isTrue);
      await e.noterCrasseEnvoyee();
      expect(e.peutFaireUneCrasse, isFalse);
      final vol = CrasseRecue(id: 'v1', ligueId: 'l', de: 'moi', pour: 'ami', crasse: Crasse.volDAudace, date: DateTime.now(), reponse: Reponse.encaissee);
      final pare = CrasseRecue(id: 'v2', ligueId: 'l', de: 'moi', pour: 'ami', crasse: Crasse.volDAudace, date: DateTime.now(), reponse: Reponse.paree);
      expect(await e.encaisserGains([vol, pare]), 5);
      expect(await e.encaisserGains([vol, pare]), 0);
      expect(e.audaceDuMois, 5);
    });
  });

  group('R41 Retournements : rattrapage, risque et journal', () {
    final mois = EtatJeu.moisDe(DateTime.now());
    CarteDefi carte(String id, {int cases = 1}) =>
        CarteDefi(type: TypeCarte.envie, defi: 'Défi', indice: '', cases: cases, joker: '', film: _film(id), bulleDePop: '');

    test('R41 le journal du plateau raconte le mois, le plus récent d\'abord, 12 lignes au plus', () async {
      final e = await _etat();
      expect(e.journal, isEmpty);
      await e.validerSeance(carte('a', cases: 2), pronostic: 3);
      expect(e.journal.first, contains('« Film a » : +2 cases'));
      await e.repondreCrasse(Crasse.fauxSpoiler, Reponse.encaissee);
      expect(e.journal.first, contains('Crasse encaissée'));
      for (var i = 0; i < 20; i++) {
        await e.repondreCrasse(Crasse.fauxSpoiler, Reponse.encaissee);
      }
      expect(e.journal, hasLength(Retournements.tailleJournal));
    });

    test('R41 Vent dans le dos : une séance vue derrière Pop rapporte 2 points d\'audace', () async {
      final e = await _etat({'pop_decalage_$mois': 5});
      expect(e.position < e.positionDePop, isTrue);
      await e.validerSeance(carte('a'), pronostic: 3);
      expect(e.audaceDuMois, Retournements.ventDansLeDos);
      expect(e.journal.any((l) => l.contains('Vent dans le dos')), isTrue);
      final f = await _etat({'position': 30});
      await f.validerSeance(carte('a'), pronostic: 3);
      expect(f.audaceDuMois, 0, reason: 'devant Pop : pas de vent');
    });

    test('R41 Volte-face : un Joker par mois pour prendre la place de Pop, seulement quand on est derrière', () async {
      final e = await _etat({'pop_decalage_$mois': 2});
      final pop = e.positionDePop;
      expect(e.volteFaceDispo, isTrue);
      expect(await e.volteFace(), isTrue);
      expect(e.position, pop);
      expect(e.positionDePop, lessThan(pop));
      expect(e.volteFaceDispo, isFalse);
      expect(await e.volteFace(), isFalse);
      final f = await _etat({'position': 30});
      expect(f.volteFaceDispo, isFalse);
      expect(await f.volteFace(), isFalse);
    });

    test('R41 le pari de Sisyphe : 4 cases d\'avance, un film abandonné renvoie à la case 1', () async {
      final e = await _etat({'position': 3});
      if (DateTime.now().day > Retournements.joursSisyphe) {
        expect(e.sisypheProposable, isFalse, reason: 'proposé la première semaine seulement');
        expect(await e.accepterSisyphe(), isFalse);
        return;
      }
      expect(await e.accepterSisyphe(), isTrue);
      expect(e.position, 3 + Retournements.avanceSisyphe);
      expect(e.sisypheActif, isTrue);
      expect(await e.accepterSisyphe(), isFalse, reason: 'une fois par mois');
      await e.commencerSeance(carte('a'), pronostic: 3);
      expect(await e.abandonnerSeance(e.enCours.single), 2 + Retournements.avanceSisyphe);
      expect(e.position, 1);
      expect(e.sisypheActif, isFalse);
      expect(e.sisypheProposable, isFalse);
      final f = await _etat();
      await f.refuserSisyphe();
      expect(f.sisypheProposable, isFalse);
      expect(f.position, 1);
    });
  });

  group('R42 Déblocage progressif et Ce soir pour toi', () {
    CarteDefi carte(String id) => CarteDefi(type: TypeCarte.envie, defi: 'Défi', indice: '', cases: 1, joker: '', film: _film(id), bulleDePop: '');
    final neuf = <String, Object>{'tout_ouvert': false};

    test('R42 les règles s\'ouvrent à la 3e, 5e, 7e et 9e séance, une à la fois', () {
      expect([for (final e in Etape.values) e.seances], [3, 5, 7, 9]);
      expect(Deblocage.ouvert(Etape.niveaux, seances: 2), isFalse);
      expect(Deblocage.ouvert(Etape.niveaux, seances: 3), isTrue);
      expect(Deblocage.ouvert(Etape.crasses, seances: 0, toutOuvert: true), isTrue);
      expect(Deblocage.prochaine(seances: 0), Etape.niveaux);
      expect(Deblocage.prochaine(seances: 5), Etape.coups);
      expect(Deblocage.prochaine(seances: 9), isNull);
      expect(Deblocage.aAnnoncer(seances: 6, annoncees: {}), Etape.niveaux, reason: 'la plus ancienne d\'abord');
      expect(Deblocage.aAnnoncer(seances: 6, annoncees: {'niveaux'}), Etape.pouvoirs);
      expect(Deblocage.aAnnoncer(seances: 6, annoncees: {'niveaux', 'pouvoirs'}), isNull);
      expect(Deblocage.aAnnoncer(seances: 9, annoncees: {}, toutOuvert: true), isNull);
    });

    test('R42 au début, pas de pouvoir ni de coup de théâtre ; Pop présente chaque règle quand elle arrive', () async {
      final e = await _etat(neuf);
      expect(e.ouvert(Etape.niveaux), isFalse);
      expect(await e.armerPouvoir(), isFalse);
      expect(e.volteFaceDispo, isFalse);
      expect(e.nouveaute, isNull);
      await e.validerSeance(carte('a'), pronostic: 3);
      await e.validerSeance(carte('b'), pronostic: 3);
      await e.validerSeance(carte('c'), pronostic: 3);
      expect(e.position, 4);
      expect(e.coupEnAttente, isNull, reason: 'les coups de théâtre ne sont pas encore ouverts');
      expect(e.ouvert(Etape.niveaux), isTrue);
      expect(e.nouveaute, Etape.niveaux);
      await e.nouveauteVue(Etape.niveaux);
      expect(e.nouveaute, isNull);
      await e.changerToutOuvert(true);
      expect(await e.armerPouvoir(), isTrue, reason: '« Je connais déjà le jeu » ouvre tout');
    });

    test('R42 Ce soir pour toi : deux lignes, la plus urgente d\'abord, puis la prochaine règle', () {
      final debut = CeSoirPourToi.lignes(const Situation(seances: 1, position: 2, pop: 5, casesRestantes: 3));
      expect(debut, ['Pop a 3 cases d\'avance : une séance ce soir te rapproche.', 'Encore 2 séances avant la prochaine règle : « Tu te mets combien ? ».']);
      final chargee = CeSoirPourToi.lignes(const Situation(seances: 12, position: 9, pop: 5, casesRestantes: 3, coupEnAttente: 14, pouvoirCharge: true, nomPouvoir: 'Slow'));
      expect(chargee, hasLength(2));
      expect(chargee.first, contains('case 14'));
      expect(chargee.last, contains('Slow est chargé'));
      final cachee = CeSoirPourToi.lignes(const Situation(seances: 3, position: 5, pop: 5, casesRestantes: 0, pouvoirCharge: true, nomPouvoir: 'Slow'));
      expect(cachee.first, contains('Plafond du jour'));
      expect(cachee.any((l) => l.contains('Slow')), isFalse, reason: 'les pouvoirs ne sont pas encore ouverts');
      expect(cachee.last, contains('Ton pouvoir'));
    });
  });

  group('R43 Rivaux robots et figurine du mois', () {
    final mois = EtatJeu.moisDe(DateTime.now());
    CarteDefi carte(String id) => CarteDefi(type: TypeCarte.envie, defi: 'Défi', indice: '', cases: 1, joker: '', film: _film(id), bulleDePop: '');

    test('R43 Bobine avance chaque jour sauf le dimanche, Pellicule de 0 à 2 ; tout se calcule depuis la date', () {
      expect(Rivaux.position(Rival.bobine, DateTime(2026, 11, 8)), 7, reason: '1er et 8 novembre 2026 sont des dimanches');
      expect(Rivaux.position(Rival.bobine, DateTime(2026, 11, 30)), 26);
      final p = Rivaux.position(Rival.pellicule, DateTime(2026, 11, 10));
      expect(p, inInclusiveRange(1, 21));
      expect(Rivaux.position(Rival.pellicule, DateTime(2026, 11, 10)), p);
      expect(Rivaux.position(Rival.pellicule, DateTime(2026, 11, 11)), greaterThanOrEqualTo(p));
    });

    test('R43 chaque semaine, un rival fait une crasse à partir d\'un jour fixé, et ne change pas d\'avis', () {
      final semaine = [for (var j = 2; j <= 8; j++) Rivaux.crasseDeLaSemaine(DateTime(2026, 11, j, 20))];
      final premier = semaine.indexWhere((c) => c != null);
      expect(premier, inInclusiveRange(0, 4), reason: 'entre lundi et vendredi');
      expect(semaine.skip(premier).every((c) => c == semaine[premier]), isTrue);
      expect(semaine.take(premier).every((c) => c == null), isTrue);
    });

    test('R43 la crasse d\'un rival se règle une fois ; renvoyée, il recule de 2', () async {
      final e = await _etat();
      final c = Rivaux.crasseDeLaSemaine(DateTime.now());
      if (c == null) {
        expect(e.crasseDesRivaux, isNull);
        return;
      }
      expect(e.crasseDesRivaux, c);
      final avant = e.positionDe(c.rival);
      expect(await e.repondreAuRival(Reponse.renvoyee), isTrue);
      expect(e.positionDe(c.rival), max(1, avant - Rivaux.reculRenvoi));
      expect(e.crasseDesRivaux, isNull);
      expect(await e.repondreAuRival(Reponse.encaissee), isFalse);
      final f = await _etat({'tout_ouvert': false});
      expect(f.crasseDesRivaux, isNull, reason: 'les crasses ne sont pas encore ouvertes');
    });

    test('R43 l\'œuf éclot à la 3e séance du mois et donne le pouvoir d\'une autre figurine', () async {
      for (var m = 1; m <= 12; m++) {
        for (final p in Profil.values) {
          expect(Oeuf.eclosion(p, DateTime(2026, m)), isNot(p));
        }
      }
      final e = await _etat({'profil': 'critique', 'figurine_$mois': 'oeuf'});
      expect(e.profilDuPouvoir, isNull);
      expect(await e.armerPouvoir(), isFalse);
      for (final id in ['a', 'b', 'c']) {
        await e.validerSeance(carte(id), pronostic: 3);
      }
      expect(e.oeufEclos, isTrue);
      expect(e.profilDuPouvoir, Oeuf.eclosion(Profil.critique, DateTime.now()));
      expect(await e.armerPouvoir(), isTrue);
    });

    test('R43 le Figurant n\'a pas de pouvoir, mais avance d\'une case quand il se passe quelque chose, une fois par jour', () async {
      final e = await _etat({'figurine_$mois': 'figurant', 'position': 5});
      expect(e.profilDuPouvoir, isNull);
      expect(await e.armerPouvoir(), isFalse);
      await e.repondreCrasse(Crasse.fauxSpoiler, Reponse.encaissee);
      expect(e.position, 6);
      await e.noterCrasseEnvoyee();
      expect(e.position, 6, reason: 'une fois par jour');
      final f = await _etat({'position': 5});
      if (DateTime.now().day <= Retournements.joursSisyphe) {
        expect(f.figurineAChoisir, isTrue);
        await f.choisirFigurine(FigurineDuMois.figurant);
        expect(f.figurineDuMois, FigurineDuMois.figurant);
        expect(f.figurineAChoisir, isFalse);
      } else {
        expect(f.figurineAChoisir, isFalse, reason: 'le choix se fait la première semaine');
      }
    });
  });

  group('R44 Défi d\'après-séance et Pop-cartes', () {
    CarteDefi carte(String id, {int? niveau}) =>
        CarteDefi(type: TypeCarte.envie, defi: 'Défi', indice: '', cases: 1, joker: '', film: _film(id), bulleDePop: '', niveau: niveau);

    test('R44 trois questions sur le film vu, quatre réponses distinctes dont une juste', () {
      final q = DefiApres.questions(titre: 'Le Samouraï', annee: 1967, pays: const ['France'], genres: const ['Crime'], graine: 4);
      expect(q, hasLength(3));
      for (final x in q) {
        expect(x.reponses.toSet(), hasLength(4));
        expect(x.bonne, inInclusiveRange(0, 3));
      }
      expect(q[0].reponses[q[0].bonne], 'Années 1960');
      expect(q[1].reponses[q[1].bonne], 'France');
      expect(q[2].reponses[q[2].bonne], Traduction.genre('Crime'));
      expect(DefiApres.questions(titre: 'X', annee: 2001), hasLength(1), reason: 'pas de question sans donnée');
      expect(DefiApres.questions(titre: 'X'), isEmpty);
      expect([DefiApres.audace(0, 3), DefiApres.audace(2, 3), DefiApres.audace(3, 3)], [0, 2, 5]);
    });

    test('R44 après une séance, le défi attend ; un sans-faute rapporte 5 d\'audace et fait briller la Pop-carte', () async {
      final e = await _etat(_devantPop);
      await e.validerSeance(carte('a', niveau: 8), pronostic: 3);
      final b = e.defiApres!;
      expect(b.titre, 'Film a');
      expect(await e.repondreDefiApres(justes: 3, total: 3), 5);
      expect(e.audaceDuMois, 8 + 5);
      expect(e.defiApres, isNull);
      expect(e.brillante(e.billets.single), isTrue);
      expect(await e.repondreDefiApres(justes: 3, total: 3), 0, reason: 'une seule fois');
      await e.validerSeance(carte('b'), pronostic: 3);
      await e.passerDefiApres();
      expect(e.defiApres, isNull);
      expect(e.brillante(e.billets.first), isFalse);
      expect(e.albumDuMois.map((b) => b.titre), ['Film a', 'Film b']);
      final f = await _etat({'tout_ouvert': false});
      await f.validerSeance(carte('a'), pronostic: 3);
      expect(f.defiApres, isNull, reason: 'pas avant les niveaux');
    });

    test('R44 la rareté d\'une Pop-carte vient du niveau visé', () {
      expect([null, 2, 5, 8, 10].map((n) => Rarete.de(niveau: n)), [Rarete.commune, Rarete.commune, Rarete.rare, Rarete.epique, Rarete.legendaire]);
    });
  });

  group('R45 Notifications utiles et équilibrage', () {
    test('R45 au plus deux avis par semaine, à 18 h 30, jamais le jour du rappel, coupables', () {
      final mardi = DateTime(2026, 11, 10, 9);
      final avis = AvisDuJeu.prevus(maintenant: mardi, pouvoirs: true, crasses: true);
      expect(avis.length, inInclusiveRange(1, 2));
      expect(avis.every((a) => a.moment.hour == 18 && a.moment.minute == 30), isTrue);
      expect(avis.where((a) => a.moment.weekday == DateTime.monday).single.texte, contains('charge de pouvoir'));
      expect({for (final a in avis) DateTime(a.moment.year, a.moment.month, a.moment.day)}, hasLength(avis.length), reason: 'un par jour au plus');
      final lundi = DateTime(2026, 11, 16, 12, 30);
      expect(AvisDuJeu.prevus(maintenant: mardi, pouvoirs: true, crasses: false, rappelAlorsCeFilm: lundi), isEmpty, reason: 'le lundi est pris par le rappel');
      expect(AvisDuJeu.prevus(maintenant: mardi, pouvoirs: true, crasses: true, actifs: false), isEmpty);
      expect(AvisDuJeu.prevus(maintenant: mardi, pouvoirs: false, crasses: false), isEmpty, reason: 'rien tant que les règles ne sont pas ouvertes');
      final rival = AvisDuJeu.prevus(maintenant: DateTime(2026, 11, 2, 0, 1), pouvoirs: false, crasses: true);
      final c = Rivaux.crasseDeLaSemaine(DateTime(2026, 11, 6, 20))!;
      expect(rival.single.titre, '${c.rival.nom} t\'a fait une crasse');
      expect(Rivaux.crasseDeLaSemaine(rival.single.moment), c);
      if (rival.single.moment.weekday != DateTime.monday) {
        expect(Rivaux.crasseDeLaSemaine(rival.single.moment.subtract(const Duration(days: 1))), isNull, reason: 'le jour même où elle arrive');
      }
    });

    test('R45 simulateur : armés au bon moment, les pouvoirs « au billet » se valent (aucun plus de 2,5 fois un autre)', () {
      final r = Random(42);
      int tirer(List<int> poids) {
        var x = r.nextInt(poids.reduce((a, b) => a + b));
        for (final (i, p) in poids.indexed) {
          if (x < p) return i;
          x -= p;
        }
        return poids.length - 1;
      }

      final gains = <Profil, double>{};
      for (final p in [Profil.degustateur, Profil.critique, Profil.presse, Profil.hote, Profil.supporter, Profil.devoreur]) {
        var total = 0;
        const n = 4000;
        for (var i = 0; i < n; i++) {
          final demandees = 1 + tirer([4, 4, 2]);
          final deja = p == Profil.devoreur ? 2 + tirer([4, 6]) : tirer([6, 2, 1, 1]);
          final pronostic = 2 + r.nextInt(3);
          final note = r.nextInt(10) < 9 ? (pronostic + tirer([1, 2, 4, 2, 1]) - 2).clamp(1, 5) : null;
          final bonus = Pouvoirs.bonus(
            p,
            pronostic: pronostic,
            note: note,
            dureeMinutes: r.nextInt(100) < 85 ? 85 : 110,
            aPlusieurs: r.nextInt(100) < 85,
            derrierePop: r.nextInt(100) < 90,
          );
          final sans = Regles.casesAccordees(demandees: demandees, dejaGagneesAujourdhui: deja);
          final avec = Regles.casesAccordees(demandees: demandees + bonus, dejaGagneesAujourdhui: deja, plafond: Pouvoirs.plafond(p, 3));
          total += avec - sans;
        }
        gains[p] = total / n;
      }
      final valeurs = gains.values;
      final mini = valeurs.reduce(min), maxi = valeurs.reduce(max);
      expect(mini, greaterThan(0.3), reason: '$gains');
      expect(maxi, lessThanOrEqualTo(1.0), reason: '$gains');
      expect(maxi / mini, lessThanOrEqualTo(2.5), reason: '$gains');
    });
  });

  group('R46 Le pont avec VJOD', () {
    final catalogue = [for (var i = 0; i < 12; i++) _film('j$i', genres: const ['Thriller', 'Comedy', 'Drama', 'Animation', 'Adventure'])];
    Future<List<Film>> fourni(Emotion _) async => catalogue;
    final vjod = <String, Object>{'mode': 'vjod', 'jf_adresse': 'https://serveur.test/jellyfin', 'jf_utilisateur': 'u1', 'jf_jeton': 'jeton'};

    test('R46 Aura tire les cartes de 7 soirs, toujours les mêmes, et oublie les soirs passés', () async {
      final e = await _etat();
      final lundi = DateTime(2026, 11, 9, 10);
      await e.preparerCartesVjod(fourni, maintenant: lundi);
      final cartes = e.cartesPourVjod;
      expect(cartes.keys, hasLength(PontVjod.jours));
      expect(cartes.keys.first, '2026-11-09');
      expect(cartes.values.every((l) => l.length == 3), isTrue);
      final avant = jsonEncode(cartes);
      await e.preparerCartesVjod(fourni, maintenant: lundi);
      expect(jsonEncode(e.cartesPourVjod), avant, reason: 'pas de nouveau tirage pour un soir déjà prêt');
      await e.preparerCartesVjod(fourni, maintenant: DateTime(2026, 11, 11, 10));
      expect(e.cartesPourVjod.keys.first, '2026-11-11');
      expect(e.cartesPourVjod.keys, hasLength(PontVjod.jours));
      expect(PontVjod.envieDuJour(lundi), isNot(PontVjod.envieDuJour(lundi.add(const Duration(days: 1)))));
    });

    test('R46 une carte jouée dans VJOD devient une séance ; la note de fin de film la valide', () async {
      final e = await _etat();
      await e.preparerCartesVjod(fourni);
      final jour = PontVjod.jourDe(DateTime.now());
      final carte = PontVjod.carteDepuisJson(e.cartesPourVjod[jour]![1])!;
      final quand = DateTime.now().subtract(const Duration(hours: 2));
      final joue = jsonEncode({'jour': jour, 'index': 1, 'quand': quand.toUtc().toIso8601String()});
      expect(await e.appliquerDepuisVjod(joue: joue), isTrue);
      expect(e.enCours.single.filmId, carte.film.id);
      expect(e.enCours.single.debut.difference(quand).inSeconds.abs(), lessThan(2));
      expect(await e.appliquerDepuisVjod(joue: joue), isFalse, reason: 'déjà en cours');
      final note = jsonEncode({'film': carte.film.id, 'note': 5, 'quand': DateTime.now().toUtc().toIso8601String()});
      expect(await e.appliquerDepuisVjod(note: note), isTrue);
      expect(e.enCours, isEmpty);
      expect(e.billets.single.note, 5);
      expect(e.billets.single.titre, carte.film.titre);
      expect(PontVjod.lireNote('{"film":"x","note":9,"quand":"2026-11-06T20:00:00Z"}'), isNull);
      expect(PontVjod.lireJoue('pas du json'), isNull);
    });

    test('R46 à l\'ouverture, Aura lit VJOD, publie son état et efface ce qu\'il a appliqué', () async {
      final e = await _etat(vjod);
      final ecrits = <Map<String, dynamic>>[];
      final client = MockClient((r) async {
        expect(r.url.path, '/jellyfin/DisplayPreferences/aura');
        expect(r.url.queryParameters, {'userId': 'u1', 'client': 'aura'});
        if (r.method == 'GET') {
          return http.Response(jsonEncode({'Id': 'aura', 'SortBy': 'SortName', 'CustomPrefs': {'note': '{"film":"rien","note":4,"quand":"2026-11-06T20:00:00Z"}', 'autre': 'garde'}}), 200);
        }
        ecrits.add(jsonDecode(r.body) as Map<String, dynamic>);
        return http.Response('', 204);
      });
      await e.synchroniserVjod(service: ServicePontVjod(e.connexion, client: client), catalogue: fourni);
      final prefs = ecrits.single['CustomPrefs'] as Map<String, dynamic>;
      expect(ecrits.single['SortBy'], 'SortName', reason: 'le reste des préférences est gardé');
      expect(prefs['autre'], 'garde');
      expect(prefs.containsKey('note'), isFalse);
      final etat = jsonDecode(prefs['etat'] as String) as Map<String, dynamic>;
      expect(etat['v'], 1);
      expect(etat['position'], e.position);
      expect((etat['cartes'] as Map).length, PontVjod.jours);
      final f = await _etat();
      await f.synchroniserVjod(service: ServicePontVjod(f.connexion, client: client), catalogue: fourni);
      expect(ecrits, hasLength(1), reason: 'hors édition VJOD, rien n\'est envoyé');
    });
  });

  group('R47 L\'aura : se proposer des films', () {
    Proposition p(String id, {String de = 'jf:jon', String pour = 'jf:lea', String film = 'tmdb:1', bool vu = false, bool aime = false, int? note}) => Proposition(
          id: id,
          de: 'joueur-$de',
          dePersonne: de,
          deNom: de == 'jf:jon' ? 'Jon' : 'Léa',
          pourPersonne: pour,
          pourNom: 'x',
          filmCle: film,
          titre: 'Film',
          vuLe: vu ? DateTime(2026, 11, 6) : null,
          aime: aime,
          note: note,
          creeLe: DateTime(2026, 11, 5),
        );

    test('R47 regardé +1, aimé +2 (un cœur ou 4 et 5), aimé par plusieurs +3 de plus', () {
      expect(Aura.scores([p('a')]), {'jf:jon': 0});
      expect(Aura.scores([p('a', vu: true)]), {'jf:jon': 1});
      expect(Aura.scores([p('a', vu: true, aime: true)]), {'jf:jon': 3});
      expect(Aura.scores([p('a', vu: true, note: 4)]), {'jf:jon': 3});
      expect(Aura.scores([p('a', vu: true, note: 3)]), {'jf:jon': 1});
      expect(Aura.scores([p('a', vu: true, aime: true), p('b', pour: 'jf:max', vu: true, note: 5)]), {'jf:jon': 3 + 3 + Aura.bonusPlusieurs});
      expect(Aura.scores([p('a', vu: true, aime: true), p('b', pour: 'jf:max', film: 'tmdb:2', vu: true, aime: true)]), {'jf:jon': 6}, reason: 'deux films différents : pas de bonus');
      final c = Aura.classement([p('a', vu: true), p('b', de: 'jf:lea', pour: 'jf:jon', vu: true, aime: true)]);
      expect(c.map((x) => x.nom), ['Léa', 'Jon']);
      expect(c.first.aura, 3);
    });

    test('R47 une proposition se lit et s\'écrit, la clé du film est la même partout', () {
      expect(Aura.cleFilm(tmdb: 603), 'tmdb:603');
      expect(Aura.cleFilm(jellyfin: 'abc'), 'jf:abc');
      final corps = Proposition.nouvelle(dePersonne: 'srv:jon', deNom: 'Jon', pourPersonne: 'srv:lea', pourNom: 'Léa', maison: 'srv', titre: 'Matrix', annee: 1999, tmdb: 603, jellyfin: 'abc', mot: '  Tu vas adorer  ');
      expect(corps['film_cle'], 'tmdb:603');
      expect(corps['mot'], 'Tu vas adorer');
      final lue = Proposition.depuisJson({...corps, 'id': 'p1', 'de': 'u1', 'aime': false, 'note': 5, 'vu_le': '2026-11-06T21:00:00Z', 'cree_le': '2026-11-06T18:00:00Z'})!;
      expect((lue.titre, lue.tmdb, lue.jellyfin, lue.auteur, lue.destinataire, lue.vu, lue.aimee), ('Matrix', 603, 'abc', 'srv:jon', 'srv:lea', true, true));
      expect(Proposition.depuisJson({'id': 'x'}), isNull);
    });
  });

  group('R48 L\'aura dans Aura', () {
    test('R48 à qui proposer : la maison d\'abord, un par personne, puis les amis de ligue, jamais soi', () {
      final d = Destinataire.liste(
        maison: [
          (pseudo: 'Zoé', personne: 'srv:zoe'),
          (pseudo: 'Jon', personne: 'srv:jon'),
          (pseudo: 'Léa', personne: 'srv:lea'),
          (pseudo: 'Léa tablette', personne: 'srv:lea'),
          (pseudo: 'Sans personne', personne: null),
        ],
        amis: [
          (joueur: 'j-lea', pseudo: 'Léa', personne: 'srv:lea', ligueId: 'L1'),
          (joueur: 'j-max', pseudo: 'Max', personne: null, ligueId: 'L1'),
          (joueur: 'j-max', pseudo: 'Max', personne: null, ligueId: 'L2'),
          (joueur: 'j-sam', pseudo: 'Sam', personne: 'autre:sam', ligueId: 'L2'),
          (joueur: 'moi', pseudo: 'Jon', personne: null, ligueId: 'L1'),
        ],
        moiPersonne: 'srv:jon',
        moiJoueur: 'moi',
      );
      expect(d.map((x) => x.nom), ['Léa', 'Zoé', 'Max', 'Sam']);
      expect(d.first.maison, isTrue);
      expect((d[2].joueur, d[2].personne, d[2].ligueId), ('j-max', null, 'L1'), reason: 'sans VJOD, visé par son joueur');
      expect((d[3].joueur, d[3].personne), (null, 'autre:sam'), reason: 'avec VJOD, visé par sa personne pour tous ses appareils');
    });

    test('R48 vu et aimé d\'après Jellyfin, comme dans VJOD ; on n\'enlève jamais', () {
      final p = Proposition(id: 'p', de: 'u', deNom: 'Jon', pourNom: 'Léa', filmCle: 'tmdb:1', titre: 'X', creeLe: DateTime(2026, 11, 6));
      final t = DateTime.utc(2026, 11, 6, 22);
      expect(majDepuisJellyfin({'Played': true, 'IsFavorite': true}, p, t), {'vu_le': '2026-11-06T22:00:00.000Z', 'aime': true});
      expect(majDepuisJellyfin({'UnplayedItemCount': 5, 'PlayedPercentage': 10}, p, t), {'vu_le': '2026-11-06T22:00:00.000Z'});
      expect(majDepuisJellyfin({'Rating': 8}, p, t)?['aime'], isTrue);
      expect(majDepuisJellyfin({'Played': false}, p, t), isNull);
      expect(majDepuisJellyfin(null, p, t), isNull);
      final vue = Proposition(id: 'p', de: 'u', deNom: 'Jon', pourNom: 'Léa', filmCle: 'tmdb:1', titre: 'X', vuLe: t, aime: true, creeLe: t);
      expect(majDepuisJellyfin({'Played': false, 'IsFavorite': false}, vue, t), isNull);
    });
  });

  group('R49 Le Deck d\'atouts', () {
    Billet billet({int? annee = 1970, int pronostic = 4, int? note = 4, List<String> pays = const ['France'], List<String> genres = const ['Drama'], DateTime? date, String type = 'Rétro', int? niveau}) => Billet(
          titre: 'X',
          type: type,
          pronostic: pronostic,
          cases: 0,
          date: date ?? DateTime(2026, 11, 4, 21),
          note: note,
          annee: annee,
          pays: pays,
          genres: genres,
          niveau: niveau,
        );

    test('R49 les atouts posés et possédés se déclenchent ; une case au plus par film, l\'audace s\'additionne', () {
      final e = Deck.effets(['projectionniste', 'critique', 'nouvelle_vague', 'cascadeur'], {'projectionniste': 1, 'critique': 1, 'nouvelle_vague': 1}, ContexteAtout(billet: billet()));
      expect(e.declenches.map((a) => a.id), ['projectionniste', 'critique', 'nouvelle_vague']);
      expect(e.cases, 1, reason: 'deux atouts à une case : une seule case');
      expect(e.audace, 2);
      final rien = Deck.effets(['critique'], {'critique': 1}, ContexteAtout(billet: billet(note: 2)));
      expect((rien.cases, rien.audace), (0, 0));
      expect(rien.declenches, isEmpty);
    });

    test('R49 les doubles font monter le niveau : 3 exemplaires niveau 2, 6 niveau 3, une d\'audace de plus par niveau', () {
      expect([1, 2, 3, 5, 6, 9].map(Deck.niveau), [1, 1, 2, 2, 3, 3]);
      final e = Deck.effets(['projectionniste'], {'projectionniste': 6}, ContexteAtout(billet: billet()));
      expect(e.audace, 2 + 2);
    });

    test('R49 des défis lisibles : dimanche, film d\'hier, 3e de la semaine, pays nouveau du mois', () {
      final dimanche = DateTime(2026, 11, 8, 21);
      expect(Deck.de('generique')!.condition(ContexteAtout(billet: billet(date: dimanche))), isTrue);
      final hier = billet(date: dimanche.subtract(const Duration(days: 1)));
      expect(Deck.de('plan_sequence')!.condition(ContexteAtout(billet: billet(date: dimanche), avant: [hier])), isTrue);
      expect(Deck.de('realisatrice')!.condition(ContexteAtout(billet: billet(date: dimanche), avant: [hier, billet(date: DateTime(2026, 11, 3))])), isTrue);
      expect(Deck.de('realisatrice')!.condition(ContexteAtout(billet: billet(date: dimanche), avant: [hier])), isFalse);
      expect(Deck.de('tour_du_monde')!.condition(ContexteAtout(billet: billet(pays: ['Japon']), avant: [billet(pays: ['France'])])), isTrue);
      expect(Deck.de('tour_du_monde')!.condition(ContexteAtout(billet: billet(pays: ['France']), avant: [billet(pays: ['France'])])), isFalse);
      expect(Deck.de('ralenti')!.condition(ContexteAtout(billet: billet(), dureeMinutes: 160)), isTrue);
    });

    test('R49 24 atouts en 3 séries de 8, chacun avec un gain ; 4e place à 15 atouts différents', () {
      expect(Deck.atouts, hasLength(24));
      expect(Deck.atouts.map((a) => a.id).toSet(), hasLength(24));
      for (final s in Serie.values) {
        expect(Deck.dela(s), hasLength(8));
        expect(Collection.exploits.any((x) => x.id == s.exploit), isTrue);
      }
      expect(Deck.atouts.every((a) => a.cases > 0 || a.audace > 0), isTrue);
      expect(Deck.atouts.where((a) => a.rarete == Rarete.commune).every((a) => a.cases == 0), isTrue, reason: 'les communes ne donnent que de l\'audace');
      expect((Deck.emplacements(14), Deck.emplacements(15)), (3, 4));
    });

    test('R49 un booster : 3 atouts ; un Épique ou mieux garanti au 10e booster', () {
      for (var g = 0; g < 200; g++) {
        expect(Deck.booster(Random(g)), hasLength(3));
        final garanti = Deck.booster(Random(g), sansEpique: Deck.garantie - 1);
        expect(garanti.any((a) => a.rarete.index >= Rarete.epique.index), isTrue);
      }
    });

    test('R49 un booster par jour, au plus deux en réserve', () {
      final lundi = DateTime(2026, 11, 2, 10);
      expect(Deck.disponibles(reserve: 0, dernierDon: null, aujourdhui: lundi), 1);
      expect(Deck.disponibles(reserve: 0, dernierDon: lundi, aujourdhui: lundi.add(const Duration(hours: 8))), 0);
      expect(Deck.disponibles(reserve: 0, dernierDon: lundi, aujourdhui: lundi.add(const Duration(days: 1))), 1);
      expect(Deck.disponibles(reserve: 0, dernierDon: lundi, aujourdhui: lundi.add(const Duration(days: 6))), 2);
    });

    test('R49 ouvrir son booster : la collection grandit, les nouveaux vont au deck, pas deux fois le même jour', () async {
      final e = await _etat();
      final r = await e.ouvrirBooster(hasard: Random(3));
      expect(r.cartes, hasLength(3));
      expect(e.atouts.values.fold<int>(0, (a, b) => a + b), 3);
      expect(e.deck, isNotEmpty);
      expect(e.deck.length, lessThanOrEqualTo(3));
      expect(e.boostersDispo(), 0);
      expect((await e.ouvrirBooster()).cartes, isEmpty);
    });

    test('R49 au billet : la Critique donne sa case et le plafond du jour tient', () async {
      final e = await _etat({'atouts': jsonEncode({'critique': 1}), 'deck': ['critique'], ..._devantPop});
      expect(await e.validerSeance(_carte('a', type: TypeCarte.envie, cases: 1), pronostic: 4, note: 4), 2);
      expect(await e.validerSeance(_carte('b', cases: 3), pronostic: 4, note: 4), 1, reason: 'plafond de 3 cases par jour');
      expect(await e.basculerAtout('critique'), isTrue);
      expect(e.deck, isEmpty);
      expect(await e.basculerAtout('inconnu'), isFalse);
    });
  });
}

class _SourceFixe implements SourceFilms {
  _SourceFixe(this.films);
  final List<Film> films;
  @override
  String get nom => 'fixe';
  @override
  Future<List<Film>> catalogue({Emotion? emotion, Duree? duree, Epoque? epoque, bool auHasard = true}) async => films;
}

class _SourceEnPanne implements SourceFilms {
  @override
  String get nom => 'en panne';
  @override
  Future<List<Film>> catalogue({Emotion? emotion, Duree? duree, Epoque? epoque, bool auHasard = true}) async => throw Exception('TMDB ne répond pas');

}

/// Rouvre l'état sur les mêmes préférences, comme après une fermeture.
Future<EtatJeu> _etatDepuis(EtatJeu _) async => EtatJeu(await SharedPreferences.getInstance());
