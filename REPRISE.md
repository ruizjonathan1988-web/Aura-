# Reprendre le projet Aura

Document de passation : tout ce qu'il faut savoir pour continuer Aura dans une nouvelle conversation. À coller ou à faire lire en début de session.

Dernière mise à jour : 5 novembre 2026, après la validation automatique, Pop adversaire et le fichier des règles.

## Qui et quoi

Jon, éducateur spécialisé et développeur pour son usage, en France. Tout est en français : réponses et textes d'interface. Il préfère une prose naturelle, des échanges directs et concis, et des améliorations par petites touches plutôt que des réécritures complètes.

Il maintient :

- **VJOD** : son client Jellyfin en Flutter (fork de Moonfin), dépôt `ruizjonathan1988-web/Vjod-moon`, branche de publication `perso`. On n'y touche pas depuis Aura.
- **IPTV Checker / Ma TV** : outil Python sur une seedbox Ultra.cc qui trie les comptes IPTV et sert direct, replay et catalogue VOD à VJOD.
- Un serveur maison avec Jellyfin, Seerr, Prowlarr et qBittorrent.

**Aura** est une application nouvelle, distincte de VJOD : un jeu de société du cinéma qui règle le « qu'est-ce qu'on regarde ce soir ? ». Dépôt : `ruizjonathan1988-web/Aura-` (branche `main`).

## Méthode de travail

Jon travaille avec des crédits limités et plusieurs comptes : ce fichier remplace toute réexplication. À chaque session :

1. Lire ce fichier en entier avant de toucher au code.
2. Travailler sur une branche, ouvrir une pull request, attendre la CI verte (analyse, tests, APK), puis fusionner dans `main`. La fusion publie l'APK.
3. Toute règle du jeu nouvelle ou modifiée a son test dans `test/regles_test.dart`, numéroté comme dans le tableau ci-dessous. Un test qui casse veut dire qu'une règle a bougé : on le décide exprès, jamais en passant.
4. Avant de finir, mettre à jour ce fichier : date en haut, « Fait », « Prochaines étapes », tableau des règles. Petites touches, pas de réécriture.

Pas de Flutter dans l'environnement des sessions (le téléchargement du SDK Dart est bloqué) : c'est la CI qui compile et teste. Écrire le code avec soin, puis lire l'onglet Actions de la pull request.

## Le concept

Aura est un jeu de plateau dont le dé est le film. Pas de défilement de catalogue : on tire trois cartes défis, on joue celle qui tente, et on avance sa figurine sur le plateau du mois.

Positionnement : les autres applis (Queue, OneMovie, JustWatch, Letterboxd…) aident à choisir un film. Aura transforme ton mois de cinéma en partie de jeu de société. Le choix rapide est un bénéfice, pas la promesse.

Les règles qui ne se discutent pas :

- **Zéro navet** : tout ce que le jeu propose de lui-même a au moins 3 étoiles sur 5 (6/10 TMDB), avec assez d'avis (seuil d'avis plus bas pour les films anciens). Les amis restent libres de conseiller ce qu'ils veulent ; le Flair sanctionne les navets.
- **Jamais de points au temps passé** : 3 cases par jour au maximum. Série comptée en semaines, pauses gratuites, pas de message culpabilisant.
- **Pas de pochettes surprises payantes.** Monétisation éventuelle : packs à thème vendus clairement, ligues plus grandes, cosmétique.
- **La télé est partagée** : rien de secret à l'écran (rôles cachés, notes) ; les secrets restent sur le téléphone.
- **Tout se joue à la télécommande** : flèches, OK, Retour. Pas de saisie de texte sur la télé.

## Les règles et leurs tests

Chaque règle est protégée par des tests `Rn` dans `test/regles_test.dart` (les tests plus anciens de `test/jeu_test.dart` restent valables).

