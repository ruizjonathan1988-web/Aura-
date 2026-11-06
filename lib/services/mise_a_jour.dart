import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Une version d'Aura plus récente que celle installée.
class NouvelleVersion {
  const NouvelleVersion({required this.adresse, required this.publieeLe, required this.nouveautes, this.taille});

  final Uri adresse;
  final DateTime publieeLe;

  /// Ce qui change, tel que la CI l'écrit sur la release (vide s'il n'y a rien).
  final List<String> nouveautes;
  final int? taille;

  /// « 6 novembre à 14 h 32 », pour la fenêtre.
  String get date {
    const mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
    final l = publieeLe.toLocal();
    return '${l.day} ${mois[l.month - 1]} à ${l.hour} h ${l.minute.toString().padLeft(2, '0')}';
  }
}

/// La mise à jour automatique, comme dans VJOD : la CI publie l'APK sur la
/// release « derniere » ; Aura le compare à l'heure de sa propre installation,
/// le télécharge et le donne à l'installeur d'Android. Sur la box, pas besoin
/// de Downloader. Sur le web, rien à faire : la page est toujours la dernière.
abstract final class MiseAJour {
  static const release = 'https://api.github.com/repos/ruizjonathan1988-web/Aura-/releases/tags/derniere';
  static const fichier = 'aura.apk';
  static const _canal = MethodChannel('fr.vjod.aura/mise_a_jour');

  /// Deux minutes de marge : l'installation suit de peu la publication.
  static const marge = Duration(minutes: 2);

  static bool get possible => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// La release lue sur GitHub, comparée à l'heure d'installation : nulle
  /// quand Aura est à jour ou quand la release n'a pas d'APK.
  static NouvelleVersion? depuisRelease(Object? json, DateTime installeeLe) {
    if (json is! Map) return null;
    final apk = (json['assets'] as List? ?? const []).whereType<Map>().where((a) => a['name'] == fichier).firstOrNull;
    if (apk == null) return null;
    final publiee = DateTime.tryParse(apk['updated_at']?.toString() ?? '');
    final adresse = Uri.tryParse(apk['browser_download_url']?.toString() ?? '');
    if (publiee == null || adresse == null || !publiee.isAfter(installeeLe.add(marge))) return null;
    return NouvelleVersion(
      adresse: adresse,
      publieeLe: publiee,
      nouveautes: nouveautesDepuis(json['body']?.toString() ?? ''),
      taille: apk['size'] as int?,
    );
  }

  /// Les lignes « - … » écrites par la CI sous « Ce qui change ».
  static List<String> nouveautesDepuis(String corps) {
    final lignes = const LineSplitter().convert(corps);
    final debut = lignes.indexWhere((l) => l.trim().toLowerCase().startsWith('ce qui change'));
    if (debut < 0) return const [];
    return [
      for (final l in lignes.skip(debut + 1))
        if (l.trim().startsWith('- ')) l.trim().substring(2).trim(),
    ].where((l) => l.isNotEmpty).toList();
  }

  static DateTime? _derniereVerification;

  /// Une nouvelle version, ou nulle. Au plus une demande à GitHub par heure,
  /// sauf si on la demande dans les réglages ([forcer]). Jamais d'erreur.
  static Future<NouvelleVersion?> verifier({bool forcer = false, http.Client? client}) async {
    if (!possible) return null;
    final maintenant = DateTime.now();
    if (!forcer && _derniereVerification != null && maintenant.difference(_derniereVerification!) < const Duration(hours: 1)) {
      return null;
    }
    _derniereVerification = maintenant;
    try {
      final ms = await _canal.invokeMethod<int>('installeeLe');
      if (ms == null || ms <= 0) return null;
      final c = client ?? http.Client();
      final rep = await c.get(Uri.parse(release), headers: const {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 15));
      if (rep.statusCode != 200) return null;
      return depuisRelease(jsonDecode(utf8.decode(rep.bodyBytes)), DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
    } catch (_) {
      return null;
    }
  }

  /// Si Android laisse Aura installer ses mises à jour (« sources inconnues »).
  static Future<bool> peutInstaller() async {
    try {
      return await _canal.invokeMethod<bool>('peutInstaller') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> ouvrirReglages() async {
    try {
      await _canal.invokeMethod<bool>('ouvrirReglages');
    } catch (_) {}
  }

  /// Télécharge l'APK (la progression va de 0 à 1) puis le donne à
  /// l'installeur d'Android. Renvoie un message d'erreur, ou nul.
  static Future<String?> installer(NouvelleVersion v, {void Function(double)? progression, http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final dossier = await _canal.invokeMethod<String>('dossier');
      if (dossier == null) return 'Impossible de préparer le téléchargement.';
      final apk = File('$dossier/aura-mise-a-jour.apk');
      final rep = await c.send(http.Request('GET', v.adresse));
      if (rep.statusCode != 200) return 'Le téléchargement a échoué (${rep.statusCode}).';
      final total = rep.contentLength ?? v.taille ?? 0;
      var recu = 0;
      final sortie = apk.openWrite();
      await for (final morceau in rep.stream) {
        sortie.add(morceau);
        recu += morceau.length;
        if (total > 0) progression?.call(recu / total);
      }
      await sortie.close();
      await _canal.invokeMethod<bool>('installer', {'chemin': apk.path});
      return null;
    } catch (_) {
      return 'La mise à jour n\'a pas pu s\'installer. Réessaie depuis les réglages.';
    }
  }
}
