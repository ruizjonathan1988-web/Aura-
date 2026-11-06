import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_donnees;
import 'package:timezone/timezone.dart' as tz;

import 'avis_du_jeu.dart';

/// Le rappel du lendemain : une seule notification, « Alors, Le Samouraï ? »,
/// avec trois notes directement dedans. Un geste, et le pion avance.
/// Jamais de culpabilisation : un seul rappel par carte jouée, et il
/// disparaît dès que le billet est validé.
abstract final class Rappels {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _pret = false;
  static const _id = 1;

  /// Les trois notes proposées dans la notification.
  static const notes = {'note_2': 2, 'note_4': 4, 'note_5': 5};

  /// Une réponse arrivée avant que le jeu soit prêt (appli lancée depuis la
  /// notification) : (identifiant du film, note ou null).
  static (String, int?)? enAttente;

  /// Appelé quand le joueur touche la notification pendant que l'appli tourne.
  static void Function(String filmId, int? note)? surReponse;

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> initialiser() async {
    if (!_android || _pret) return;
    try {
      tz_donnees.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Paris'));
      await _plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (r) {
          final lu = lire(r.payload, r.actionId);
          if (lu == null) return;
          if (surReponse != null) {
            surReponse!(lu.$1, lu.$2);
          } else {
            enAttente = lu;
          }
        },
      );
      final lancement = await _plugin.getNotificationAppLaunchDetails();
      final r = lancement?.notificationResponse;
      if ((lancement?.didNotificationLaunchApp ?? false) && r != null) enAttente = lire(r.payload, r.actionId);
      _pret = true;
    } catch (_) {
      // Pas de notifications sur cet appareil : le jeu marche sans.
    }
  }

  /// Lit une réponse de notification : (film, note) ; la note est null si
  /// on a simplement touché la notification.
  static (String, int?)? lire(String? payload, String? actionId) {
    if (payload == null || payload.isEmpty) return null;
    return (payload, notes[actionId]);
  }

  /// Le moment du rappel : le lendemain à 12 h 30.
  static DateTime moment(DateTime carteJouee) => DateTime(carteJouee.year, carteJouee.month, carteJouee.day + 1, 12, 30);

  static Future<void> alorsCeFilm({required String filmId, required String titre, required DateTime carteJouee}) async {
    if (!_pret) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin.zonedSchedule(
        _id,
        'Alors, $titre ?',
        'Donne ta note en un geste, et ton pion avance.',
        tz.TZDateTime.from(moment(carteJouee), tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'alors_ce_film',
            'Alors, ce film ?',
            channelDescription: 'Un seul rappel le lendemain d\'une carte jouée, pour noter le film.',
            importance: Importance.defaultImportance,
            actions: [
              AndroidNotificationAction('note_2', 'Bof', showsUserInterface: true),
              AndroidNotificationAction('note_4', 'Bien', showsUserInterface: true),
              AndroidNotificationAction('note_5', 'Génial !', showsUserInterface: true),
            ],
          ),
        ),
        payload: filmId,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {}
  }

  /// Les notifications de jeu (R45), identifiants 10 à 16 : on efface les
  /// anciennes et on prévoit les nouvelles.
  static Future<void> planifierAvis(List<AvisPrevu> avis) async {
    if (!_pret) return;
    try {
      for (var id = 10; id <= 16; id++) {
        await _plugin.cancel(id);
      }
      for (final (i, a) in avis.take(7).indexed) {
        await _plugin.zonedSchedule(
          10 + i,
          a.titre,
          a.texte,
          tz.TZDateTime.from(a.moment, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'avis_du_jeu',
              'Nouvelles du jeu',
              channelDescription: 'Au plus deux par semaine : ta charge de pouvoir revenue, la crasse d\'un rival.',
              importance: Importance.low,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (_) {}
  }

  static Future<void> annuler() async {
    if (!_pret) return;
    try {
      await _plugin.cancel(_id);
    } catch (_) {}
  }
}
