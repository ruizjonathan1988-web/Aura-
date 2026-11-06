import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/modeles.dart';
import 'sources.dart';

/// Un film de l'historique importé (Letterboxd).
class FilmVu {
  const FilmVu(this.titre, this.annee, [this.note]);
  final String titre;
  final int? annee;

  /// Note sur 5 donnée sur Letterboxd, si elle existe.
  final double? note;
}

/// L'import de l'historique Letterboxd : Aura ne propose plus les films déjà
/// vus ailleurs. Aucune case n'est gagnée pour le passé (on n'avance qu'en
/// regardant), et rien ne part sur le serveur.
///
/// Sur Letterboxd : Paramètres, Import et export, « Export your data ». On
/// choisit ensuite dans Aura le fichier .zip reçu (ou directement
/// watched.csv, ratings.csv ou diary.csv).
abstract final class Historique {
  /// Lit l'export : un .zip (on prend watched, ratings et diary) ou un .csv.
  static List<FilmVu> lireExport(Uint8List octets, String nomDuFichier) {
    if (nomDuFichier.toLowerCase().endsWith('.zip')) {
      final archive = ZipDecoder().decodeBytes(octets);
      final films = <FilmVu>[];
      for (final f in archive.files) {
        final nom = f.name.toLowerCase().split('/').last;
        if (f.isFile && ['watched.csv', 'ratings.csv', 'diary.csv'].contains(nom)) {
          films.addAll(lireCsv(utf8.decode(f.content as List<int>, allowMalformed: true)));
        }
      }
      return films;
    }
    return lireCsv(utf8.decode(octets, allowMalformed: true));
  }

  /// Lit un fichier CSV Letterboxd (colonnes Name, Year et, si présente, Rating).
  static List<FilmVu> lireCsv(String texte) {
    final lignes = _lignes(texte.replaceFirst('﻿', ''));
    if (lignes.isEmpty) return const [];
    final entete = lignes.first.map((c) => c.trim().toLowerCase()).toList();
    final iNom = entete.indexOf('name');
    final iAnnee = entete.indexOf('year');
    final iNote = entete.indexOf('rating');
    if (iNom < 0) return const [];
    return [
      for (final l in lignes.skip(1))
        if (l.length > iNom && l[iNom].trim().isNotEmpty)
          FilmVu(
            l[iNom].trim(),
            iAnnee >= 0 && l.length > iAnnee ? int.tryParse(l[iAnnee].trim()) : null,
            iNote >= 0 && l.length > iNote ? double.tryParse(l[iNote].trim()) : null,
          ),
    ];
  }

  /// Découpe un CSV en respectant les guillemets (virgules et guillemets
  /// doublés dans les titres).
  static List<List<String>> _lignes(String texte) {
    final lignes = <List<String>>[];
    var ligne = <String>[];
    final champ = StringBuffer();
    var guillemets = false;
    for (var i = 0; i < texte.length; i++) {
      final c = texte[i];
      if (guillemets) {
        if (c == '"') {
          if (i + 1 < texte.length && texte[i + 1] == '"') {
            champ.write('"');
            i++;
          } else {
            guillemets = false;
          }
        } else {
          champ.write(c);
        }
      } else if (c == '"') {
        guillemets = true;
      } else if (c == ',') {
        ligne.add(champ.toString());
        champ.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < texte.length && texte[i + 1] == '\n') i++;
        ligne.add(champ.toString());
        champ.clear();
        if (ligne.any((x) => x.isNotEmpty)) lignes.add(ligne);
        ligne = <String>[];
      } else {
        champ.write(c);
      }
    }
    ligne.add(champ.toString());
    if (ligne.any((x) => x.isNotEmpty)) lignes.add(ligne);
    return lignes;
  }

  static const _accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
    'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i', 'ñ': 'n',
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o', 'ø': 'o',
    'û': 'u', 'ü': 'u', 'ú': 'u', 'ù': 'u', 'ÿ': 'y', 'œ': 'oe', 'æ': 'ae',
  };

  /// Un titre réduit à l'essentiel : minuscules, sans accents ni ponctuation,
  /// sans article au début. « Le Samouraï » et « Le Samourai » se valent.
  static String normaliser(String titre) {
    var t = titre.toLowerCase();
    t = t.split('').map((c) => _accents[c] ?? c).join();
    t = t.replaceAll(RegExp(r"[^a-z0-9]+"), ' ').trim();
    t = t.replaceFirst(RegExp(r'^(the|a|an|le|la|les|l|un|une|el|il|der|die|das) '), '');
    return t;
  }

  static String cle(String titre, int? annee) => '${normaliser(titre)}|${annee ?? ''}';

  /// Vrai si le film figure dans l'historique (titre ou titre original, à un
  /// an près : les dates de sortie varient selon les pays).
  static bool dejaVu(Film f, Set<String> vus) {
    if (vus.isEmpty) return false;
    final titres = [f.titre, ...f.autresTitres].map(normaliser).toSet();
    final annees = f.annee == null ? <String>{''} : {for (var d = -1; d <= 1; d++) '${f.annee! + d}'};
    for (final t in titres) {
      for (final a in annees) {
        if (vus.contains('$t|$a')) return true;
      }
      if (vus.contains('$t|')) return true;
    }
    return false;
  }
}

/// Une source dont les films de l'historique importé sont marqués « vus » :
/// le tirage, l'Affiche et le Bluff ne les proposent plus.
class SourceAvecHistorique implements SourceFilms {
  SourceAvecHistorique(this.source, this.vus);
  final SourceFilms source;
  final Set<String> vus;

  @override
  String get nom => source.nom;

  @override
  Future<List<Film>> catalogue({Emotion? emotion, bool auHasard = true}) async {
    final films = await source.catalogue(emotion: emotion, auHasard: auHasard);
    return [for (final f in films) Historique.dejaVu(f, vus) ? f.vu() : f];
  }
}