| Règle | Ce qui est vérifié | Où dans le code |
|---|---|---|
| R1 Zéro navet | Tirage, Plan du jour et Affiche ne proposent rien sous 6/10 ni sans assez d'avis (150, ou 30 avant 1990) ; l'Affiche n'est jamais un film déjà vu | `Tirage.assezBon` |
| R2 3 cases par jour | La 2e carte du jour ne rapporte plus ; un film vu hier compte sur hier | `Regles.casesAccordees`, `EtatJeu.casesLe` |
| R3 Pas de points au temps passé | Un film de 5 h rapporte autant qu'un film court ; la durée ne fait que filtrer | `TypeCarte`, `Tirage` |
| R4 Revenir ne punit jamais | Une séance sans case ne fait pas reculer ; la position survit à la fermeture | `EtatJeu` |
| R5 Plateau du mois | Retour en case 1 le 1er, plafond à 30, une séance du mois dernier ne compte pas | `EtatJeu._nouveauMois` |
| R6 Plan du jour | Un seul essai par jour, 3 indices, 4 réponses à choisir | `PlanDuJour`, `EtatJeu.planDuJour` |
| R7 Affiche de la semaine | Curseur secret jusqu'au dimanche, gardé d'une ouverture à l'autre | `Affiche`, écran Semaine |
| R8 Pop | 1 case par jour, 5 triches au plus par mois, pari fixe sur la semaine, recul de 2 une seule fois par pari, toujours entre 1 et 30 | `Pop` |
| R9 Aucune séance perdue | Carte jouée gardée ; une note suffit ; billet automatique noté après coup ; Jellyfin ne compte que les films vus après la carte ; taux mesuré | `EtatJeu`, `SourceJellyfin.dateDeVisionnage` |
| R10 Tout à la télécommande | À partir de 900 de large, mode télé : les champs de texte deviennent « ça s'écrit depuis ton téléphone » | `ChampAura`, `estLargeurTele` |

Règles sans test automatique : « pas de pochettes surprises payantes » (rien à vendre pour l'instant), le plafond de 3 cases côté serveur (trigger SQL `plafonner_cases`, pas exécuté en CI), et la navigation aux flèches (à vérifier à la main sur la box). Exception connue à R10 : les Réglages Jellyfin demandent encore l'adresse et la clé au clavier.

## Les rythmes du jeu

Tous asynchrones, personne ne regarde en même temps :

- **Chaque jour** : le Plan du jour (un film à deviner en 3 indices, résultat partageable sans spoiler).
- **Chaque soir** : Ce soir (envie, durée, plateformes, puis 3 cartes défis en éventail ; pronostic avant, billet et Verdict après).
- **Chaque semaine** : l'Affiche de la semaine (film choisi par le Programmateur, dispo chez tous) avec Bluff (faux synopsis), Curseur (deviner les ressentis), Faussaire (rôle caché qui n'a pas vu le film), Révélation le dimanche sur la télé.
- **Chaque mois** : la saison sur le plateau (30 cases, carte des genres, Jokers, alliances, finale, générique de fin à partager). En solo, on affronte Pop, qui avance d'une case par jour.

Les huit profils de spectateur (chacun a sa figurine, un pouvoir, un contrat de saison et un piège) : Dévoreur, Dégustateur, Explorateur, Critique, Fidèle, Supporter, Hôte, Pressé.

La collection : figurines de base (les 8 profils), figurines de saison (un thème par mois, jamais rééditées), variantes rares débloquées par des exploits, échange de doubles entre amis.

Le social : Verdict en une phrase, Flair (réputation de prescripteur : tes conseils qui plaisent), listes à voir absolument jouables comme des campagnes, Cadeau cacheté (offrir un film à ouvrir plus tard).

## L'identité visuelle

Style « jeu de société moderne » (inspiration : Magical Athlete / Mild Mile, sans copier leurs personnages), lié à VJOD :

- Fond rouge VJOD `#E5261F` tramé de points ; contours noirs épais `#141414` ; ombres franches décalées ; carton crème `#F6EFE2` ; boutons ambre VJOD `#F2A93B` qui s'enfoncent ; jaune `#FFD23F` pour la sélection et le focus.
- Titres en Anton (la police condensée de VJOD) en capitales, contour noir et ombre ; texte en Nunito gras.
- Cartes défis : cadre de couleur, nom en haut, fenêtre en rayons de soleil avec un « ? », encart blanc.
- Plateau : circuit noir aux coins arrondis, filet blanc, cases vives (orange, rose, vert, bleu, rouge numérotées tous les 5), panneau central avec podium.
- Figurines : personnages délirants sur arche de couleur et socle en bois (`assets/figurines`).
- **Pop** : mascotte VJOD, pot de pop-corn rayé rouge et crème, yeux qui partent chacun de leur côté, étiquette au vrai logo VJOD. C'est aussi le Programmateur et l'adversaire du solo (`assets/marque/pop.png`).
- Logo VJOD détouré : `assets/marque/vjod-transparent.png`, et `vjod-contour.png` (contour noir) pour les fonds rouges.

## L'état du code

