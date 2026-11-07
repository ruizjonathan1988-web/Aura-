// Tests d'écrans : on ouvre l'appli comme un joueur, sur un téléphone et
// sur une télé, et on vérifie qu'aucun écran ne plante ni ne déborde.
// (Un débordement de mise en page fait échouer le test.)

import 'package:aura/app.dart';
import 'package:aura/screens/revelation.dart';
import 'package:aura/services/affiche.dart';
import 'package:aura/services/etat.dart';
import 'package:aura/services/sources.dart';
import 'package:aura/theme/aura_theme.dart';
import 'package:aura/widgets/aura_widgets.dart';
import 'package:aura/services/premier_soir.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<EtatJeu> _etat([Map<String, Object> valeurs = const {}]) async {
  SharedPreferences.setMockInitialValues(valeurs);
  return EtatJeu(await SharedPreferences.getInstance());
}

/// Laisse passer le temps des animations (sans attendre la fin des
/// animations qui tournent en boucle, comme Pop qui se dandine).
Future<void> _patienter(WidgetTester t, [int secondes = 3]) async {
  for (var i = 0; i < secondes * 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 100));
  await t.tap(f.first);
  await _patienter(t, 1);
}

void _taille(WidgetTester t, Size logique, double densite) {
  t.view.physicalSize = logique * densite;
  t.view.devicePixelRatio = densite;
  addTearDown(t.view.reset);
}

