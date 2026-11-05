import 'dart:math';

import 'package:aura/models/modeles.dart';
import 'package:aura/services/sources.dart';
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
}
