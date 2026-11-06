import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/modeles.dart';

/// Ouvre un titre de la bibliothèque Jellyfin directement dans VJOD.
///
/// VJOD (fork de Moonfin) reçoit déjà ces liens sur Android TV et sur
/// téléphone, sans modification :
///   moonfin://play?id=<itemId>&serverId=<serverId>   lance la lecture
///   moonfin://item?id=<itemId>&serverId=<serverId>   ouvre la fiche
abstract final class VjodLien {
  static Uri pour(Film film, {bool lecture = true}) => film.source == SourceFilm.catalogueVjod
      // Hors du serveur : la fiche VJOD du titre, qui sait s'il est en VOD
      // chez le fournisseur IPTV ou s'il faut le demander (VJOD 4.36).
      ? Uri(scheme: 'moonfin', host: 'tmdb', queryParameters: {'id': '${film.tmdbId}', 'type': 'movie', 'title': film.titre})
      : Uri(
        scheme: 'moonfin',
        host: lecture ? 'play' : 'item',
        queryParameters: {
          'id': film.id,
          if (film.serveurId != null && film.serveurId!.isNotEmpty) 'serverId': film.serveurId!,
        },
      );

  /// Vrai si le titre peut partir dans VJOD depuis cet appareil.
  static bool disponible(Film film) =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android && (film.source == SourceFilm.jellyfin || (film.source == SourceFilm.catalogueVjod && film.tmdbId != null));

  /// Renvoie null si VJOD a été ouvert, sinon le message à afficher.
  static Future<String?> ouvrir(Film film, {bool lecture = true}) async {
    if (!disponible(film)) {
      return 'Le lancement dans VJOD fonctionne sur Android, en édition VJOD.';
    }
    try {
      final ok = await launchUrl(pour(film, lecture: lecture), mode: LaunchMode.externalApplication);
      return ok ? null : 'VJOD n\'est pas installé sur cet appareil.';
    } catch (_) {
      return 'VJOD n\'a pas répondu. Vérifie qu\'il est installé et à jour.';
    }
  }
}