void main() {
  for (final (nom, taille, densite) in [('téléphone', const Size(390, 844), 3.0), ('télé', const Size(960, 540), 2.0)]) {
    group('Sur $nom', () {
      testWidgets('ouverture, premier soir passé, puis tous les onglets', (t) async {
        _taille(t, taille, densite);
        final etat = await _etat();
        await t.pumpWidget(AuraApp(etat: etat));
        await _patienter(t);
        await _toucher(t, find.text('ENTRER DANS LA SALLE'));
        expect(find.text('BIENVENUE DANS AURA !'), findsWidgets);
        await _toucher(t, find.text('PASSER, JE CONNAIS LE JEU'));
        expect(etat.accueilFait, isTrue);
        for (final onglet in ['PLATEAU', 'SEMAINE', 'LIGUE', 'CE SOIR']) {
          await _toucher(t, find.text(onglet));
          expect(t.takeException(), isNull, reason: onglet);
        }
        await _patienter(t);
      });

      testWidgets('une soirée complète : tirage, carte, billet, plateau', (t) async {
        _taille(t, taille, densite);
        final etat = await _etat({'accueil_fait': true, 'tout_ouvert': true});
        await t.pumpWidget(AuraApp(etat: etat));
        await _patienter(t);
        await _toucher(t, find.text('ENTRER DANS LA SALLE'));
        expect(find.text('CE SOIR POUR TOI').evaluate().isNotEmpty || find.text('Pour toi').evaluate().isNotEmpty, isTrue);
        expect(find.text('TU TE METS COMBIEN ?'), findsOneWidget);
        await _toucher(t, find.descendant(of: find.byType(Pastille), matching: find.text('7')));
        await _toucher(t, find.text('TIRER MES 3 CARTES'));
        expect(find.text('CHOISIS TA CARTE !'), findsWidgets);
        await _toucher(t, find.text('JOUER CETTE CARTE !'));
        expect(find.text('CARTE RÉVÉLÉE !'), findsOneWidget);
        await _toucher(t, find.text('C\'EST PARTI, JE LE REGARDE'));
        expect(etat.enCours, hasLength(1));
        await _toucher(t, find.text('VALIDER ET AVANCER MON PION'));
        await _patienter(t);
        expect(etat.billets, hasLength(1));
        expect(etat.billets.single.niveau, 7);
        expect(etat.position, 4, reason: 'niveau 7 : 3 cases');
        expect(etat.enCours, isEmpty);
      });

      testWidgets('le premier soir en entier : test, figurine, Bluff', (t) async {
        _taille(t, taille, densite);
        final etat = await _etat();
        await t.pumpWidget(AuraApp(etat: etat));
        await _patienter(t);
        await _toucher(t, find.text('ENTRER DANS LA SALLE'));
        await _toucher(t, find.text('C\'EST PARTI !'));
        for (final q in TestSpectateur.questions) {
          await _toucher(t, find.text(q.reponses.first.$1));
        }
        await _patienter(t, 2);
        expect(etat.accueilFait, isFalse);
        await _toucher(t, find.text('GARDER ET JOUER CONTRE POP'));
        await _patienter(t, 2);
        // Le Bluff : on choisit le premier synopsis, puis on entre dans le jeu.
        final faux = BluffDePop.fauxDePop.firstWhere((f) => find.text(f).evaluate().isNotEmpty);
        await _toucher(t, find.text(faux));
        await _toucher(t, find.text('ENTRER DANS LE JEU'));
        expect(etat.accueilFait, isTrue);
        expect(t.takeException(), isNull);
        await _patienter(t);
      });

      testWidgets('la Révélation du dimanche se déroule jusqu\'au bout', (t) async {
        _taille(t, taille, densite);
        final affiche = Affiche.de(DateTime(2026, 11, 8), await SourceDemo().catalogue(), EtatJeu.jourDe)!;
        final etat = await _etat({'accueil_fait': true, 'curseur_${affiche.semaine}': 9});
        await t.pumpWidget(PorteeEtat(
          etat: etat,
          child: MaterialApp(theme: construireTheme(), home: Builder(builder: (c) => Scaffold(
            body: Center(child: TextButton(
              onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => RevelationEcran(affiche: affiche))),
              child: const Text('ouvrir'),
            )),
          ))),
        ));
        await _toucher(t, find.text('ouvrir'));
        for (var i = 0; i < 3; i++) {
          await _toucher(t, find.text('SUITE'));
          await _patienter(t, 2);
        }
        expect(etat.revelationFaite(affiche.semaine), isTrue);
        await _toucher(t, find.text('À LA SEMAINE PROCHAINE !'));
        await _patienter(t, 2);
        expect(find.text('ouvrir'), findsOneWidget);
      });

      testWidgets('Juste un film : trois idées, on en change une puis toutes', (t) async {
        _taille(t, taille, densite);
        final etat = await _etat({'accueil_fait': true});
        await t.pumpWidget(AuraApp(etat: etat));
        await _patienter(t);
        await _toucher(t, find.text('ENTRER DANS LA SALLE'));
        await _toucher(t, find.textContaining('PAS ENVIE DE JOUER'));
        await _patienter(t, 2);
        expect(find.text('JUSTE UN FILM'), findsWidgets);
        expect(find.text('UNE AUTRE IDÉE'), findsNWidgets(3));
        await _toucher(t, find.text('UNE AUTRE IDÉE'));
        await _toucher(t, find.text('Réfléchir'));
        await _toucher(t, find.text('TROIS AUTRES IDÉES'));
        expect(find.text('UNE AUTRE IDÉE'), findsNWidgets(3));
        expect(etat.enCours, isEmpty);
        expect(etat.billets, isEmpty);
        expect(t.takeException(), isNull);
        t.state<NavigatorState>(find.byType(Navigator).first).pop();
        await _patienter(t, 2);
      });

      testWidgets('La Soirée jeu ouvre le Duel du canapé sans souci', (t) async {
        _taille(t, taille, densite);
        final etat = await _etat({'accueil_fait': true});
        await t.pumpWidget(AuraApp(etat: etat));
        await _patienter(t);
        await _toucher(t, find.text('ENTRER DANS LA SALLE'));
        await _toucher(t, find.textContaining('SOIRÉE JEU'));
        await _patienter(t, 1);
        await _toucher(t, find.textContaining('LE DUEL DU CANAPÉ'));
        await _toucher(t, find.text('C\'EST PARTI'));
        await _patienter(t, 1);
        expect(t.takeException(), isNull);
        t.state<NavigatorState>(find.byType(Navigator).first).pop();
        await _patienter(t, 2);
      });
    });
  }
}
