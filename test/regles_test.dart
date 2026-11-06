// Les règles du jeu, une par une. Chaque test porte le numéro de la règle
// qu'il protège (voir « Les règles et leurs tests » dans REPRISE.md).
// Une règle nouvelle = un test nouveau ici. Si un test casse, c'est qu'une
// règle a changé : on le décide exprès, jamais par accident.

import 'dart:convert';
import 'dart:math';

import 'package:aura/models/modeles.dart';
import 'package:aura/services/affiche.dart';
import 'package:aura/services/cadeaux.dart';
import 'package:aura/services/campagnes.dart';
import 'package:aura/services/carte_genres.dart';
import 'package:aura/services/collection.dart';
import 'package:aura/services/config.dart';
import 'package:aura/services/connexion_vjod.dart';
import 'package:aura/services/duel.dart';
import 'package:aura/services/etat.dart';
import 'package:aura/services/fidelite.dart';
import 'package:aura/services/generique.dart';
import 'package:aura/services/historique.dart';
import 'package:aura/services/juste_un_film.dart';
import 'package:aura/services/ligues.dart';
import 'package:aura/services/mesures.dart';
import 'package:aura/services/plan_du_jour.dart';
import 'package:aura/services/plateformes.dart';
import 'package:aura/services/pop.dart';
import 'package:aura/services/premier_soir.dart';
import 'package:aura/services/rappels.dart';
import 'package:aura/services/semaine_ligue.dart';
import 'package:aura/services/source_tmdb.dart';
import 'package:aura/services/soiree.dart';
import 'package:aura/services/sources.dart';
import 'package:aura/services/tirage.dart';
import 'package:aura/services/vjod_lien.dart';
import 'package:aura/widgets/animations.dart';
import 'package:aura/widgets/aura_widgets.dart';
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

Future<EtatJeu> _etat([Map<String, Object> valeurs = const {}]) async {
  SharedPreferences.setMockInitialValues(valeurs);
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
}

class _SourceFixe implements SourceFilms {
  _SourceFixe(this.films);
  final List<Film> films;
  @override
  String get nom => 'fixe';
  @override
  Future<List<Film>> catalogue({Emotion? emotion, Duree? duree, bool auHasard = true}) async => films;
}

class _SourceEnPanne implements SourceFilms {
  @override
  String get nom => 'en panne';
  @override
  Future<List<Film>> catalogue({Emotion? emotion, Duree? duree, bool auHasard = true}) async => throw Exception('TMDB ne répond pas');
}

/// Rouvre l'état sur les mêmes préférences, comme après une fermeture.
Future<EtatJeu> _etatDepuis(EtatJeu _) async => EtatJeu(await SharedPreferences.getInstance());
