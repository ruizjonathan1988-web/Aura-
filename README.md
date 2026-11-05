# Aura

Le jeu de société du cinéma. Un jeu VJOD.

On ne fait plus défiler un catalogue : on tire trois cartes défis, on joue celle qui nous tente, et on avance sa figurine sur le plateau du mois. Le jeu ne propose de lui-même que des titres notés 3 étoiles ou plus, et ne récompense jamais le temps passé devant l'écran (3 cases par jour au maximum).

## Ce qui marche déjà

- **Ce soir** : l'envie (frissonner, rire…), la durée, puis une main de trois cartes en éventail. La carte jouée révèle le film ; on fait son pronostic, puis on valide la séance avec un billet et un Verdict.
- **Plateau** : le circuit de 30 cases du mois, ta figurine et celle de Pop, l'adversaire du mode solo, qui avance d'une case par jour.
- **Profil** : les huit profils de spectateur et leurs figurines, avec pouvoir, contrat de saison et piège.
- **Édition VJOD** : dans les réglages, branche ta bibliothèque Jellyfin. Les cartes viennent alors de tes films, et « Lancer dans VJOD » ouvre le film directement dans VJOD sur la box Android TV ou le téléphone (liens `moonfin://play?id=…`, que VJOD comprend déjà).
- Tout se joue à la télécommande : flèches, OK, Retour.

## À venir

- Les ligues entre amis (Supabase) : code d'invitation, Affiche de la semaine, Bluff, Curseur, Faussaire, Révélation du dimanche sur la télé.
- Le Duel du canapé et le test « Quel spectateur es-tu ? » à l'inscription.
- Les titres de Ma TV : il faudra ajouter dans VJOD un lien `moonfin://tmdb?…` vers sa fiche « Regarder / Demander ».

## Construire

Pas besoin de Flutter en local : chaque envoi sur `main` lance GitHub Actions, qui vérifie le code, passe les tests, et publie l'APK dans la release « derniere » (même fichier pour la télé et le téléphone) et la version web sur GitHub Pages.

Pour activer les ligues plus tard :

1. Crée un projet sur supabase.com et lance `supabase/migrations/0001_ligues.sql` dans l'éditeur SQL.
2. Ajoute dans les secrets du dépôt `SUPABASE_URL` et `SUPABASE_ANON_KEY`.

## Organisation du code

| Dossier | Contenu |
| --- | --- |
| `lib/theme` | Couleurs, polices, contours et ombres du style « matériel de jeu » |
| `lib/widgets` | Boutons qui s'enfoncent, pastilles, panneaux, titres cartoon, cartes, main en éventail, figurines |
| `lib/models` | Émotions, durées, profils, films, cartes défis |
| `lib/services` | Tirage (règle zéro navet), sources de films (démo, Jellyfin), lien VJOD, état du joueur |
| `lib/screens` | Ce soir, Plateau, Ligue, Profil, Réglages |
| `assets` | Figurines, Pop et logo VJOD |
| `supabase` | Schéma des ligues, avec sécurité par ligne et plafond de 3 cases par jour |
