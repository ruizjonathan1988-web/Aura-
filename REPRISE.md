# Reprendre le projet Aura

Document de passation : tout ce qu'il faut savoir pour continuer Aura dans une nouvelle conversation. À coller ou à faire lire en début de session.

## Qui et quoi

Jon, éducateur spécialisé et développeur pour son usage, en France. Tout est en français : réponses et textes d'interface. Il préfère une prose naturelle, des échanges directs et concis, et des améliorations par petites touches plutôt que des réécritures complètes.

Il maintient :

- **VJOD** : son client Jellyfin en Flutter (fork de Moonfin), dépôt `ruizjonathan1988-web/Vjod-moon`, branche de publication `perso`. On n'y touche pas depuis Aura.
- **IPTV Checker / Ma TV** : outil Python sur une seedbox Ultra.cc qui trie les comptes IPTV et sert direct, replay et catalogue VOD à VJOD.
- Un serveur maison avec Jellyfin, Seerr, Prowlarr et qBittorrent.

**Aura** est une application nouvelle, distincte de VJOD : un jeu de société du cinéma qui règle le « qu'est-ce qu'on regarde ce soir ? ». Dépôt : `ruizjonathan1988-web/Aura-` (branche `main`).

## Le concept

Aura est un jeu de plateau dont le dé est le film. Pas de défilement de catalogue : on tire trois cartes défis, on joue celle qui tente, et on avance sa figurine sur le plateau du mois.

Positionnement : les autres applis (Queue, OneMovie, JustWatch, Letterboxd…) aident à choisir un film. Aura transforme ton mois de cinéma en partie de jeu de société. Le choix rapide est un bénéfice, pas la promesse.

Les règles qui ne se discutent pas :

- **Zéro navet** : tout ce que le jeu propose de lui-même a au moins 3 étoiles sur 5 (6/10 TMDB), avec assez d'avis (seuil d'avis plus bas pour les films anciens). Les amis restent libres de conseiller ce qu'ils veulent ; le Flair sanctionne les navets.
- **Jamais de points au temps passé** : 3 cases par jour au maximum. Série comptée en semaines, pauses gratuites, pas de message culpabilisant.
- **Pas de pochettes surprises payantes.** Monétisation éventuelle : packs à thème vendus clairement, ligues plus grandes, cosmétique.
- **La télé est partagée** : rien de secret à l'écran (rôles cachés, notes) ; les secrets restent sur le téléphone.
- **Tout se joue à la télécommande** : flèches, OK, Retour. Pas de saisie de texte sur la télé.

Les rythmes du jeu (tous asynchrones, personne ne regarde en même temps) :

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
- Tirage avec règle zéro navet et plafond de 3 cases par jour (`lib/services/tirage.dart`), tests dans `test/jeu_test.dart`.
- Édition VJOD : source Jellyfin (`MinCommunityRating=6`) et lancement direct dans VJOD par `moonfin://play?id=<itemId>&serverId=<serverId>`, que VJOD comprend déjà.
- Onglets alignés sur le prototype : Ce soir, Plateau, Semaine, Ligue ; le Profil s'ouvre par la pastille ronde en haut, la pastille des pions mène à la Ligue, les Réglages sont en bas du Profil.
- Plan du jour (`lib/services/plan_du_jour.dart`) : même film pour tous le même jour, 3 indices à ouvrir, 1 essai parmi 4 titres (rien à taper), résultat à copier sans spoiler.
- Semaine en solo : Affiche choisie par Pop (même film du lundi au dimanche), séance à +2 cases, Curseur secret, Révélation le dimanche. Bluff et Faussaire attendent les ligues.
- Plateau du mois : la position repart de la case 1 le 1er du mois.
- Ligues Supabase branchées (`lib/services/ligues.dart`) : compte anonyme avec pseudo, création de ligue, rejointe par code à 6 caractères, classement du mois (`supabase/migrations/0002_classement.sql`), séances envoyées au serveur et renvoyées si hors ligne. Sans les secrets, l'appli reste en solo. Sur la télé, la ligue s'affiche mais se gère au téléphone.
- Maquettes rangées dans `docs/maquettes/` (planche complète et sources lisibles).

## Prochaines étapes, dans l'ordre

1. Vérifier l'APK sur la box et le téléphone ; régler la navigation à la télécommande si besoin.
2. Activer Supabase : créer le projet, lancer `0001_ligues.sql` puis `0002_classement.sql` dans l'éditeur SQL, activer les connexions anonymes (Authentication > Sign In / Providers), ajouter les secrets `SUPABASE_URL` et `SUPABASE_ANON_KEY` au dépôt. Ensuite : relier la télé au compte du téléphone (code à afficher sur la télé).
3. Le test « Quel spectateur es-tu ? » à l'inscription, avec la révélation de la figurine à partager.
4. Le Duel du canapé : chacun tire ses cartes, on les pose sur la télé, élimination à tour de rôle, cartes Veto et Jokers, mini-quiz dont le gagnant prend la télécommande.
5. Le mode « Soirée jeu » sur la télé (plateau en grand, téléphones en manettes).
6. L'Affiche de la semaine : Bluff, Curseur, Faussaire, Révélation.
7. Version publique : plateformes de chaque titre via TMDB (données JustWatch, mention obligatoire), import de l'historique Letterboxd ou Trakt, licences de données à vérifier (TMDB demande un accord pour un usage commercial).

À noter pour une future session VJOD (pas dans Aura) : ajouter dans `lib/data/services/deep_link_service.dart` un lien `moonfin://tmdb?type=movie&id=…` vers la fiche « Regarder / Demander », pour lancer aussi les titres de Ma TV.

## Ailleurs

- Bible du jeu (doc sourcé : recherches, profils, boucles, code de bonne conduite, jauge de buzz) : https://claude.ai/artifact/6Z17KcsCNCrzfhDrJmdcKt
- Maquettes et prototype interactif (canevas) : https://claude.ai/artifact/CBMHGoeQ7iWUjnuPRQ6asU (copie dans `docs/maquettes/`)

Ces deux liens sont privés au compte d'origine : pour les ouvrir depuis un autre compte, les partager d'abord depuis leur menu Partager.
