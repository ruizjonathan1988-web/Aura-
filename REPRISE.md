# Reprendre le projet Aura

Document de passation : tout ce qu'il faut savoir pour continuer Aura dans une nouvelle conversation. À coller ou à faire lire en début de session.

Dernière mise à jour : 6 novembre 2026, nuit de travail autonome (voir « Nuit du 6 novembre »).

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
| R1 Zéro navet | Tirage, Plan du jour et Affiche ne proposent rien sous 6/10 ni sans assez d'avis (150, ou 30 avant 1990) ; l'Affiche n'est jamais un film déjà vu ; tirage, Plan du jour et Affiche puisent d'abord dans les 40 % les mieux notés | `Tirage.assezBon` |
| R2 3 cases par jour | La 2e carte du jour ne rapporte plus ; un film vu hier compte sur hier | `Regles.casesAccordees`, `EtatJeu.casesLe` |
| R3 Pas de points au temps passé | Un film de 5 h rapporte autant qu'un film court ; la durée ne fait que filtrer | `TypeCarte`, `Tirage` |
| R4 Revenir ne punit jamais | Une séance sans case ne fait pas reculer ; la position survit à la fermeture | `EtatJeu` |
| R5 Plateau du mois | Retour en case 1 le 1er, plafond à 30, une séance du mois dernier ne compte pas | `EtatJeu._nouveauMois` |
| R6 Plan du jour | Un seul essai par jour, 3 indices, 4 réponses à choisir | `PlanDuJour`, `EtatJeu.planDuJour` |
| R7 Affiche de la semaine | Curseur secret jusqu'au dimanche, gardé d'une ouverture à l'autre | `Affiche`, écran Semaine |
| R8 Pop | 1 case par jour, 5 triches au plus par mois, pari fixe sur la semaine, recul de 2 une seule fois par pari, toujours entre 1 et 30 | `Pop` |
| R9 Aucune séance perdue | Carte jouée gardée ; une note suffit ; billet automatique noté après coup ; Jellyfin ne compte que les films vus après la carte ; taux mesuré | `EtatJeu`, `SourceJellyfin.dateDeVisionnage` |
| R10 Tout à la télécommande | À partir de 900 de large, mode télé : les champs de texte deviennent « ça s'écrit depuis ton téléphone » | `ChampAura`, `estLargeurTele` |
| R11 Premier soir | Test équilibré (chaque profil 3 fois sur 6 questions), égalité au plus récent ; Bluff : un vrai synopsis et deux faux de Pop, jamais de navet ni de documentaire ; Joker +1 case une seule fois, plafond de 3 respecté | `TestSpectateur`, `BluffDePop`, `EtatJeu.jokerBluff` |
| R12 Carte des genres | Une séance rend la région tienne (un film peut en couvrir plusieurs) ; Pop vise une région libre chaque lundi et la prend si rien n'y est vu avant dimanche ; elle se reprend ; rien de visé avant le premier lundi ; chaque région de Pop = 1 case | `CarteDesGenres`, `Pop.position` |
| R13 Connexion VJOD | Identifiant et mot de passe, ou code Quick Connect accepté sur le téléphone, donnent une connexion complète ; mauvais mot de passe = message clair | `ConnexionVjod` |
| R14 Duel du canapé | On écarte à tour de rôle une carte de l'autre ; un Veto par joueur protège une carte ; la partie finit toujours avec une carte chacun ; quiz : 4 réponses distinctes, pas de question en double | `Duel`, `Quiz` |
| R15 Revenir après une pause | Après 3 jours d'absence, carte de rattrapage (+2 cases, plafond respecté) ; rien au premier lancement ; série en semaines, une semaine vide est une pause gratuite, deux la remettent à zéro ; un lundi matin ne fait pas perdre la série | `Fidelite`, `EtatJeu.bonRetour` |
| R16 Bluff de la semaine | Le vrai synopsis de l'Affiche est parmi trois (deux faux de Pop) ; pas de Bluff sans synopsis ; un essai par semaine ; trouvé = Joker +1 case | `BluffDePop.pourFilm`, `EtatJeu.bluffDe` |
| R17 Mesures | Une ouverture comptée par jour ; file hors ligne plafonnée à 200 ; seulement six types d'événements, sans titre de film | `ServiceMesures` |
| R18 Amis | Le fil raconte la séance d'un ami en une phrase (« Léa a vu « … » et lui donne 4 sur 5. ») ; ses propres séances à la deuxième personne | `Nouvelle` |
| R19 Animations | Coupées si l'appareil demande moins d'animations ; sinon les entrées se font en fondu | `animationsReduites`, `Entree` |
| R20 Rappel du lendemain | Un seul rappel, le lendemain à 12 h 30 ; trois boutons (Bof 2, Bien 4, Génial 5) ; noter depuis la notification valide la séance ; un simple toucher ne valide rien | `Rappels`, `EtatJeu.repondreRappel` |
| R21 Révélation du dimanche | Pari du Médium entre 0 et 10, fixe sur la semaine ; raté de 3 crans ou plus = Joker, une fois par semaine | `Affiche.pariDuMedium`, `EtatJeu.terminerRevelation` |
| R22 Collection | Exploits mérités par le jeu (première séance, Rétro, globe-trotteur, devin, Pop dépassé, Bluffs…) ; figurine de saison à la case 20, au nom du mois ; un exploit obtenu reste pour toujours | `Collection`, `EtatJeu.collection` |
| R23 Affiche en ligue | Chacun programme à son tour ; Faussaire jamais Programmateur (pas de Faussaire à deux) ; la première Affiche compte ; on départage le vrai synopsis et les faux des autres, jamais le sien, dans un ordre stable ; points : vrai trouvé +2, ami piégé +1, Curseur le plus proche de la moyenne +1, Faussaire démasqué +2, ami trompé +1 au Faussaire | `SemaineDeLigue` |
| R24 Soirée jeu | Code de 4 lettres lisibles ; de 2 à 4 joueurs, toujours un coup possible, fin avec une carte chacun, révélation dès que tous ont répondu ; chacun joue à son tour depuis son téléphone, gestes interdits refusés (pas son tour, sa propre carte, carte protégée) ; partie complète jusqu'au film du gagnant ; une seule réponse par question ; la télé révèle même si quelqu'un ne répond pas | `PartieSoiree` |
| R25 Historique Letterboxd | Le CSV se lit (virgules et guillemets) ; un film est reconnu par son titre ou son titre original, accents et articles ignorés, à un an près ; les films importés ne sont plus proposés et ne rapportent aucune case | `Historique`, `SourceAvecHistorique` |
| R26 Où voir le film | Plateformes en France seulement, abonnement d'abord ; recherche TMDB par titre et année, ou identifiant TMDB donné par Jellyfin ; si TMDB ne répond pas, rien ne s'affiche | `Plateformes`, `ServicePlateformes` |
| R27 Jokers, finale, générique | Bouclier : Pop ne prend pas la région visée cette semaine-là ; un Joker de chaque par mois ; en fin de mois, résultat contre Pop gardé, champion si devant ; générique dans l'ordre d'apparition, sans les films hors saison | `CarteDesGenres` (boucliers), `EtatJeu`, `Generique` |
| R28 Campagnes | Chaque campagne garde les 5 films les mieux notés de son thème (un par pays pour le Tour du monde) ; elle avance avec les billets et se boucle ; l'exploit n'est donné qu'une fois | `Campagnes` |
| R29 Cadeau cacheté et Flair | Scellé jusqu'au jour prévu ; dates proposées ce soir, demain, vendredi, samedi, dimanche sans doublon ; Flair = part des cadeaux notés 4 ou 5 (les non notés ne comptent pas) ; jouer un cadeau = carte à 2 cases | `Cadeau`, `Cadeaux` |

