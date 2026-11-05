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
  static Uri pour(Film film, {bool lecture = true}) => Uri(
        scheme: 'moonfin',
        host: lecture ? 'play' : 'item',
        queryParameters: {
          'id': film.id,
          if (film.serveurId != null && film.serveurId!.isNotEmpty) 'serverId': film.serveurId!,
        },
      );

  /// Vrai si le titre peut partir dans VJOD depuis cet appareil.
  static bool disponible(Film film) =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android && film.source == SourceFilm.jellyfin;

  /// Renvoie null si VJOD a été ouvert, sinon le message à afficher.
  static Future<String?> ouvrir(Film film, {bool lecture = true}) async {
    if (!disponible(film)) {
      return 'Le lancement dans VJOD marche sur Android, pour les titres de ta bibliothèque.';
    }
    try {
      final ok = await launchUrl(pour(film, lecture: lecture), mode: LaunchMode.externalApplication);
      return ok ? null : 'VJOD n\'est pas installé sur cet appareil.';
    } catch (_) {
      return 'VJOD n\'a pas répondu. Vérifie qu\'il est installé et à jour.';
    }
  }
}
