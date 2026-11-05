// Les règles du jeu, une par une. Chaque test porte le numéro de la règle
// qu'il protège (voir « Les règles et leurs tests » dans REPRISE.md).
// Une règle nouvelle = un test nouveau ici. Si un test casse, c'est qu'une
// règle a changé : on le décide exprès, jamais par accident.

import 'dart:convert';
import 'dart:math';

import 'package:aura/models/modeles.dart';
import 'package:aura/services/affiche.dart';
import 'package:aura/services/carte_genres.dart';
import 'package:aura/services/connexion_vjod.dart';
import 'package:aura/services/duel.dart';
import 'package:aura/services/etat.dart';
import 'package:aura/services/plan_du_jour.dart';
import 'package:aura/services/pop.dart';
import 'package:aura/services/premier_soir.dart';
import 'package:aura/services/sources.dart';
import 'package:aura/services/tirage.dart';
import 'package:aura/widgets/aura_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Film _film(String id, {double? note = 7.5, int annee = 2010, int duree = 100, bool vu = false, int? votes}) =>
    Film(id: id, titre: 'Film $id', note: note, annee: annee, dureeMinutes: duree, genres: const ['Thriller'], pays: const ['France'], dejaVu: vu, nombreVotes: votes);

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
      expect(jsonDecode(recue.body), {'Username': 'jon', 'Pw': 'secret'});
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
}

/// Rouvre l'état sur les mêmes préférences, comme après une fermeture.
Future<EtatJeu> _etatDepuis(EtatJeu _) async => EtatJeu(await SharedPreferences.getInstance());