Tests d'écrans (`test/ecrans_test.dart`) : l'appli est ouverte comme par un joueur, sur un téléphone (390 × 844) et sur une télé (960 × 540) ; ouverture, premier soir complet, tous les onglets, une soirée complète (tirage, carte, billet, plateau), Plan du jour, Duel. Un débordement ou un plantage fait échouer la CI. Possible parce que les polices sont embarquées (`assets/polices`, licence OFL) au lieu d'être téléchargées.

Règles sans test automatique : « pas de pochettes surprises payantes » (rien à vendre pour l'instant), le plafond de 3 cases côté serveur (trigger SQL `plafonner_cases`, pas exécuté en CI), et la navigation aux flèches (à vérifier à la main sur la box). Exception connue à R10 : l'adresse du serveur VJOD reste modifiable au clavier dans les Réglages, mais elle est pré-remplie ; sur la télé, la connexion passe par un code Quick Connect.

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
- Ligues Supabase branchées (`lib/services/ligues.dart`) : compte anonyme avec pseudo, création de ligue, rejointe par code à 6 caractères, classement du mois (`supabase/migrations/0002_classement.sql`), séances envoyées au serveur et renvoyées si hors ligne. Projet Supabase : `trjocwmslkxtluuhsvgx` (Francfort). Adresse et clé anon dans `lib/services/config.dart` (publiques par nature ; les secrets GitHub, s'ils existent, passent avant). Les sessions ne peuvent ni écrire les secrets GitHub ni joindre Supabase (proxy) : les vérifications serveur se font par Jon. Sur la télé, la ligue s'affiche mais se gère au téléphone.
- Validation sans effort : une carte jouée devient une « séance en cours » gardée sur l'appareil. En édition VJOD, Aura demande à Jellyfin si le film a été vu (Played ou 90 %, après la carte) au démarrage et au retour dans l'appli : le billet se crée tout seul, il ne reste qu'à noter en un geste. Sinon, « Alors, ce film ? » avec les étoiles dans Ce soir. Taux cartes jouées / billets affiché dans le Profil.
- Pop adversaire (`lib/services/pop.dart`) : pari de la semaine (il recule de 2 cases s'il le perd), petites triches avouées, répliques sur le plateau et chambrage du pronostic (vraie note demandée après la séance).
- Premier soir (`lib/screens/premier_soir.dart`, `lib/services/premier_soir.dart`) : au premier lancement, Pop accueille, test « Quel spectateur es-tu ? » en 6 questions, figurine qui sort de sa boîte (copiable pour partager), puis mini-Bluff : un film de la bibliothèque (synopsis Jellyfin « Overview », ramené à sa première phrase) ou de la démo, son vrai synopsis et deux faux de Pop. Trouver le vrai donne le Joker du Bluff (+1 case sur la prochaine séance). « Refaire le test » est dans le Profil.
- Carte des genres (`lib/services/carte_genres.dart`, section du Plateau) : 8 régions (Polar, Comédie, Drame, Évasion, Animation, Frissons, Classiques avant 1980, Cinéma d'ailleurs hors France et États-Unis). Les billets gardent désormais genres, année et pays. Chaque lundi Pop vise une région libre et la prend si on ne la défend pas avant dimanche ; chacune lui vaut une case ; on la reprend en y regardant un film.
- Français relu dans toute l'appli (textes de Pop, cartes, test, profils, messages) ; genres, pays et durées traduits à l'écran (`lib/services/traduction.dart`).
- Sélection de démonstration : 42 films reconnus (classements IMDb et SensCritique), synopsis rédigés pour Aura. Le tirage garde d'abord les 40 % les mieux notés.
- Connexion VJOD pour les utilisateurs de Jon (`lib/services/connexion_vjod.dart`, Réglages) : code Quick Connect sur la télé, identifiant et mot de passe VJOD au téléphone, ou clé d'API (avancé). Plus besoin de clé d'API. Une carte « Tu utilises VJOD ? » invite à brancher sa bibliothèque depuis Ce soir. L'adresse du serveur de Jon, `https://ava88.zen.usbx.me/jellyfin`, est pré-remplie (`Config.serveurVjod`, remplaçable par `--dart-define=VJOD_SERVEUR=…`).
- Duel du canapé (`lib/screens/duel.dart`, `lib/services/duel.dart`, accès depuis Ce soir) : deux figurines, une envie chacun, 6 cartes retournées sur la table, élimination à tour de rôle avec un Veto chacun, Pop commente, mini-quiz de 6 questions sur des films reconnus (3 chacun), égalité tranchée par la meilleure note ; le gagnant « prend la télécommande » et lance le film (séance gardée pour la validation).
- Revenir sans être puni (`lib/services/fidelite.dart`) : après 3 jours d'absence, Pop accueille (« j'ai gardé ta place au chaud ») et offre une carte de rattrapage (+2 cases sur la prochaine séance). Série comptée en semaines sur le Plateau, une semaine sans film ne la casse pas.
- Pop bluffe : chaque semaine, avant la séance de l'Affiche, Bluff en solo contre Pop (trouver le vrai résumé parmi trois). Gagné = Joker +1 case. Pop se dandine quand il parle (animation légère).
- Mesures anonymes (`lib/services/mesures.dart`, `supabase/migrations/0003_mesures.sql`) : compte anonyme par appareil, événements ouverture (1 par jour), carte jouée, billet, Plan du jour, Duel, Bluff ; file d'attente hors ligne. Les quatre chiffres se lisent dans l'éditeur SQL de Supabase : `select * from public.mesures;` (retour J+1, J+7, J+30, cartes devenues billets).
- Amis (`supabase/migrations/0004_invitation.sql`, onglet Ligue) : fil de la ligue (les 8 dernières séances des membres, avec note et Verdict) ; inviter un ami qui rejoint par code donne une figurine dorée aux deux.
- Animations (`lib/widgets/animations.dart`, d'après le prototype du canevas mis à jour le 6 nov.) : ouverture en salle de cinéma à chaque lancement (rideau de velours qui s'écarte, projecteur, Pop qui tournoie, « AURA » qui claque, les 8 figurines en file, « Entrer dans la salle ») ; cartes distribuées une à une avec rebond ; carte jouée qui se retourne en affiche illustrée (rayons, cercles, titre, pastille de note) ; tampon « Vu ! » et confettis à la validation ; pion qui fait trois sauts sur sa nouvelle case ; pastilles qui rebondissent ; Pop qui arrive et se dandine. Tout est coupé si l'appareil demande moins d'animations.
- Ce soir enrichi : encarts « Ta course contre Pop » (jauge et figurines) et « Ta série » ; fil « Pendant ce temps, à la ligue » sous le tirage (ou invitation à créer sa ligue).
- Polices embarquées (Anton, Nunito 700/800/900, sous-ensemble latin, converties depuis Google Fonts) : plus de téléchargement au premier lancement, l'appli marche hors ligne sur la box. Le paquet `google_fonts` est retiré.
- Rappel du lendemain (`lib/services/rappels.dart`, Android) : quand une carte est jouée, une notification est prévue le lendemain à 12 h 30, « Alors, Le Samouraï ? », avec trois boutons de note ; un geste valide le billet. Annulée dès que plus rien n'attend. Le script `tool/configurer_android.py` ajoute la permission, les récepteurs et le désucrage Java.
- Révélation du dimanche (`lib/screens/revelation.dart`, bouton dans Semaine le dimanche) : quatre tableaux à faire défiler avec OK, en direction D, lisibles sur la télé ; Pop « le Médium » devine le Curseur (Joker s'il se trompe de 3 crans ou plus), rappel du Bluff, plateau en bandeau, carte des genres.
- Collection (`lib/services/collection.dart`, section du Profil) : 10 exploits à débloquer (gardés pour toujours, annoncés par Pop) et une figurine de saison par mois, gagnée à la case 20, qui ne revient jamais.
- Affiche de la semaine en ligue (`lib/screens/semaine_ligue.dart`, `lib/services/semaine_ligue.dart`, migration `0005_semaine_et_soiree.sql`), en haut de l'onglet Semaine quand on a une ligue : le Programmateur (chacun son tour) choisit parmi trois films, sinon Pop dès le mercredi ; chacun écrit un faux synopsis et cherche le vrai ; rôle secret Faussaire ou Témoin sur le téléphone seulement ; Curseur et Verdict ; le dimanche, vote pour démasquer le Faussaire et Révélation avec points et classement.
- Soirée jeu (`lib/screens/soiree.dart`, `lib/services/soiree.dart`, migration `0005`) : sur la télé, « Soirée jeu » ouvre un plateau avec un code de 4 lettres ; sur les téléphones, « Rejoindre une soirée jeu » avec ce code et son envie. De 2 à 4 joueurs : la télé distribue 3 cartes à chacun ; à son tour, chacun écarte en secret depuis son téléphone une carte d'un adversaire (ou une des siennes quand les autres n'en ont plus qu'une), Veto compris, puis quiz de 5 questions auquel on répond en même temps ; le gagnant lance le film. La télé tient l'état (table `soirees`) et applique les gestes des téléphones (table `soiree_actions`), interrogés toutes les 1,5 s. Accessible quand les ligues sont branchées.
- Historique Letterboxd (`lib/services/historique.dart`, Réglages, au téléphone) : on choisit le .zip exporté par Letterboxd (ou watched.csv, ratings.csv, diary.csv) ; les films déjà vus ne sont plus proposés par le tirage, l'Affiche et le Bluff. Reconnaissance par titre ou titre original (Jellyfin `OriginalTitle`, titres anglais ajoutés à la sélection de démonstration). Aucune case pour le passé, rien n'est envoyé au serveur. Trakt n'est pas fait : il faut une clé d'API Trakt au nom de Jon.
- Où voir le film (`lib/services/plateformes.dart`, `lib/widgets/ou_le_voir.dart`) : sur la carte révélée, l'Affiche, la fin du Duel et de la Soirée jeu, « Où le voir » indique la bibliothèque VJOD puis les plateformes en France (abonnement, gratuit, location, achat), avec la mention JustWatch / TMDB obligatoire. Clé d'API TMDB de Jon dans `Config.tmdbCle` (remplaçable par `--dart-define=TMDB_CLE=…`) ; TMDB demande un accord pour un usage commercial.
- Jokers du plateau (un de chaque par mois, sans ajouter de cases pour respecter R2) : Relance (nouvelle main, dans Choisis ta carte) et Bouclier (Pop ne prend pas la région visée cette semaine, sur le Plateau). Finale : au changement de mois, le résultat contre Pop est gardé ; finir devant donne l'exploit « Champion de saison ». Générique de fin (`lib/screens/generique.dart`) : il défile comme au cinéma (films dans l'ordre d'apparition, chiffres, meilleur Verdict, duel contre Pop), se copie pour être partagé, s'annonce dans Ce soir au début du mois suivant et reste accessible depuis le Plateau. Trois exploits en plus : Champion de saison, Campagne bouclée, Fin limier.
- Campagnes (`lib/services/campagnes.dart`, `lib/screens/campagnes.dart`, accès depuis Ce soir) : sept listes jouables (polar, grands classiques, tour du monde, fous rires, films qui bouleversent, animation, frissons), tirées du catalogue (sélection Aura ou bibliothèque VJOD) parmi les mieux notés ; chaque film joué est une carte Campagne à 2 cases ; boucler une campagne donne l'exploit « Campagne bouclée ».
- Cadeau cacheté et Flair (`lib/screens/cadeaux.dart`, `lib/services/cadeaux.dart`, migration `0006_cadeaux.sql`, onglet Ligue) : offrir un film à un ami de sa ligue (choix parmi 4 films très bien notés), avec un mot, à ouvrir ce soir, demain ou le week-end ; le cadeau reste scellé jusqu'au jour prévu, s'annonce dans « Pendant ce temps, à la ligue », s'ouvre, se joue (carte Cadeau à 2 cases) et se note ; le Flair de chacun est la part de ses cadeaux notés 4 ou 5 ; un cadeau qui plaît donne l'exploit « Fin limier ».
- Échange de doubles : volontairement pas fait. Aura ne distribue rien au hasard (pas de pochettes surprises), donc il n'y a pas de doubles à échanger.
- Rien à taper sur la télé : `ChampAura` se remplace par un message en mode télé (Verdict, ligues).
- Maquettes rangées dans `docs/maquettes/` (planche complète et sources lisibles).

## Nuit du 6 novembre (travail autonome)

Jon a demandé une appli « finie, présentable, jouable, rigolote, avec une forte rétention » au réveil, en suivant toutes les recommandations. Fait dans la nuit, chaque bloc en pull request fusionnée après CI verte : français relu et films reconnus ; connexion VJOD sans clé ; Duel du canapé ; retour après pause ; Bluff de la semaine ; mesures anonymes ; fil de la ligue et figurine dorée ; ouverture en salle de cinéma et animations ; polices embarquées et tests d'écrans ; rappel du lendemain ; Révélation du dimanche ; collection d'exploits ; Ce soir en deux colonnes sur la télé.

**À faire par Jon :**

1. Installer le dernier APK : https://github.com/ruizjonathan1988-web/Aura-/releases/download/derniere/aura.apk
2. ~~Migrations Supabase~~ : `0001` à `0006` lancées par Jon le 6 novembre (succès). Reste à vérifier que les connexions anonymes sont activées. Lire les chiffres avec `select * from public.mesures;`.
3. Adresse du serveur VJOD : fait, `https://ava88.zen.usbx.me/jellyfin` est pré-remplie dans les Réglages (`Config.serveurVjod`).
4. Tester sur la box : flèches et OK partout, ouverture, Duel, Révélation (le dimanche), connexion par code Quick Connect.

## Retours de Jon à traiter

- **6 nov. : « tout est mal écrit, le français est vraiment approximatif. »** Relecture complète faite dans la nuit ; à vérifier par Jon à l'usage.
- **6 nov. : « le quiz est mal écrit, les propositions de films sont franchement mauvaises. »** Fait en partie : sélection de 42 films reconnus et tirage tourné vers les mieux notés ; questions du test réécrites. Le mini-quiz du Duel porte maintenant sur des films reconnus de la sélection. À reprendre avec des bases reconnues : IMDb (Top 250, notes et nombre de votes), SensCritique (tops et notes de la communauté française), Letterboxd, TMDB. Concerne au moins le catalogue de démonstration (`SourceDemo`, 15 films choisis à la main), les questions du test « Quel spectateur es-tu ? », du mini-quiz du Duel (`docs/brouillons/duel.dart.txt`) et les faux synopsis de Pop. Demander à Jon lequel il visait en premier s'il n'a pas précisé. Licences : les jeux de données IMDb sont réservés à l'usage non commercial ; SensCritique n'a pas d'API publique ; TMDB est gratuit avec mention et demande un accord pour un usage commercial. Pour l'édition VJOD, les films viennent de sa bibliothèque Jellyfin : le seuil zéro navet peut aussi s'appuyer sur le nombre de votes TMDB/IMDb que Jellyfin récupère.

## Prochaines étapes, dans l'ordre

La priorité est la rétention : d'abord colmater les fuites, ensuite l'effet « jamais vu ».

1. Vérifier l'APK sur la box et le téléphone, et la validation automatique avec un vrai film Jellyfin.
2. Vérifier le premier soir sur la box (focus aux flèches à chaque question, animation de la boîte, Bluff avec un vrai synopsis Jellyfin en français).
3. Pop bluffe : fait (Bluff de la semaine sur l'Affiche). Carte des genres faite.
4. Revenir après une pause : fait (carte de rattrapage, série en semaines avec pauses gratuites).
5. Mesures : fait, table en place ; lire `select * from public.mesures;`.
6. Supabase : vérifier que `0001` à `0005` ont bien été lancés et que les connexions anonymes sont activées (à confirmer par Jon). Affiche en ligue et Soirée jeu faites : à essayer à plusieurs (deux téléphones et la box).
7. Duel du canapé : fait. À vérifier sur la box (focus des cartes aux flèches, lisibilité à 3 mètres).
8. Version publique : import Trakt (il faut une clé d'API Trakt), accord TMDB pour un usage commercial, licences. Faits : plateformes via TMDB, import Letterboxd, notification du lendemain.

À noter pour une future session VJOD (pas dans Aura) : ajouter dans `lib/data/services/deep_link_service.dart` un lien `moonfin://tmdb?type=movie&id=…` vers la fiche « Regarder / Demander », pour lancer aussi les titres de Ma TV.

## Ailleurs

- Bible du jeu (doc sourcé : recherches, profils, boucles, code de bonne conduite, jauge de buzz) : https://claude.ai/artifact/6Z17KcsCNCrzfhDrJmdcKt
- Maquettes et prototype interactif (canevas) : https://claude.ai/artifact/CBMHGoeQ7iWUjnuPRQ6asU (copie dans `docs/maquettes/`)

Ces deux liens sont privés au compte d'origine : pour les ouvrir depuis un autre compte, les partager d'abord depuis leur menu Partager.