Flutter (Android TV, téléphone, web). Pas de Flutter en local : GitHub Actions (`.github/workflows/construire.yml`) génère les dossiers natifs avec `flutter create`, configure le manifeste Android (`tool/configurer_android.py` : leanback, nom, réseau, droit d'ouvrir `moonfin://`), analyse, teste, puis publie l'APK dans la release `derniere` et le web sur GitHub Pages.

Fait :

- Ce soir (envie, durée, main de 3 cartes en éventail, pronostic, billet et Verdict).
- Plateau du mois contre Pop, profils et figurines, réglages.
- Tirage avec règle zéro navet et plafond de 3 cases par jour (`lib/services/tirage.dart`).
- Tests : une règle, un test, dans `test/regles_test.dart` (voir le tableau plus haut) ; tests historiques dans `test/jeu_test.dart`.
- Édition VJOD : source Jellyfin (`MinCommunityRating=6`) et lancement direct dans VJOD par `moonfin://play?id=<itemId>&serverId=<serverId>`, que VJOD comprend déjà.
- Onglets alignés sur le prototype : Ce soir, Plateau, Semaine, Ligue ; le Profil s'ouvre par la pastille ronde en haut, la pastille des pions mène à la Ligue, les Réglages sont en bas du Profil.
- Plan du jour (`lib/services/plan_du_jour.dart`) : même film pour tous le même jour, 3 indices à ouvrir, 1 essai parmi 4 titres (rien à taper), résultat à copier sans spoiler.
- Semaine en solo : Affiche choisie par Pop (même film du lundi au dimanche), séance à +2 cases, Curseur secret, Révélation le dimanche. Bluff et Faussaire attendent les ligues.
- Plateau du mois : la position repart de la case 1 le 1er du mois.
- Ligues Supabase branchées (`lib/services/ligues.dart`) : compte anonyme avec pseudo, création de ligue, rejointe par code à 6 caractères, classement du mois (`supabase/migrations/0002_classement.sql`), séances envoyées au serveur et renvoyées si hors ligne. Sans les secrets, l'appli reste en solo. Sur la télé, la ligue s'affiche mais se gère au téléphone.
- Validation sans effort : une carte jouée devient une « séance en cours » gardée sur l'appareil. En édition VJOD, Aura demande à Jellyfin si le film a été vu (Played ou 90 %, après la carte) au démarrage et au retour dans l'appli : le billet se crée tout seul, il ne reste qu'à noter en un geste. Sinon, « Alors, ce film ? » avec les étoiles dans Ce soir. Taux cartes jouées / billets affiché dans le Profil.
- Pop adversaire (`lib/services/pop.dart`) : pari de la semaine (il recule de 2 cases s'il le perd), petites triches avouées, répliques sur le plateau et chambrage du pronostic (vraie note demandée après la séance).
- Rien à taper sur la télé : `ChampAura` se remplace par un message en mode télé (Verdict, ligues).
- Maquettes rangées dans `docs/maquettes/` (planche complète et sources lisibles).

## Prochaines étapes, dans l'ordre

La priorité est la rétention : d'abord colmater les fuites, ensuite l'effet « jamais vu ».

1. Vérifier l'APK sur la box et le téléphone, et la validation automatique avec un vrai film Jellyfin.
2. Le premier soir en trois minutes : test « Quel spectateur es-tu ? », figurine qui sort de sa boîte, puis mini-Bluff contre Pop (deux faux synopsis, trouver le vrai, gagner sa première carte).
3. Pop, suite : il prend une région de la carte des genres si on ne la défend pas, il bluffe.
4. Revenir après une pause sans être puni : Pop garde ta place, carte de rattrapage.
5. Mesurer : retour J+1, J+7, J+30 et taux cartes jouées / billets (le taux est déjà compté sur l'appareil ; à remonter dans Supabase).
6. Activer Supabase (lancer `0001` puis `0002`, connexions anonymes, secrets `SUPABASE_URL` et `SUPABASE_ANON_KEY`), puis les événements d'amis (« Léa a deviné ton Curseur ») et la figurine débloquée pour les deux quand on invite un ami.
7. Le Duel du canapé : la logique est prête dans `docs/brouillons/duel.dart.txt`, à remettre dans `lib/services/` (6 cartes, écarts à tour de rôle, un Veto chacun, mini-quiz de cinéma).
8. Version publique : notification du lendemain « Alors, Le Samouraï ? » avec les étoiles, plateformes via TMDB (JustWatch), import Letterboxd ou Trakt, licences.

À noter pour une future session VJOD (pas dans Aura) : ajouter dans `lib/data/services/deep_link_service.dart` un lien `moonfin://tmdb?type=movie&id=…` vers la fiche « Regarder / Demander », pour lancer aussi les titres de Ma TV.

## Ailleurs

- Bible du jeu (doc sourcé : recherches, profils, boucles, code de bonne conduite, jauge de buzz) : https://claude.ai/artifact/6Z17KcsCNCrzfhDrJmdcKt
- Maquettes et prototype interactif (canevas) : https://claude.ai/artifact/CBMHGoeQ7iWUjnuPRQ6asU (copie dans `docs/maquettes/`)

Ces deux liens sont privés au compte d'origine : pour les ouvrir depuis un autre compte, les partager d'abord depuis leur menu Partager.
