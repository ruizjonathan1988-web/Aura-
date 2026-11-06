// ignore_for_file: invalid_use_of_visible_for_testing_member
// Les captures d'écran d'Aura, pour relire l'interface sans appareil :
// la CI les dessine (avec les vraies polices) et les garde en artefact.
// Lancées à part : flutter test captures/captures_test.dart --update-goldens

import 'dart:io';
import 'dart:math';

import 'package:aura/app.dart';
import 'package:aura/models/modeles.dart';
import 'package:aura/screens/campagnes.dart';
import 'package:aura/screens/casse.dart';
import 'package:aura/screens/deck.dart';
import 'package:aura/screens/duel.dart';
import 'package:aura/screens/juste_un_film.dart';
import 'package:aura/screens/reglages.dart';
import 'package:aura/services/etat.dart';
import 'package:aura/services/sources.dart';
import 'package:aura/services/tirage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _polices() async {
  Future<void> charger(String famille, List<String> fichiers) async {
    final l = FontLoader(famille);
    for (final f in fichiers) {
      l.addFont(rootBundle.load(f));
    }
    await l.load();
  }

  await charger('Anton', ['assets/polices/Anton-Regular.ttf']);
  await charger('Nunito', ['assets/polices/Nunito-Bold.ttf', 'assets/polices/Nunito-ExtraBold.ttf', 'assets/polices/Nunito-Black.ttf']);
  final racine = Platform.environment['FLUTTER_ROOT'];
  if (racine != null) {
    final icones = File('$racine/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icones.existsSync()) {
      final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icones.readAsBytesSync().buffer)));
      await l.load();
    }
  }
}

Future<void> _patienter(WidgetTester t, [int dixiemes = 25]) async {
  for (var i = 0; i < dixiemes; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _photo(WidgetTester t, String nom) async {
  await _patienter(t);
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('sorties/$nom.png'));
}

Future<void> _toucher(WidgetTester t, String texte) async {
  final f = find.text(texte);
  if (f.evaluate().isEmpty) return;
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 100));
  await t.tap(f.first, warnIfMissed: false);
  await _patienter(t, 12);
}

Future<void> _ouvrir(WidgetTester t, Widget ecran) async {
  t.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute(builder: (_) => ecran));
  await _patienter(t);
}

Future<void> _fermer(WidgetTester t) async {
  t.state<NavigatorState>(find.byType(Navigator).first).pop();
  await _patienter(t, 8);
}

void main() {
  setUpAll(_polices);

  for (final (appareil, taille, densite) in [('telephone', const Size(390, 844), 2.0), ('tele', const Size(960, 540), 1.5)]) {
    testWidgets('captures $appareil', (t) async {
      t.view.physicalSize = taille * densite;
      t.view.devicePixelRatio = densite;
      addTearDown(t.view.reset);

      // Premier lancement : le rideau.
      SharedPreferences.setMockInitialValues({});
      var etat = EtatJeu(await SharedPreferences.getInstance());
      await t.pumpWidget(AuraApp(etat: etat));
      await _photo(t, '${appareil}_01_rideau');
      await _toucher(t, 'ENTRER DANS LA SALLE');
      await _photo(t, '${appareil}_02_premier_soir');

      // Un joueur en cours de mois : quelques billets, un deck.
      SharedPreferences.setMockInitialValues({'accueil_fait': true, 'tout_ouvert': true});
      etat = EtatJeu(await SharedPreferences.getInstance());
      final films = await SourceDemo().catalogue();
      final tirage = Tirage(hasard: Random(4));
      final cartes = tirage.tirer(catalogue: films, emotion: Emotion.rire, duree: Duree.soiree, profil: Profil.fidele);
      await etat.validerSeance(cartes.first, pronostic: 4, note: 5, verdict: 'Génial');
      await etat.ouvrirBooster(hasard: Random(2));
      await t.pumpWidget(AuraApp(etat: etat));
      await _patienter(t);
      await _toucher(t, 'ENTRER DANS LA SALLE');
      await _photo(t, '${appareil}_03_ce_soir');
      await _toucher(t, 'TIRER MES 3 CARTES');
      await _photo(t, '${appareil}_04_cartes');
      await _toucher(t, 'JOUER CETTE CARTE !');
      await _photo(t, '${appareil}_05_carte_revelee');
      await _toucher(t, 'C\'EST PARTI, JE LE REGARDE');
      await _photo(t, '${appareil}_06_billet');
      for (final (i, onglet) in ['PLATEAU', 'SEMAINE', 'LIGUE'].indexed) {
        await _toucher(t, onglet);
        await _photo(t, '${appareil}_0${7 + i}_${onglet.toLowerCase()}');
      }
      await _toucher(t, 'CE SOIR');
      await _ouvrir(t, const DeckEcran());
      await _photo(t, '${appareil}_10_deck');
      await _fermer(t);
      await _ouvrir(t, const CasseEcran());
      await _photo(t, '${appareil}_11_casse');
      await _fermer(t);
      await _ouvrir(t, const JusteUnFilmEcran());
      await _photo(t, '${appareil}_12_juste_un_film');
      await _fermer(t);
      await _ouvrir(t, const CampagnesEcran());
      await _photo(t, '${appareil}_13_campagnes');
      await _fermer(t);
      await _ouvrir(t, const DuelEcran());
      await _photo(t, '${appareil}_14_duel');
      await _fermer(t);
      await _ouvrir(t, const ReglagesEcran());
      await _photo(t, '${appareil}_15_reglages');
    });
  }
}
