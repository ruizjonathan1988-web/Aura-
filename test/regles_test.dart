// Les règles du jeu, une par une. Chaque test porte le numéro de la règle
// qu'il protège (voir « Les règles et leurs tests » dans REPRISE.md).
// Une règle nouvelle = un test nouveau ici. Si un test casse, c'est qu'une
// règle a changé : on le décide exprès, jamais par accident.

import 'dart:math';

import 'package:aura/models/modeles.dart';
import 'package:aura/services/affiche.dart';
import 'package:aura/services/etat.dart';
import 'package:aura/services/plan_du_jour.dart';
import 'package:aura/services/pop.dart';
import 'package:aura/services/premier_soir.dart';
import 'package:aura/services/sources.dart';
import 'package:aura/services/tirage.dart';
import 'package:aura/widgets/aura_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

/// Rouvre l'état sur les mêmes préférences, comme après une fermeture.
Future<EtatJeu> _etatDepuis(EtatJeu _) async => EtatJeu(await SharedPreferences.getInstance());
