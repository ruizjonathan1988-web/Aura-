import 'package:flutter/material.dart';

/// Les couleurs d'Aura : le rouge VJOD en fond de jeu, le noir des contours,
/// le crème du carton, l'ambre VJOD pour les actions, et les couleurs vives
/// des cases et des figurines.
abstract final class AuraCouleurs {
  static const rouge = Color(0xFFE5261F);
  static const noir = Color(0xFF141414);
  static const creme = Color(0xFFF6EFE2);
  static const ambre = Color(0xFFF2A93B);
  static const jaune = Color(0xFFFFD23F);
  static const rose = Color(0xFFFF8FB8);
  static const vert = Color(0xFF5BD08A);
  static const violet = Color(0xFF9B7BFF);
  static const bleu = Color(0xFF5CB8FF);
  static const peche = Color(0xFFFFB27A);
  static const citron = Color(0xFFB8E07A);
  static const texteDoux = Color(0xFF4A3F33);

  // Cases du circuit
  static const caseOrange = Color(0xFFF7A93B);
  static const caseRose = Color(0xFFF58BC7);
  static const caseVert = Color(0xFF3DAA4E);
  static const caseBleu = Color(0xFF4AA3E8);
  static const caseRouge = Color(0xFFEE4B36);
  static const plateau = Color(0xFF1C1C1C);
}

/// Épaisseurs et ombres franches communes : le style « matériel de jeu ».
abstract final class AuraTrait {
  static const epais = 3.0;
  static const rayon = 18.0;

  static List<BoxShadow> ombre([double d = 4]) => [
        BoxShadow(color: AuraCouleurs.noir, offset: Offset(d, d)),
      ];

  static BoxDecoration panneau({
    Color couleur = AuraCouleurs.creme,
    double rayon = AuraTrait.rayon,
    double ombre = 4,
  }) =>
      BoxDecoration(
        color: couleur,
        borderRadius: BorderRadius.circular(rayon),
        border: Border.all(color: AuraCouleurs.noir, width: epais),
        boxShadow: ombre > 0 ? AuraTrait.ombre(ombre) : null,
      );
}

abstract final class AuraTexte {
  /// Police des titres : la même famille condensée que VJOD.
  static TextStyle titre(double taille, {Color couleur = AuraCouleurs.noir}) =>
      TextStyle(fontFamily: 'Anton', fontSize: taille, height: 1.0, color: couleur, letterSpacing: .3);

  static TextStyle corps(double taille,
          {FontWeight poids = FontWeight.w800, Color couleur = AuraCouleurs.noir}) =>
      TextStyle(fontFamily: 'Nunito', fontSize: taille, fontWeight: poids, color: couleur, height: 1.35);
}

ThemeData construireTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AuraCouleurs.rouge,
      primary: AuraCouleurs.rouge,
      surface: AuraCouleurs.creme,
    ),
    scaffoldBackgroundColor: AuraCouleurs.rouge,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'Nunito',
      bodyColor: AuraCouleurs.noir,
      displayColor: AuraCouleurs.noir,
    ),
    focusColor: AuraCouleurs.jaune,
    splashFactory: NoSplash.splashFactory,
  );
}
