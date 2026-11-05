import 'dart:math';

import 'package:aura/models/modeles.dart';
import 'package:aura/services/sources.dart';
import 'package:aura/services/affiche.dart';
import 'package:aura/services/etat.dart';
import 'package:aura/services/pop.dart';
import 'package:aura/services/plan_du_jour.dart';
import 'package:aura/services/tirage.dart';
import 'package:aura/services/vjod_lien.dart';
import 'package:flutter_test/flutter_test.dart';

Film _film(String id, {double? note = 7.5, int annee = 2010, int duree = 100, List<String> genres = const ['Thriller'], List<String> pays = const ['France'], bool vu = false, int? votes}) =>
    Film(id: id, titre: 'Film $id', note: note, annee: annee, dureeMinutes: duree, genres: genres, pays: pays, dejaVu: vu, nombreVotes: votes);

void main() {
  group('Zéro navet', () {
    test('le jeu ne propose jamais un titre sous 3 étoiles', () {
      final catalogue = [
        for (var i = 0; i < 20; i++) _film('mauvais$i', note: 5.9),
        _film('bon1', note: 6.0),
        _film('bon2', note: 8.1, annee: 1962),
        _film('bon3', note: 7.0, pays: const ['Japon']),
      ];
      final cartes = Tirage(hasard: Random(1)).tirer(
        catalogue: catalogue, emotion: Emotion.frissonner, duree: Duree.moyenne, profil: Profil.fidele);
      expect(cartes, isNotEmpty);
      expect(cartes.every((c) => (c.film.note ?? 0) >= 6), isTrue);
    });

    test('un titre sans note ou avec trop peu d\'avis est écarté', () {
      expect(Tirage.assezBon(_film('a', note: null)), isFalse);
      expect(Tirage.assezBon(_film('b', note: 9, votes: 3)), isFalse);
      expect(Tirage.assezBon(_film('c', note: 7, votes: 40, annee: 1955)), isTrue);
    });
  });

  test('trois cartes au plus, sans doublon, ni film déjà vu, ni film trop long', () {
    final catalogue = [
      for (var i = 0; i < 10; i++) _film('f$i', annee: 1950 + i * 7),
      _film('vu', vu: true),
      _film('long', duree: 200),
    ];
    final cartes = Tirage(hasard: Random(3)).tirer(
      catalogue: catalogue, emotion: Emotion.frissonner, duree: Duree.moyenne, profil: Profil.critique);
    expect(cartes.length, 3);
    expect(cartes.map((c) => c.film.id).toSet().length, 3);
    expect(cartes.any((c) => c.film.id == 'vu' || c.film.id == 'long'), isFalse);
  });

  test('l\'envie filtre les genres', () {
    final catalogue = [_film('rire', genres: const ['Comedy']), _film('peur', genres: const ['Horror'])];
    final cartes = Tirage(hasard: Random(2)).tirer(
      catalogue: catalogue, emotion: Emotion.rire, duree: Duree.soiree, profil: Profil.hote);
    expect(cartes.map((c) => c.film.id), ['rire']);
  });

  test('plafond d\'équité : 3 cases par jour au maximum', () {
    expect(Regles.casesAccordees(demandees: 3, dejaGagneesAujourdhui: 0), 3);
    expect(Regles.casesAccordees(demandees: 3, dejaGagneesAujourdhui: 2), 1);
    expect(Regles.casesAccordees(demandees: 2, dejaGagneesAujourdhui: 3), 0);
  });

  test('le lien VJOD lance la lecture du bon titre', () {
    const f = Film(id: 'abc123', titre: 'X', serveurId: 'srv9', source: SourceFilm.jellyfin);
    expect(VjodLien.pour(f).toString(), 'moonfin://play?id=abc123&serverId=srv9');
    expect(VjodLien.pour(f, lecture: false).toString(), 'moonfin://item?id=abc123&serverId=srv9');
  });

  test('lecture d\'un titre Jellyfin', () {
    final f = SourceJellyfin.filmDepuisJellyfin({
      'Id': 'id1',
      'Name': 'Le Samouraï',
      'ServerId': 'srv',
      'ProductionYear': 1967,
      'RunTimeTicks': 63000000000,
      'CommunityRating': 7.9,
      'Genres': ['Crime'],
      'ProductionLocations': ['France'],
      'People': [
        {'Name': 'Alain Delon', 'Type': 'Actor'},
        {'Name': 'Jean-Pierre Melville', 'Type': 'Director'},
      ],
      'UserData': {'Played': false},
    });
    expect(f.dureeMinutes, 105);
    expect(f.realisateur, 'Jean-Pierre Melville');
    expect(f.source, SourceFilm.jellyfin);
    expect(f.etoiles, closeTo(3.95, .001));
  });

  group('Plan du jour', () {
    final catalogue = [
      for (var i = 0; i < 12; i++) _film('p$i', annee: 1950 + i * 6),
      _film('navet', note: 4.0),
    ];

    test('même film toute la journée, 4 choix dont la réponse, jamais de navet', () {
      final jour = DateTime(2026, 11, 5);
      final a = PlanDuJour.du(jour, catalogue)!;
      final b = PlanDuJour.du(DateTime(2026, 11, 5, 22, 30), [...catalogue.reversed])!;
      expect(a.film.id, b.film.id);
      expect(a.choix, hasLength(4));
      expect(a.choix.map((f) => f.id).toSet(), hasLength(4));
      expect(a.choix.any((f) => f.id == a.film.id), isTrue);
      expect(a.choix.every((f) => f.id != 'navet'), isTrue);
      expect(a.indices, hasLength(3));
    });

    test('pas de partie sans assez de films', () {
      expect(PlanDuJour.du(DateTime(2026, 11, 5), catalogue.take(3).toList()), isNull);
    });

    test('les indices ne donnent pas le titre', () {
      const f = Film(id: 'x', titre: 'Le Samouraï', annee: 1967, dureeMinutes: 105, genres: ['Crime'], pays: ['France'], realisateur: 'Jean-Pierre Melville');
      final i = PlanDuJour.indicesPour(f);
      expect(i[0], 'Genre : policier · Époque : années 1960');
      expect(i[1], 'Pays : France · Durée : 1 h 45');
      expect(i[2], 'Réalisation : Jean-Pierre Melville');
      expect(i.any((x) => x.contains('Samouraï')), isFalse);
    });

    test('le résultat se partage sans spoiler', () {
      final t = const ResultatPlan(indices: 2, trouve: true).partage(DateTime(2026, 11, 5));
      expect(t, contains('5 nov.'));
      expect(t, contains('🟨🟩⬜'));
      expect(t, contains('2e indice'));
      expect(const ResultatPlan(indices: 3, trouve: false).partage(DateTime(2026, 11, 5)), contains('🟨🟨🟥'));
    });
  });

  test('l\'Affiche reste la même toute la semaine', () {
    final catalogue = [for (var i = 0; i < 9; i++) _film('a$i')];
    String cle(DateTime d) => '${d.year}-${d.month}-${d.day}';
    final lundi = Affiche.de(DateTime(2026, 11, 2), catalogue, cle)!;
    final dimanche = Affiche.de(DateTime(2026, 11, 8, 21), catalogue, cle)!;
    expect(lundi.film.id, dimanche.film.id);
    expect(lundi.semaine, '2026-11-2');
    expect(Affiche.questionPour(_film('h', genres: const ['Horror'])), contains('peur'));
  });

  group('Pop', () {
    Billet billet(String type, DateTime d, {int prono = 3, int? note, String verdict = ''}) =>
        Billet(titre: 'T', type: type, pronostic: prono, cases: 1, date: d, note: note, verdict: verdict);

    test('il avance d\'une case par jour, triches comprises, sans dépasser le plateau', () {
      for (var j = 1; j <= 30; j++) {
        final p = Pop.position(DateTime(2026, 11, j, 20), const []);
        expect(p, greaterThanOrEqualTo(j.clamp(1, 30)));
        expect(p, lessThanOrEqualTo(30));
      }
    });

    test('un pari relevé le fait reculer de 2 cases', () {
      final jour = DateTime(2026, 11, 5, 21);
      final pari = Pop.pariDe(jour);
      final avant = Pop.position(jour, const []);
      // On fabrique la semaine qui relève n'importe lequel des paris.
      final lundi = Pop.lundiDe(jour);
      final semaine = [
        for (final t in ['Rétro', 'Voyage', 'Affiche']) billet(t, lundi.add(const Duration(hours: 20)), note: 3, verdict: 'Bien'),
      ];
      expect(pari.releve(semaine), isTrue);
      expect(Pop.position(jour, semaine), avant - Pop.recul);
    });

    test('il chambre un pronostic raté et salue un pronostic exact', () {
      expect(Pop.surPronostic(pronostic: 5, note: 2, graine: 0), contains('5'));
      expect(Pop.surPronostic(pronostic: 4, note: 4, graine: 1), isNotEmpty);
    });
  });

  group('Validation automatique', () {
    final debut = DateTime(2026, 11, 5, 21);

    test('un film vu après la carte jouée crée le billet', () {
      final vu = SourceJellyfin.dateDeVisionnage({'Played': true, 'LastPlayedDate': '2026-11-05T22:50:00.0000000Z'}, debut);
      expect(vu, isNotNull);
    });

    test('un film vu avant la carte, ou à moitié, ne compte pas', () {
      expect(SourceJellyfin.dateDeVisionnage({'Played': true, 'LastPlayedDate': '2025-01-01T10:00:00Z'}, debut), isNull);
      expect(SourceJellyfin.dateDeVisionnage({'Played': false, 'PlayedPercentage': 40}, debut), isNull);
      expect(SourceJellyfin.dateDeVisionnage({'Played': false, 'PlayedPercentage': 95}, debut), isNotNull);
      expect(SourceJellyfin.dateDeVisionnage(null, debut), isNull);
    });

    test('billets et séances en attente survivent à la fermeture', () {
      final b = Billet(titre: 'X', type: 'Rétro', pronostic: 4, cases: 3, date: debut, auto: true);
      final relu = Billet.depuisJson(b.versJson());
      expect(relu.aNoter, isTrue);
      expect(relu.copie(note: 2).aNoter, isFalse);
      final s = SeanceEnCours(titre: 'X', filmId: 'id', jellyfin: true, type: 'Rétro', cases: 3, pronostic: 4, debut: debut);
      final s2 = SeanceEnCours.depuisJson(s.versJson());
      expect(s2.filmId, 'id');
      expect(s2.jellyfin, isTrue);
      expect(s2.debut, debut);
    });
  });
}
