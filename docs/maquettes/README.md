# Maquettes d'Aura

La planche du prototype, gardée dans le dépôt pour ne plus dépendre du lien privé.

- `aura-prototype.html` : la planche complète, autonome. On l'ouvre dans un navigateur : prototype jouable du téléphone, Révélation du dimanche sur la télé, et les quatre directions de style (A la salle obscure, B la table de jeu, C le moderne épuré, D le délire jeu de société). **C'est la direction D qui est retenue.**
- `telephone.source.html` : le source lisible du prototype téléphone (balisage et logique), sans les polices. C'est la référence pour les écrans, les textes et les couleurs.
- `tele-revelation.source.html` : le source de l'écran télé de la Révélation. Ancien style sombre : l'appli a désormais sa propre Révélation en direction D (`lib/screens/revelation.dart`).

Les sources utilisent le format du canevas (`sc-for`, `sc-if`, `{{…}}`) ; ils ne s'ouvrent pas seuls, il faut le fichier complet pour les voir.
