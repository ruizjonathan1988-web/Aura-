import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Les petits bruits d'Aura : Pop qui parle, une carte qu'on retourne, le
/// tampon « Vu ! », le pion qui saute, la fanfare. Sons maison (générés,
/// libres de droits). Coupables dans les Réglages.
enum Son { pop, carte, tampon, boing, fanfare }

abstract final class Sons {
  /// Réglé par EtatJeu au démarrage et dans les Réglages.
  static bool actifs = true;

  static final Map<Son, AudioPlayer> _lecteurs = {};

  static bool get _enTest {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  static Future<void> jouer(Son s) async {
    if (!actifs || _enTest) return;
    try {
      final l = _lecteurs[s] ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      await l.stop();
      await l.play(AssetSource('sons/${s.name}.wav'), volume: .7);
    } catch (_) {
      // Pas de son sur cet appareil : le jeu continue en silence.
    }
  }
}
